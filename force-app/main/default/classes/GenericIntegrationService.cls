// GenericIntegrationService.cls
// Purpose:
//  - Flow-invocable entry point.
//  - Translates business events (Flow) into Integration_Job__c records.
//  - Bulk-safe, CRUD-safe, and configuration-driven.
//  - Runtime configuration is controlled via:
//      * Integration_Object_Rule__c       (Object + System + TriggerReason + IsActive)
//      * Integration_System_Config__c     (System-level IsActive + Handler + MaxRetries)
//  - Behavior:
//      * If a System is Inactive (Integration_System_Config__c.IsActive__c = false)
//        → NO jobs will be created for that system, even if Object Rule is active.

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
        System.debug('=== GIS.process CALLED, inputs size = ' + (inputs == null ? 0 : inputs.size()));
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
            System.debug('GIS.process – INPUT: sObject=' + inReq.sObjectName +
                         ', recordId=' + inReq.recordId +
                         ', trigger=' + inReq.triggerReason);

            if (String.isBlank(inReq.sObjectName) ||
                inReq.recordId == null ||
                String.isBlank(inReq.triggerReason)) {
                continue;
            }
            sObjectNames.add(inReq.sObjectName);
            triggerReasons.add(inReq.triggerReason);
        }

        System.debug('GIS.process – sObjectNames=' + sObjectNames);
        System.debug('GIS.process – triggerReasons=' + triggerReasons);

        if (sObjectNames.isEmpty() || triggerReasons.isEmpty()) return;

        // --------------------------------------------------------------------
        // 1) Load object rules (custom object, NOT CMDT)
        //    Rule fields:
        //      - SObjectName__c
        //      - SystemDeveloperName__c (matches Integration_System_Config__c.DeveloperName__c)
        //      - TriggerReason__c
        //      - IsActive__c
        // --------------------------------------------------------------------
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

        System.debug('GIS.process – LOADED Object Rules (active only), size=' + rules.size());
        for (Integration_Object_Rule__c r : rules) {
            System.debug('  Rule: SObject=' + r.SObjectName__c +
                         ', System=' + r.SystemDeveloperName__c +
                         ', Trigger=' + r.TriggerReason__c +
                         ', IsActive=' + r.IsActive__c);
        }

        if (rules.isEmpty()) {
            // No active object rules → nothing to create
            System.debug('GIS.process – No active rules, exiting.');
            return;
        }

        // --------------------------------------------------------------------
        // 2) Load active systems referenced by these rules
        //    (respect System-level IsActive__c from Systems tab)
        // --------------------------------------------------------------------
        Set<String> systemDevNames = new Set<String>();
        for (Integration_Object_Rule__c r : rules) {
            systemDevNames.add(r.SystemDeveloperName__c);
        }
        System.debug('GIS.process – systemDevNames from rules=' + systemDevNames);

        Map<String, Integration_System_Config__c> activeSystemsByDevName =
            new Map<String, Integration_System_Config__c>();

        for (Integration_System_Config__c sys : [
            SELECT DeveloperName__c, IsActive__c, HandlerClass__c, MaxRetries__c
            FROM Integration_System_Config__c
            WHERE DeveloperName__c IN :systemDevNames
              AND IsActive__c      = true
        ]) {
            activeSystemsByDevName.put(sys.DeveloperName__c, sys);
            System.debug('  Active System: devName=' + sys.DeveloperName__c +
                         ', IsActive=' + sys.IsActive__c +
                         ', HandlerClass=' + sys.HandlerClass__c +
                         ', MaxRetries=' + sys.MaxRetries__c);
        }

        System.debug('GIS.process – activeSystemsByDevName keys=' + activeSystemsByDevName.keySet());

        if (activeSystemsByDevName.isEmpty()) {
            // All systems referenced by rules are inactive → nothing to create
            System.debug('GIS.process – No active systems for rules, exiting.');
            return;
        }

        // --------------------------------------------------------------------
        // 3) Key rules by (SObjectName|TriggerReason), BUT ONLY for active systems
        // --------------------------------------------------------------------
        Map<String, List<Integration_Object_Rule__c>> rulesByKey =
            new Map<String, List<Integration_Object_Rule__c>>();

        for (Integration_Object_Rule__c rule : rules) {
            // Skip any rule whose system is not active at system level
            if (!activeSystemsByDevName.containsKey(rule.SystemDeveloperName__c)) {
                System.debug('  SKIP Rule (system inactive or missing): System=' +
                             rule.SystemDeveloperName__c);
                continue;
            }

            String key = rule.SObjectName__c + '|' + rule.TriggerReason__c;
            if (!rulesByKey.containsKey(key)) {
                rulesByKey.put(key, new List<Integration_Object_Rule__c>());
            }
            rulesByKey.get(key).add(rule);
        }

        System.debug('GIS.process – rulesByKey keys=' + rulesByKey.keySet());

        if (rulesByKey.isEmpty()) {
            // No rules remain after filtering out inactive systems
            System.debug('GIS.process – No rules after system filter, exiting.');
            return;
        }

        // --------------------------------------------------------------------
        // 4) Create Integration_Job__c records
        // --------------------------------------------------------------------
        for (IntegrationRequestInput inReq : inputs) {
            if (String.isBlank(inReq.sObjectName) ||
                inReq.recordId == null ||
                String.isBlank(inReq.triggerReason)) {
                continue;
            }

            String key = inReq.sObjectName + '|' + inReq.triggerReason;
            List<Integration_Object_Rule__c> ruleList = rulesByKey.get(key);
            System.debug('GIS.process – For input key=' + key +
                         ' → ruleList size=' + (ruleList == null ? 0 : ruleList.size()));

            if (ruleList == null || ruleList.isEmpty()) continue;

            for (Integration_Object_Rule__c rule : ruleList) {
                // Defensive: system must still be active (should already be true from filter above)
                if (!activeSystemsByDevName.containsKey(rule.SystemDeveloperName__c)) {
                    System.debug('  SKIP Rule at job creation (system inactive): System=' +
                                 rule.SystemDeveloperName__c);
                    continue;
                }

                Integration_Job__c job = new Integration_Job__c();
                job.SObjectName__c   = inReq.sObjectName;
                job.RecordId__c      = (String) inReq.recordId;
                job.SystemApiName__c = rule.SystemDeveloperName__c;
                job.TriggerReason__c = inReq.triggerReason;
                job.Status__c        = 'Pending';
                job.RetryCount__c    = 0;
                jobsToInsert.add(job);

                System.debug('  CREATE JOB: SObject=' + job.SObjectName__c +
                             ', Record=' + job.RecordId__c +
                             ', System=' + job.SystemApiName__c +
                             ', Trigger=' + job.TriggerReason__c);
            }
        }

        System.debug('GIS.process – jobsToInsert size=' + jobsToInsert.size());

        if (!jobsToInsert.isEmpty()) {
            insert jobsToInsert;

            List<Id> jobIds = new List<Id>();
            for (Integration_Job__c j : jobsToInsert) jobIds.add(j.Id);

            System.enqueueJob(new IntegrationJobWorker(jobIds));
        }
    }
}
