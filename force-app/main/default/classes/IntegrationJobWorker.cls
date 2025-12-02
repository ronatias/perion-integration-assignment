// IntegrationJobWorker.cls
// Purpose:
//  - Execute integration jobs asynchronously (Queueable).
//  - Bulk-safe processing of multiple jobs in a batch.
//  - Enforce CRUD/FLS for business data.
//  - Use Integration_Field_Map__mdt for payload mapping.
//  - Implement retry logic based on Integration_System__mdt.MaxRetries__c.
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
                   TriggerReason__c, Status__c, RetryCount__c, LastError__c
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

        // Load system configs (1 SOQL)
        Map<String, Integration_System__mdt> systemsByName =
            new Map<String, Integration_System__mdt>([
                SELECT DeveloperName, IsActive__c, HandlerClass__c, MaxRetries__c
                FROM Integration_System__mdt
                WHERE DeveloperName IN :systemNames
            ]);

        // Load object configs (1 SOQL)
        List<Integration_Object_Config__mdt> objConfigs = [
            SELECT SObjectName__c, SystemApiName__c, TriggerReason__c, IsActive__c
            FROM Integration_Object_Config__mdt
            WHERE SObjectName__c IN :sObjNames
              AND SystemApiName__c IN :systemNames
              AND TriggerReason__c IN :triggerReasons
              AND IsActive__c = true
        ];

        Map<String, Integration_Object_Config__mdt> objCfgByKey =
            new Map<String, Integration_Object_Config__mdt>();
        for (Integration_Object_Config__mdt cfg : objConfigs) {
            String key = cfg.SObjectName__c + '|' + cfg.SystemApiName__c + '|' + cfg.TriggerReason__c;
            objCfgByKey.put(key, cfg);
        }

        // Load field mappings (1 SOQL)
        List<Integration_Field_Map__mdt> fieldMaps = [
            SELECT SObjectName__c, SystemApiName__c, SourceFieldAPI__c,
                   TargetFieldName__c, IsRequired__c, DataType__c
            FROM Integration_Field_Map__mdt
            WHERE SObjectName__c IN :sObjNames
              AND SystemApiName__c IN :systemNames
        ];

        Map<String, List<Integration_Field_Map__mdt>> fieldMapsByKey =
            new Map<String, List<Integration_Field_Map__mdt>>();

        for (Integration_Field_Map__mdt fm : fieldMaps) {
            String key = fm.SObjectName__c + '|' + fm.SystemApiName__c;
            fieldMapsByKey.putIfAbsent(key, new List<Integration_Field_Map__mdt>());
            fieldMapsByKey.get(key).add(fm);
        }

        // Load source records (with CRUD + FLS)
        Map<String, Map<Id, SObject>> recordsByType = loadAndSecureRecords(jobs);

        List<Integration_Job__c> jobsToUpdate = new List<Integration_Job__c>();
        List<Integration_Job__c> jobsToRetry  = new List<Integration_Job__c>();

        for (Integration_Job__c job : jobs) {
            Integration_System__mdt sys = systemsByName.get(job.SystemApiName__c);
            if (sys == null || !sys.IsActive__c) {
                job.Status__c   = 'Permanent_Failed';
                job.LastError__c = 'System not configured or inactive';
                jobsToUpdate.add(job);
                continue;
            }

            String objKey = job.SObjectName__c + '|' + job.SystemApiName__c + '|' + job.TriggerReason__c;
            Integration_Object_Config__mdt objCfg = objCfgByKey.get(objKey);
            if (objCfg == null) {
                job.Status__c   = 'Permanent_Failed';
                job.LastError__c = 'Object config not found';
                jobsToUpdate.add(job);
                continue;
            }

            Map<Id, SObject> recsMap = recordsByType.get(job.SObjectName__c);
            if (recsMap == null) {
                job.Status__c   = 'Permanent_Failed';
                job.LastError__c = 'No records loaded for ' + job.SObjectName__c;
                jobsToUpdate.add(job);
                continue;
            }

            SObject record = recsMap.get((Id) job.RecordId__c);
            if (record == null) {
                job.Status__c   = 'Permanent_Failed';
                job.LastError__c = 'Record not found';
                jobsToUpdate.add(job);
                continue;
            }

            String fmKey = job.SObjectName__c + '|' + job.SystemApiName__c;
            List<Integration_Field_Map__mdt> mappings = fieldMapsByKey.get(fmKey);
            if (mappings == null || mappings.isEmpty()) {
                job.Status__c   = 'Permanent_Failed';
                job.LastError__c = 'No field mappings found';
                jobsToUpdate.add(job);
                continue;
            }

            // Build payload (FLS-safe; required fields enforced)
            Map<String, Object> payload = buildPayloadFromFieldMaps(record, mappings, job);
            if ('Permanent_Failed'.equals(job.Status__c)) {
                jobsToUpdate.add(job);
                continue;
            }

            // Resolve adapter via HandlerClass__c
            IIntegrationAdapter adapter =
                (IIntegrationAdapter) Type.forName(sys.HandlerClass__c).newInstance();

            IntegrationContext ctx = new IntegrationContext();
            ctx.record       = record;
            ctx.systemConfig = sys;
            ctx.objectConfig = objCfg;
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
            Integer maxRetries    = sys.MaxRetries__c == null ? 0 : sys.MaxRetries__c;
            Integer currentRetries = job.RetryCount__c == null ? 0 : job.RetryCount__c;

            if (result.isSuccess) {
                job.Status__c   = 'Success';
                job.LastError__c = null;
                jobsToUpdate.add(job);
            } else if (result.isTemporaryError && currentRetries < maxRetries) {
                job.RetryCount__c = currentRetries + 1;
                job.Status__c     = 'Temp_Failed';
                job.LastError__c  = result.message;
                jobsToUpdate.add(job);
                jobsToRetry.add(job);
            } else {
                job.Status__c   = 'Permanent_Failed';
                job.LastError__c = result.message;
                jobsToUpdate.add(job);
            }
        }

        if (!jobsToUpdate.isEmpty()) {
            update jobsToUpdate;
        }

        if (!jobsToRetry.isEmpty()) {
            List<Id> retryIds = new List<Id>();
            for (Integration_Job__c j : jobsToRetry) retryIds.add(j.Id);
            System.enqueueJob(new IntegrationJobWorker(retryIds));
        }
    }

    // Bulk + FLS-safe load of source records
    private static Map<String, Map<Id, SObject>> loadAndSecureRecords(List<Integration_Job__c> jobs) {
        Map<String, Set<Id>> idsByType = new Map<String, Set<Id>>();

        for (Integration_Job__c job : jobs) {
            idsByType.putIfAbsent(job.SObjectName__c, new Set<Id>());
            idsByType.get(job.SObjectName__c).add((Id) job.RecordId__c);
        }

        Map<String, Map<Id, SObject>> result = new Map<String, Map<Id, SObject>>();

        for (String sObjName : idsByType.keySet()) {
            Schema.SObjectType sType = Schema.getGlobalDescribe().get(sObjName);
            if (sType == null) continue;

            Schema.DescribeSObjectResult d = sType.getDescribe();

            // CRUD: object-level access
            if (!d.isAccessible()) {
                // Jobs for this type will be marked as failed later.
                continue;
            }

            String soql = 'SELECT FIELDS(ALL) FROM ' + sObjName + ' WHERE Id IN :idsByType.get(sObjName)';
            List<SObject> recs = Database.query(soql);

            // FLS: strip non-readable fields
            recs = (List<SObject>) Security.stripInaccessible(AccessType.READABLE, recs).getRecords();

            result.put(sObjName, new Map<Id, SObject>(recs));
        }

        return result;
    }

    // Build payload from Integration_Field_Map__mdt rows
    private static Map<String, Object> buildPayloadFromFieldMaps(
        SObject record,
        List<Integration_Field_Map__mdt> mappings,
        Integration_Job__c job
    ) {
        Map<String, Object> payload = new Map<String, Object>();

        for (Integration_Field_Map__mdt fm : mappings) {
            String sourceApi  = fm.SourceFieldAPI__c;
            String targetName = String.isBlank(fm.TargetFieldName__c)
                ? sourceApi
                : fm.TargetFieldName__c;

            Object value;
            try {
                value = record.get(sourceApi); // FLS-safe: unreadable fields are null after stripInaccessible
            } catch (Exception ex) {
                job.Status__c   = 'Permanent_Failed';
                job.LastError__c =
                    'Error reading field ' + sourceApi + ': ' + ex.getMessage();
                break;
            }

            if (fm.IsRequired__c && value == null) {
                job.Status__c   = 'Permanent_Failed';
                job.LastError__c =
                    'Required field ' + sourceApi + ' is null or not accessible';
                break;
            }

            payload.put(targetName, value);
        }

        return payload;
    }
}
