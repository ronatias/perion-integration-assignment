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
// TBD - ADD FLS + CRUD checks for Integration_Job__c fields (Need to check and update test class after any change) 

public with sharing class GenericIntegrationService {

    // DTO for Flow → Apex bridge.
    // Each element represents one business event (one record + one trigger reason).
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
        // Guard: nothing to do if Flow passed no valid items
        if (inputs == null || inputs.isEmpty()) return;

        // CRUD: ensure caller may create Integration_Job__c.
        // This enforces security when invoked from Flow, Apex, or other tools.
        if (!Integration_Job__c.SObjectType.getDescribe().isCreateable()) {
            throw new SecurityException(
                'User does not have permission to create Integration_Job__c records.'
            );
        }

        List<Integration_Job__c> jobsToInsert = new List<Integration_Job__c>();

        // Collect distinct sObject names and trigger reasons for efficient rule lookup.
        Set<String> sObjectNames   = new Set<String>();
        Set<String> triggerReasons = new Set<String>();

        for (IntegrationRequestInput inReq : inputs) {
            // Skip malformed entries – we only work with fully specified events.
            if (String.isBlank(inReq.sObjectName) ||
                inReq.recordId == null ||
                String.isBlank(inReq.triggerReason)) {
                continue;
            }
            sObjectNames.add(inReq.sObjectName);
            triggerReasons.add(inReq.triggerReason);
        }

        // If nothing valid remains, exit quietly.
        if (sObjectNames.isEmpty() || triggerReasons.isEmpty()) return;

        // --------------------------------------------------------------------
        // 1) Load object rules (custom object)
        //    Rule fields:
        //      - SObjectName__c
        //      - SystemDeveloperName__c (matches Integration_System_Config__c.DeveloperName__c)
        //      - TriggerReason__c
        //      - IsActive__c
        //
        // These rules define *which* systems should receive events
        // for a given SObject + TriggerReason combination.
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

        if (rules.isEmpty()) {
            // No active object rules → nothing to create.
            // This is a configuration decision, not an error.
            return;
        }

        // --------------------------------------------------------------------
        // 2) Load active systems referenced by these rules
        //    (respect System-level IsActive__c from Systems tab)
        //
        // Even if a rule is active, the system itself might be turned off
        // for maintenance / rollout. We only push to systems that are active.
        // --------------------------------------------------------------------
        Set<String> systemDevNames = new Set<String>();
        for (Integration_Object_Rule__c r : rules) {
            systemDevNames.add(r.SystemDeveloperName__c);
        }

        Map<String, Integration_System_Config__c> activeSystemsByDevName =
            new Map<String, Integration_System_Config__c>();

        for (Integration_System_Config__c sys : [
            SELECT DeveloperName__c, IsActive__c, HandlerClass__c, MaxRetries__c
            FROM Integration_System_Config__c
            WHERE DeveloperName__c IN :systemDevNames
              AND IsActive__c      = true
        ]) {
            activeSystemsByDevName.put(sys.DeveloperName__c, sys);
        }

        if (activeSystemsByDevName.isEmpty()) {
            // All systems referenced by rules are inactive → nothing to create.
            // Object rules exist, but system-level switch disables them.
            return;
        }

        // --------------------------------------------------------------------
        // 3) Key rules by (SObjectName|TriggerReason), BUT ONLY for active systems
        //
        // Result: rulesByKey tells us, for a given (SObject, TriggerReason),
        // which *active* systems should receive jobs.
        // --------------------------------------------------------------------
        Map<String, List<Integration_Object_Rule__c>> rulesByKey =
            new Map<String, List<Integration_Object_Rule__c>>();

        for (Integration_Object_Rule__c rule : rules) {
            // Skip any rule whose system is not active at system level.
            // This double-check ensures we never create jobs for inactive systems.
            if (!activeSystemsByDevName.containsKey(rule.SystemDeveloperName__c)) {
                continue;
            }

            String key = rule.SObjectName__c + '|' + rule.TriggerReason__c;
            if (!rulesByKey.containsKey(key)) {
                rulesByKey.put(key, new List<Integration_Object_Rule__c>());
            }
            rulesByKey.get(key).add(rule);
        }

        if (rulesByKey.isEmpty()) {
            // No rules remain after filtering out inactive systems.
            // At this point, configuration says “nothing should be sent anywhere”.
            return;
        }

        // --------------------------------------------------------------------
        // 4) Create Integration_Job__c records
        //
        // For each valid input event, look up its rules and fan out jobs
        // to all active systems configured for that (SObject, TriggerReason).
        // --------------------------------------------------------------------
        for (IntegrationRequestInput inReq : inputs) {
            // Re-validate the input in case some entries were malformed.
            if (String.isBlank(inReq.sObjectName) ||
                inReq.recordId == null ||
                String.isBlank(inReq.triggerReason)) {
                continue;
            }

            String key = inReq.sObjectName + '|' + inReq.triggerReason;
            List<Integration_Object_Rule__c> ruleList = rulesByKey.get(key);

            if (ruleList == null || ruleList.isEmpty()) continue;

            for (Integration_Object_Rule__c rule : ruleList) {
                // Defensive: system must still be active (should already be true from filter above).
                if (!activeSystemsByDevName.containsKey(rule.SystemDeveloperName__c)) {
                    continue;
                }

                // One job per (record, system) matching this trigger.
                Integration_Job__c job = new Integration_Job__c();
                job.SObjectName__c   = inReq.sObjectName;
                job.RecordId__c      = (String) inReq.recordId;
                job.SystemApiName__c = rule.SystemDeveloperName__c;
                job.TriggerReason__c = inReq.triggerReason;
                job.Status__c        = 'Pending';
                job.RetryCount__c    = 0;
                jobsToInsert.add(job);
            }
        }

        // Persist jobs and hand them off to the async worker for processing.
        if (!jobsToInsert.isEmpty()) {
            insert jobsToInsert;

            List<Id> jobIds = new List<Id>();
            for (Integration_Job__c j : jobsToInsert) jobIds.add(j.Id);

            System.enqueueJob(new IntegrationJobWorker(jobIds));
        }
    }
}
