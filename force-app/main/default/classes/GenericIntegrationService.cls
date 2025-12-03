// GenericIntegrationService.cls
// Purpose:
//  - Flow-invocable entry point.
//  - Translates business events (Flow) into Integration_Job__c records.
//  - Bulk-safe, CRUD-safe, and configuration-driven.
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
        if (inputs == null || inputs.isEmpty()) return;

        // CRUD: ensure caller may create Integration_Job__c
        if (!Integration_Job__c.SObjectType.getDescribe().isCreateable()) {
            throw new SecurityException(
                'User does not have permission to create Integration_Job__c records.'
            );
        }

        List<Integration_Job__c> jobsToInsert = new List<Integration_Job__c>();

        Set<String> sObjectNames   = new Set<String>();
        Set<String> triggerReasons = new Set<String>();

        for (IntegrationRequestInput inReq : inputs) {
            if (String.isBlank(inReq.sObjectName) ||
                inReq.recordId == null ||
                String.isBlank(inReq.triggerReason)) {
                continue;
            }
            sObjectNames.add(inReq.sObjectName);
            triggerReasons.add(inReq.triggerReason);
        }

        if (sObjectNames.isEmpty() || triggerReasons.isEmpty()) return;

        // Load object configs for these object+triggerReason (bulk)
        List<Integration_Object_Config__mdt> configs = [
            SELECT SObjectName__c, SystemApiName__c, TriggerReason__c, IsActive__c
            FROM Integration_Object_Config__mdt
            WHERE SObjectName__c IN :sObjectNames
              AND TriggerReason__c IN :triggerReasons
              AND IsActive__c = true
        ];

        Map<String, List<Integration_Object_Config__mdt>> configsByKey =
            new Map<String, List<Integration_Object_Config__mdt>>();

        for (Integration_Object_Config__mdt cfg : configs) {
            String key = cfg.SObjectName__c + '|' + cfg.TriggerReason__c;
            if (!configsByKey.containsKey(key)) {
                configsByKey.put(key, new List<Integration_Object_Config__mdt>());
            }
            configsByKey.get(key).add(cfg);            
        }

        for (IntegrationRequestInput inReq : inputs) {
            String key = inReq.sObjectName + '|' + inReq.triggerReason;
            List<Integration_Object_Config__mdt> cfgs = configsByKey.get(key);
            if (cfgs == null || cfgs.isEmpty()) continue;

            for (Integration_Object_Config__mdt cfg : cfgs) {
                Integration_Job__c job = new Integration_Job__c();
                job.SObjectName__c   = inReq.sObjectName;
                job.RecordId__c      = (String) inReq.recordId;
                job.SystemApiName__c = cfg.SystemApiName__c;
                job.TriggerReason__c = inReq.triggerReason;
                job.Status__c        = 'Pending';
                job.RetryCount__c    = 0;
                jobsToInsert.add(job);
            }
        }

        if (!jobsToInsert.isEmpty()) {
            insert jobsToInsert;

            List<Id> jobIds = new List<Id>();
            for (Integration_Job__c j : jobsToInsert) jobIds.add(j.Id);

            System.enqueueJob(new IntegrationJobWorker(jobIds));
        }
    }
}
