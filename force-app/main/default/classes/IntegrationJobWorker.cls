// IntegrationJobWorker.cls
// Purpose:
//  - Execute integration jobs asynchronously (Queueable).
//  - Bulk-safe processing of multiple jobs in a batch.
//  - Enforce CRUD (object-level) for business data.
//  - Build payloads using Integration_Field_Map_Config__c.
//  - Implement retry logic based on Integration_System_Config__c.MaxRetries__c.
//
// v2 – CONFIG SOURCE CHANGE
//  - Original version used:
//      * Integration_System__mdt
//      * Integration_Object_Config__mdt
//      * Integration_Field_Map__mdt
//  - This version now uses custom objects managed by the Admin UI:
//      * Integration_System_Config__c
//          - DeveloperName__c      – system key, matches job.SystemApiName__c
//          - IsActive__c
//          - HandlerClass__c
//          - MaxRetries__c
//      * Integration_Object_Rule__c
//          - SObjectName__c
//          - SystemDeveloperName__c
//          - TriggerReason__c
//          - IsActive__c
//      * Integration_Field_Map_Config__c
//          - SObjectName__c
//          - SystemDeveloperName__c
//          - SourceFieldAPI__c
//          - TargetFieldName__c
//          - IsRequired__c
//          - DataType__c
//
// NOTE:
//  - Field-level FLS enforcement via Security.stripInaccessible is not used here
//    due to API compatibility. We still enforce object-level access via
//    DescribeSObjectResult.isAccessible() and rely on admin-selected mappings.

