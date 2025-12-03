@IsTest
private class GenericIntegrationServiceTest {

    // Utility: create a basic Account to use as "business" record
    private static Account createTestAccount() {
        Account a = new Account(Name = 'Test Account');
        insert a;
        return a;
    }

    // Utility: create an active System Config
    private static Integration_System_Config__c createActiveSystem(String devName) {
        Integration_System_Config__c sys = new Integration_System_Config__c(
            DeveloperName__c  = devName,
            IsActive__c       = true,
            HandlerClass__c   = 'IntegrationJobWorker',
            MaxRetries__c     = 3
        );
        insert sys;
        return sys;
    }

    // Utility: create an inactive System Config (for completeness)
    private static Integration_System_Config__c createInactiveSystem(String devName) {
        Integration_System_Config__c sys = new Integration_System_Config__c(
            DeveloperName__c  = devName,
            IsActive__c       = false,
            HandlerClass__c   = 'IntegrationJobWorker',
            MaxRetries__c     = 3
        );
        insert sys;
        return sys;
    }

    // Utility: create an Object Rule
    private static Integration_Object_Rule__c createRule(
        String sObjectName,
        String systemDevName,
        String triggerReason,
        Boolean isActive
    ) {
        Integration_Object_Rule__c rule = new Integration_Object_Rule__c(
            SObjectName__c         = sObjectName,
            SystemDeveloperName__c = systemDevName,
            TriggerReason__c       = triggerReason,
            IsActive__c            = isActive
        );
        insert rule;
        return rule;
    }

    // -----------------------------
    // 1) Happy path – one rule, one system, one input => one job
    // -----------------------------
    @IsTest
    static void testProcess_singleJobCreated() {
        Account acc = createTestAccount();

        String systemDevName = 'PERION_API';
        createActiveSystem(systemDevName);
        createRule('Account', systemDevName, 'AFTER_INSERT', true);

        GenericIntegrationService.IntegrationRequestInput input =
            new GenericIntegrationService.IntegrationRequestInput();
        input.sObjectName   = 'Account';
        input.recordId      = acc.Id;
        input.triggerReason = 'AFTER_INSERT';

        Test.startTest();
        GenericIntegrationService.process(
            new List<GenericIntegrationService.IntegrationRequestInput>{ input }
        );
        Test.stopTest(); // will also run IntegrationJobWorker

        List<Integration_Job__c> jobs = [
            SELECT Id, SObjectName__c, RecordId__c, SystemApiName__c, TriggerReason__c, Status__c, RetryCount__c
            FROM Integration_Job__c
        ];

        System.assertEquals(1, jobs.size(), 'Exactly one Integration_Job__c should be created');
        Integration_Job__c job = jobs[0];
        System.assertEquals('Account', job.SObjectName__c);
        System.assertEquals((String)acc.Id, job.RecordId__c);
        System.assertEquals(systemDevName, job.SystemApiName__c);
        System.assertEquals('AFTER_INSERT', job.TriggerReason__c);
        // Do NOT assert on Status__c / RetryCount__c – worker may change them
    }

    // -----------------------------
    // 2) Multiple active rules (same sObject + trigger, different systems) => multiple jobs
    // -----------------------------
    @IsTest
    static void testProcess_multipleSystemsCreatesMultipleJobs() {
        Account acc = createTestAccount();

        String systemA = 'SYS_A';
        String systemB = 'SYS_B';

        createActiveSystem(systemA);
        createActiveSystem(systemB);

        createRule('Account', systemA, 'AFTER_UPDATE', true);
        createRule('Account', systemB, 'AFTER_UPDATE', true);

        GenericIntegrationService.IntegrationRequestInput input =
            new GenericIntegrationService.IntegrationRequestInput();
        input.sObjectName   = 'Account';
        input.recordId      = acc.Id;
        input.triggerReason = 'AFTER_UPDATE';

        Test.startTest();
        GenericIntegrationService.process(
            new List<GenericIntegrationService.IntegrationRequestInput>{ input }
        );
        Test.stopTest();

        List<Integration_Job__c> jobs = [
            SELECT SystemApiName__c
            FROM Integration_Job__c
        ];

        System.assertEquals(2, jobs.size(), 'Two jobs expected – one per active system');
        Set<String> systemsFromJobs = new Set<String>();
        for (Integration_Job__c j : jobs) {
            systemsFromJobs.add(j.SystemApiName__c);
        }
        System.assertEquals(new Set<String>{ systemA, systemB }, systemsFromJobs);
    }

