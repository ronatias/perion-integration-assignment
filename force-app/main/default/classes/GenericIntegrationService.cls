// GenericIntegrationService.cls
// Purpose:
//  - Flow-invocable entry point.
//  - Translates business events (Flow) into Integration_Job__c records.
//  - Bulk-safe, CRUD-safe, and configuration-driven.
//
// v2 – CONFIG SOURCE CHANGE
//  - Original version used Integration_Object_Config__mdt (CMDT) for
//    object→system routing.
//  - This version now uses the custom object Integration_Object_Rule__c,
//    which is maintained by the Admin UI (integrationAdminApp).
//  - Structure assumed for Integration_Object_Rule__c:
//      * SObjectName__c         (Text)    – API name of the object, e.g. 'Opportunity'
//      * SystemDeveloperName__c (Text)    – matches Integration_System_Config__c.DeveloperName__c
//      * TriggerReason__c       (Text)    – e.g. 'OPP_STAGE_CONTRACTING'
//      * IsActive__c            (Checkbox)
//
//  - Integration_Job__c is used as before:
//      * SObjectName__c
//      * RecordId__c
//      * SystemApiName__c       – stores the SystemDeveloperName__c
//      * TriggerReason__c
//      * Status__c              – 'Pending' initially
//      * RetryCount__c          – 0 initially
//
public with sharing class GenericIntegrationService {

    public class IntegrationRequestInput {
        @InvocableVariable(required=true)
        public String sObjectName;

        @InvocableVariable(required=true)
        public Id recordId;

        @InvocableVariable(required=true)
        public String triggerReason;
    }

    @InvocableMethod(label='Process Generic Integration')
    public static void process(List<IntegrationRequestInput> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }

        // CRUD: ensure caller may create Integration_Job__c
        if (!Integration_Job__c.SObjectType.getDescribe().isCreateable()) {
            throw new SecurityException(
                'User does not have permission to create Integration_Job__c records.'
            );
        }

        // Collect all SObject names + trigger reasons from the Flow payload (bulk-safe)
        Set<String> sObjectNames   = new Set<String>();
        Set<String> triggerReasons = new Set<String>();

        for (IntegrationRequestInput inReq : inputs) {
            if (String.isBlank(inReq.sObjectName) ||
                inReq.recordId == null ||
                String.isBlank(inReq.triggerReason)) {
                // Skip malformed entries instead of failing the whole batch
                continue;
            }
            sObjectNames.add(inReq.sObjectName);
            triggerReasons.add(inReq.triggerReason);
        }

        if (sObjectNames.isEmpty() || triggerReasons.isEmpty()) {
            return;
        }

        // CONFIG LOOKUP (v2):
        //  - Use Integration_Object_Rule__c instead of CMDT.
        //  - Filter by SObject + TriggerReason + IsActive__c.
        List<Integration_Object_Rule__c> rules = [
            SELECT SObjectName__c,
                   SystemDeveloperName__c,
                   TriggerReason__c,
                   IsActive__c
            FROM Integration_Object_Rule__c
            WHERE SObjectName__c IN :sObjectNames
              AND TriggerReason__c IN :triggerReasons
              AND IsActive__c = true
        ];

        // Group rules by (SObjectName|TriggerReason) for quick lookup
        Map<String, List<Integration_Object_Rule__c>> rulesByKey =
            new Map<String, List<Integration_Object_Rule__c>>();

        for (Integration_Object_Rule__c rule : rules) {
            String key = rule.SObjectName__c + '|' + rule.TriggerReason__c;
            List<Integration_Object_Rule__c> bucket = rulesByKey.get(key);
            if (bucket == null) {
                bucket = new List<Integration_Object_Rule__c>();
                rulesByKey.put(key, bucket);
            }
            bucket.add(rule);
        }

        // Build Integration_Job__c records based on the rules
        List<Integration_Job__c> jobsToInsert = new List<Integration_Job__c>();

        for (IntegrationRequestInput inReq : inputs) {
            String key = inReq.sObjectName + '|' + inReq.triggerReason;
            List<Integration_Object_Rule__c> matchingRules = rulesByKey.get(key);
            if (matchingRules == null || matchingRules.isEmpty()) {
                // No routing rules for this event → nothing to integrate
                continue;
            }

            for (Integration_Object_Rule__c rule : matchingRules) {
                Integration_Job__c job = new Integration_Job__c();
                job.SObjectName__c   = inReq.sObjectName;
                job.RecordId__c      = (String) inReq.recordId;
                // SystemApiName__c holds the SystemDeveloperName__c key
                job.SystemApiName__c = rule.SystemDeveloperName__c;
                job.TriggerReason__c = inReq.triggerReason;
                job.Status__c        = 'Pending';
                job.RetryCount__c    = 0;
                jobsToInsert.add(job);
            }
        }

        if (!jobsToInsert.isEmpty()) {
            insert jobsToInsert;

            // Enqueue async worker to process the jobs
            List<Id> jobIds = new List<Id>();
            for (Integration_Job__c j : jobsToInsert) {
                jobIds.add(j.Id);
            }

            System.enqueueJob(new IntegrationJobWorker(jobIds));
        }
    }
}