public with sharing class IntegrationJobWorker
    implements Queueable, Database.AllowsCallouts {

    private List<Id> jobIds;

    public IntegrationJobWorker(List<Id> jobIds) {
        this.jobIds = jobIds;
    }

    public void execute(QueueableContext qc) {
        if (jobIds == null || jobIds.isEmpty()) return;

        // CRUD: ensure we may update Integration_Job__c
        if (!Integration_Job__c.SObjectType.getDescribe().isUpdateable()) {
            throw new SecurityException(
                'User does not have permission to update Integration_Job__c records.'
            );
        }

        // Lock jobs to avoid concurrent updates
        List<Integration_Job__c> jobs = [
            SELECT Id, SObjectName__c, RecordId__c, SystemApiName__c,
                   TriggerReason__c, Status__c, RetryCount__c, LastError__c,
                   LastAttemptAt__c
            FROM Integration_Job__c
            WHERE Id IN :jobIds
            FOR UPDATE
        ];
        if (jobs.isEmpty()) return;

        // Collect distinct names
        Set<String> systemNames    = new Set<String>();
        Set<String> sObjNames      = new Set<String>();
        Set<String> triggerReasons = new Set<String>();

        for (Integration_Job__c job : jobs) {
            systemNames.add(job.SystemApiName__c);
            sObjNames.add(job.SObjectName__c);
            triggerReasons.add(job.TriggerReason__c);
        }

        //
        // CONFIG LOAD (custom objects instead of CMDT)
        //

        // 1) Load system configs (Integration_System_Config__c) – 1 SOQL
        Map<String, Integration_System_Config__c> systemsByName =
            new Map<String, Integration_System_Config__c>([
                SELECT Id,
                       DeveloperName__c,
                       IsActive__c,
                       HandlerClass__c,
                       MaxRetries__c
                FROM Integration_System_Config__c
                WHERE DeveloperName__c IN :systemNames
            ]);

        // 2) Load object rules (Integration_Object_Rule__c) – 1 SOQL
        List<Integration_Object_Rule__c> objRules = [
            SELECT Id,
                   SObjectName__c,
                   SystemDeveloperName__c,
                   TriggerReason__c,
                   IsActive__c
            FROM Integration_Object_Rule__c
            WHERE SObjectName__c         IN :sObjNames
              AND SystemDeveloperName__c IN :systemNames
              AND TriggerReason__c       IN :triggerReasons
              AND IsActive__c = true
        ];

        // Key: "<SObjectName>|<SystemDeveloperName>|<TriggerReason>"
        Map<String, Integration_Object_Rule__c> objRuleByKey =
            new Map<String, Integration_Object_Rule__c>();
        for (Integration_Object_Rule__c rule : objRules) {
            String key = rule.SObjectName__c
                       + '|' + rule.SystemDeveloperName__c
                       + '|' + rule.TriggerReason__c;
            objRuleByKey.put(key, rule);
        }

        // 3) Load field mappings (Integration_Field_Map_Config__c) – 1 SOQL
        List<Integration_Field_Map_Config__c> fieldMaps = [
            SELECT Id,
                   SObjectName__c,
                   SystemDeveloperName__c,
                   SourceFieldAPI__c,
                   TargetFieldName__c,
                   IsRequired__c,
                   DataType__c
            FROM Integration_Field_Map_Config__c
            WHERE SObjectName__c         IN :sObjNames
              AND SystemDeveloperName__c IN :systemNames
        ];

        // Key: "<SObjectName>|<SystemDeveloperName>"
        Map<String, List<Integration_Field_Map_Config__c>> fieldMapsByKey =
            new Map<String, List<Integration_Field_Map_Config__c>>();

        for (Integration_Field_Map_Config__c fm : fieldMaps) {
            String key = fm.SObjectName__c + '|' + fm.SystemDeveloperName__c;
            List<Integration_Field_Map_Config__c> bucket = fieldMapsByKey.get(key);
            if (bucket == null) {
                bucket = new List<Integration_Field_Map_Config__c>();
                fieldMapsByKey.put(key, bucket);
            }
            bucket.add(fm);
        }

        //
        // Load source records (with object-level CRUD checks)
        //
        Map<String, Map<Id, SObject>> recordsByType = loadAndSecureRecords(jobs);

        List<Integration_Job__c> jobsToUpdate = new List<Integration_Job__c>();
        List<Integration_Job__c> jobsToRetry  = new List<Integration_Job__c>();

        for (Integration_Job__c job : jobs) {
            // Resolve system config
            Integration_System_Config__c sys = systemsByName.get(job.SystemApiName__c);
            if (sys == null || !sys.IsActive__c) {
                job.Status__c    = 'Permanent_Failed';
                job.LastError__c = 'System not configured or inactive';
                jobsToUpdate.add(job);
                continue;
            }

            // Resolve object rule
            String objKey = job.SObjectName__c
                          + '|' + job.SystemApiName__c
                          + '|' + job.TriggerReason__c;
            Integration_Object_Rule__c objRule = objRuleByKey.get(objKey);
            if (objRule == null) {
                job.Status__c    = 'Permanent_Failed';
                job.LastError__c = 'Object rule not found';
                jobsToUpdate.add(job);
                continue;
            }

            // Resolve source record
            Map<Id, SObject> recsMap = recordsByType.get(job.SObjectName__c);
            if (recsMap == null) {
                job.Status__c    = 'Permanent_Failed';
                job.LastError__c = 'No records loaded for ' + job.SObjectName__c;
                jobsToUpdate.add(job);
                continue;
            }

            SObject record = recsMap.get((Id) job.RecordId__c);
            if (record == null) {
                job.Status__c    = 'Permanent_Failed';
                job.LastError__c = 'Record not found';
                jobsToUpdate.add(job);
                continue;
            }

            // Resolve field mappings
            String fmKey = job.SObjectName__c + '|' + job.SystemApiName__c;
            List<Integration_Field_Map_Config__c> mappings = fieldMapsByKey.get(fmKey);
            if (mappings == null || mappings.isEmpty()) {
                job.Status__c    = 'Permanent_Failed';
                job.LastError__c = 'No field mappings found';
                jobsToUpdate.add(job);
                continue;
            }

            // Build payload (required fields enforced)
            Map<String, Object> payload =
                buildPayloadFromFieldMaps(record, mappings, job);

            // buildPayloadFromFieldMaps may set job.Status__c = 'Permanent_Failed'
            if ('Permanent_Failed'.equals(job.Status__c)) {
                jobsToUpdate.add(job);
                continue;
            }

            // Resolve adapter via HandlerClass__c
            IIntegrationAdapter adapter;
            try {
                adapter = (IIntegrationAdapter) Type.forName(sys.HandlerClass__c).newInstance();
            } catch (Exception ex) {
                job.Status__c    = 'Permanent_Failed';
                job.LastError__c = 'Handler class error: ' + ex.getMessage();
                jobsToUpdate.add(job);
                continue;
            }

            // Build context
            IntegrationContext ctx = new IntegrationContext();
            ctx.record       = record;
            ctx.systemConfig = sys;      // Integration_System_Config__c
            ctx.objectConfig = objRule;  // Integration_Object_Rule__c
            ctx.payload      = payload;

            IntegrationResult result;
            try {
                result = adapter.send(ctx);
            } catch (Exception ex) {
                Boolean temp = (ex instanceof CalloutException);
                result = temp
                    ? IntegrationResult.tempError(null, ex.getMessage())
                    : IntegrationResult.permanentError(null, ex.getMessage());
            }

            job.LastAttemptAt__c = System.now();

            Integer maxRetries = 0;
            if (sys.MaxRetries__c != null) {
                maxRetries = Integer.valueOf(sys.MaxRetries__c.intValue());
            }
            Integer currentRetries = (job.RetryCount__c == null)
                ? 0
                : Integer.valueOf(job.RetryCount__c);

            if (result.isSuccess) {
                job.Status__c    = 'Success';
                job.LastError__c = null;
                jobsToUpdate.add(job);
            } else if (result.isTemporaryError && currentRetries < maxRetries) {
                job.RetryCount__c = currentRetries + 1;
                job.Status__c     = 'Temp_Failed';
                job.LastError__c  = result.message;
                jobsToUpdate.add(job);
                jobsToRetry.add(job);
            } else {
                job.Status__c    = 'Permanent_Failed';
                job.LastError__c = result.message;
                jobsToUpdate.add(job);
            }
        }

        if (!jobsToUpdate.isEmpty()) {
            update jobsToUpdate;
        }

        if (!jobsToRetry.isEmpty()) {
            List<Id> retryIds = new List<Id>();
            for (Integration_Job__c j : jobsToRetry) {
                retryIds.add(j.Id);
            }
            System.enqueueJob(new IntegrationJobWorker(retryIds));
        }
    }

    // Bulk + object-level-secure load of source records
    private static Map<String, Map<Id, SObject>> loadAndSecureRecords(
        List<Integration_Job__c> jobs
    ) {
        Map<String, Set<Id>> idsByType = new Map<String, Set<Id>>();

        for (Integration_Job__c job : jobs) {
            if (!idsByType.containsKey(job.SObjectName__c)) {
                idsByType.put(job.SObjectName__c, new Set<Id>());
            }
            idsByType.get(job.SObjectName__c).add((Id) job.RecordId__c);
        }

        Map<String, Map<Id, SObject>> result =
            new Map<String, Map<Id, SObject>>();

        for (String sObjName : idsByType.keySet()) {
            Schema.SObjectType sType = Schema.getGlobalDescribe().get(sObjName);
            if (sType == null) continue;

            Schema.DescribeSObjectResult d = sType.getDescribe();

            // CRUD: object-level access
            if (!d.isAccessible()) {
                // Jobs for this type will be marked as failed later.
                continue;
            }

            String soql =
                'SELECT FIELDS(ALL) FROM ' + sObjName + ' WHERE Id IN :idsByType.get(sObjName)';
            List<SObject> recs = Database.query(soql);

            // NOTE: We are not calling Security.stripInaccessible here due to
            //       API compatibility in this org. If you upgrade the API
            //       version and have Security.stripInaccessible available,
            //       you can add a field-level FLS enforcement step here.

            result.put(sObjName, new Map<Id, SObject>(recs));
        }

        return result;
    }

    // Build payload from Integration_Field_Map_Config__c rows
    private static Map<String, Object> buildPayloadFromFieldMaps(
        SObject record,
        List<Integration_Field_Map_Config__c> mappings,
        Integration_Job__c job
    ) {
        Map<String, Object> payload = new Map<String, Object>();

        for (Integration_Field_Map_Config__c fm : mappings) {
            String sourceApi  = fm.SourceFieldAPI__c;
            String targetName = String.isBlank(fm.TargetFieldName__c)
                ? sourceApi
                : fm.TargetFieldName__c;

            Object value;
            try {
                value = record.get(sourceApi);
            } catch (Exception ex) {
                job.Status__c    = 'Permanent_Failed';
                job.LastError__c =
                    'Error reading field ' + sourceApi + ': ' + ex.getMessage();
                break;
            }

            if (fm.IsRequired__c && value == null) {
                job.Status__c    = 'Permanent_Failed';
                job.LastError__c =
                    'Required field ' + sourceApi + ' is null or not accessible';
                break;
            }

            payload.put(targetName, value);
        }

        return payload;
    }
}