    // -----------------------------
    // 3) No matching rules => no jobs
    // -----------------------------
    @IsTest
    static void testProcess_noRulesNoJobs() {
        Account acc = createTestAccount();

        // System + rule use a different triggerReason than the input
        String systemDevName = 'PERION_API';
        createActiveSystem(systemDevName);
        createRule('Account', systemDevName, 'AFTER_INSERT', true);

        GenericIntegrationService.IntegrationRequestInput input =
            new GenericIntegrationService.IntegrationRequestInput();
        input.sObjectName   = 'Account';
        input.recordId      = acc.Id;
        input.triggerReason = 'AFTER_UPDATE'; // does NOT match rule

        Test.startTest();
        GenericIntegrationService.process(
            new List<GenericIntegrationService.IntegrationRequestInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Integration_Job__c],
            'No jobs should be created when no rules match'
        );
    }

    // -----------------------------
    // 4) Rules exist, but systems are inactive => early return, no jobs
    // -----------------------------
    @IsTest
    static void testProcess_rulesButNoActiveSystems() {
        Account acc = createTestAccount();

        // Create rule that references a system dev name
        // but the actual system config is INACTIVE
        String systemDevName = 'INACTIVE_SYS';
        createInactiveSystem(systemDevName);
        createRule('Account', systemDevName, 'AFTER_INSERT', true);

        GenericIntegrationService.IntegrationRequestInput input =
            new GenericIntegrationService.IntegrationRequestInput();
        input.sObjectName   = 'Account';
        input.recordId      = acc.Id;
        input.triggerReason = 'AFTER_INSERT';

        Test.startTest();
        GenericIntegrationService.process(
            new List<GenericIntegrationService.IntegrationRequestInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Integration_Job__c],
            'No jobs should be created when all systems are inactive'
        );
    }

    // -----------------------------
    // 5) Mixed valid/invalid inputs – invalid ones are skipped
    // -----------------------------
    @IsTest
    static void testProcess_skipsInvalidInputs() {
        Account acc = createTestAccount();

        String systemDevName = 'PERION_API';
        createActiveSystem(systemDevName);
        createRule('Account', systemDevName, 'AFTER_INSERT', true);

        // Valid input
        GenericIntegrationService.IntegrationRequestInput valid =
            new GenericIntegrationService.IntegrationRequestInput();
        valid.sObjectName   = 'Account';
        valid.recordId      = acc.Id;
        valid.triggerReason = 'AFTER_INSERT';

        // Missing sObjectName
        GenericIntegrationService.IntegrationRequestInput missingSObject =
            new GenericIntegrationService.IntegrationRequestInput();
        missingSObject.sObjectName   = null;
        missingSObject.recordId      = acc.Id;
        missingSObject.triggerReason = 'AFTER_INSERT';

        // Missing recordId
        GenericIntegrationService.IntegrationRequestInput missingRecordId =
            new GenericIntegrationService.IntegrationRequestInput();
        missingRecordId.sObjectName   = 'Account';
        missingRecordId.recordId      = null;
        missingRecordId.triggerReason = 'AFTER_INSERT';

        // Missing triggerReason
        GenericIntegrationService.IntegrationRequestInput missingTrigger =
            new GenericIntegrationService.IntegrationRequestInput();
        missingTrigger.sObjectName   = 'Account';
        missingTrigger.recordId      = acc.Id;
        missingTrigger.triggerReason = null;

        List<GenericIntegrationService.IntegrationRequestInput> inputs =
            new List<GenericIntegrationService.IntegrationRequestInput>{
                valid,
                missingSObject,
                missingRecordId,
                missingTrigger
            };

        Test.startTest();
        GenericIntegrationService.process(inputs);
        Test.stopTest();

        // Only the valid input should produce a job
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Integration_Job__c],
            'Only one job should be created from the single valid input'
        );
    }

    // -----------------------------
    // 6) Null / empty inputs => early return, no exceptions
    // -----------------------------
    @IsTest
    static void testProcess_nullAndEmptyInputs() {
        Test.startTest();
        // Both calls happen within a single start/stop block
        GenericIntegrationService.process(null);
        GenericIntegrationService.process(
            new List<GenericIntegrationService.IntegrationRequestInput>()
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Integration_Job__c],
            'No jobs should be created for null or empty input list'
        );
    }
}
