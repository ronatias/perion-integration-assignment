@IsTest
private class IntegrationJobWorkerTest {

    // -----------------------
    // Test data helpers
    // -----------------------

    private static Account createTestAccount(Boolean setPhone) {
        Account a = new Account(
            Name = 'Test Account' + (setPhone ? ' With Phone' : ' No Phone')
        );
        if (setPhone) {
            a.Phone = '123456';
        }
        insert a;
        return a;
    }

    private static Integration_System_Config__c createSystemConfig(
        String devName,
        Boolean isActive
    ) {
        Integration_System_Config__c sys = new Integration_System_Config__c(
            DeveloperName__c = devName,
            IsActive__c      = isActive,
            HandlerClass__c  = 'DummyHandler', // never actually used in tests
            MaxRetries__c    = 3
        );
        insert sys;
        return sys;
    }

    private static Integration_Object_Rule__c createObjectRule(
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

    private static Integration_Field_Map_Config__c createFieldMap(
        String sObjectName,
        String systemDevName,
        String sourceFieldApi,
        String targetFieldName,
        Boolean isRequired
    ) {
        Integration_Field_Map_Config__c fm = new Integration_Field_Map_Config__c(
            SObjectName__c         = sObjectName,
            SystemDeveloperName__c = systemDevName,
            SourceFieldAPI__c      = sourceFieldApi,
            TargetFieldName__c     = targetFieldName,
            IsRequired__c          = isRequired,
            DataType__c            = 'String'
        );
        insert fm;
        return fm;
    }

    private static Integration_Job__c createJob(
        String sObjectName,
        Id recordId,
        String systemApiName,
        String triggerReason
    ) {
        Integration_Job__c job = new Integration_Job__c(
            SObjectName__c   = sObjectName,
            RecordId__c      = (recordId == null ? null : (String)recordId),
            SystemApiName__c = systemApiName,
            TriggerReason__c = triggerReason,
            Status__c        = 'Pending',
            RetryCount__c    = 0
        );
        insert job;
        return job;
    }

    // -----------------------
    // 1) jobIds null / empty => early return
    // -----------------------
    @IsTest
    static void testExecute_nullOrEmptyJobIds() {
        Test.startTest();
        // Null list
        new IntegrationJobWorker(null).execute(null);
        // Empty list
        new IntegrationJobWorker(new List<Id>()).execute(null);
        Test.stopTest();

        // No exception and no updates is the success criteria here
        System.assertEquals(0, [SELECT COUNT() FROM Integration_Job__c]);
    }

    // -----------------------
    // 2) System missing or inactive => Permanent_Failed (system not configured / inactive)
    // -----------------------
    @IsTest
    static void testExecute_systemInactive() {
        Account acc = createTestAccount(true);

        // System exists but inactive
        String systemName = 'SYS_INACTIVE';
        createSystemConfig(systemName, false);

        // No need for rules / field maps – will fail at system check
        Integration_Job__c job = createJob(
            'Account',
            acc.Id,
            systemName,
            'AFTER_INSERT'
        );

        Test.startTest();
        new IntegrationJobWorker(new List<Id>{ job.Id }).execute(null);
        Test.stopTest();

        Integration_Job__c updated = [
            SELECT Status__c, LastError__c
            FROM Integration_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Permanent_Failed', updated.Status__c);
        System.assertEquals('System not configured or inactive', updated.LastError__c);
    }

    // -----------------------
    // 3) Object config not found => Permanent_Failed
    // -----------------------
    @IsTest
    static void testExecute_objectConfigNotFound() {
        Account acc = createTestAccount(true);

        String systemName = 'SYS_NO_RULE';
        createSystemConfig(systemName, true);

        // Intentionally NO object rule for (Account, SYS_NO_RULE, AFTER_INSERT)
        Integration_Job__c job = createJob(
            'Account',
            acc.Id,
            systemName,
            'AFTER_INSERT'
        );

        Test.startTest();
        new IntegrationJobWorker(new List<Id>{ job.Id }).execute(null);
        Test.stopTest();

        Integration_Job__c updated = [
            SELECT Status__c, LastError__c
            FROM Integration_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Permanent_Failed', updated.Status__c);
        System.assertEquals('Object config not found', updated.LastError__c);
    }

    // -----------------------
    // 4) No records loaded for SObjectName__c => Permanent_Failed
    //    Use a fake SObjectName that does not exist in the org schema.
    // -----------------------
    @IsTest
    static void testExecute_noRecordsLoadedForType() {
        // We won't actually use a real record – fake SObject name will skip loading
        String fakeSObject = 'Ghost__c';
        String systemName  = 'SYS_GHOST';

        createSystemConfig(systemName, true);
        createObjectRule(fakeSObject, systemName, 'AFTER_INSERT', true);

        // Job points to fake SObject name
        Integration_Job__c job = createJob(
            fakeSObject,
            null, // RecordId__c will be null string, but loadAndSecureRecords already won't load anything
            systemName,
            'AFTER_INSERT'
        );

        Test.startTest();
        new IntegrationJobWorker(new List<Id>{ job.Id }).execute(null);
        Test.stopTest();

        Integration_Job__c updated = [
            SELECT Status__c, LastError__c
            FROM Integration_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Permanent_Failed', updated.Status__c);
        System.assertEquals(
            'No records loaded for ' + fakeSObject,
            updated.LastError__c
        );
    }

    // -----------------------
    // 5) Record not found => Permanent_Failed
    //    Use SObjectName 'Contact' but RecordId__c is an Account Id (so query returns no record).
    // -----------------------
    @IsTest
    static void testExecute_recordNotFound() {
        Account acc = createTestAccount(true);

        String systemName = 'SYS_RECORD_NOT_FOUND';
        createSystemConfig(systemName, true);
        createObjectRule('Contact', systemName, 'AFTER_INSERT', true);

        // Job pretends the record is a Contact, but the Id is actually an Account Id
        Integration_Job__c job = createJob(
            'Contact',
            acc.Id,
            systemName,
            'AFTER_INSERT'
        );

        Test.startTest();
        new IntegrationJobWorker(new List<Id>{ job.Id }).execute(null);
        Test.stopTest();

        Integration_Job__c updated = [
            SELECT Status__c, LastError__c
            FROM Integration_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Permanent_Failed', updated.Status__c);
        System.assertEquals('Record not found', updated.LastError__c);
    }

    // -----------------------
    // 6) No field mappings => Permanent_Failed
    // -----------------------
    @IsTest
    static void testExecute_noFieldMappings() {
        Account acc = createTestAccount(true);

        String systemName = 'SYS_NO_FM';
        createSystemConfig(systemName, true);
        createObjectRule('Account', systemName, 'AFTER_INSERT', true);

        // Intentionally NO Integration_Field_Map_Config__c records for (Account, SYS_NO_FM)
        Integration_Job__c job = createJob(
            'Account',
            acc.Id,
            systemName,
            'AFTER_INSERT'
        );

        Test.startTest();
        new IntegrationJobWorker(new List<Id>{ job.Id }).execute(null);
        Test.stopTest();

        Integration_Job__c updated = [
            SELECT Status__c, LastError__c
            FROM Integration_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Permanent_Failed', updated.Status__c);
        System.assertEquals('No field mappings found', updated.LastError__c);
    }

    // -----------------------
    // 7) Required field is null => Permanent_Failed
    //    (exercises buildPayloadFromFieldMaps with IsRequired__c = true)
    // -----------------------
    @IsTest
    static void testExecute_requiredFieldMissing() {
        // Create account WITHOUT Phone → required mapping will fail
        Account acc = createTestAccount(false);

        String systemName = 'SYS_REQUIRED_MISSING';
        createSystemConfig(systemName, true);
        createObjectRule('Account', systemName, 'AFTER_INSERT', true);

        // Required field mapping for Phone (which is null)
        createFieldMap('Account', systemName, 'Phone', 'phone', true);

        Integration_Job__c job = createJob(
            'Account',
            acc.Id,
            systemName,
            'AFTER_INSERT'
        );

        Test.startTest();
        new IntegrationJobWorker(new List<Id>{ job.Id }).execute(null);
        Test.stopTest();

        Integration_Job__c updated = [
            SELECT Status__c, LastError__c
            FROM Integration_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Permanent_Failed', updated.Status__c);
        System.assert(updated.LastError__c.contains('Required field Phone'),
            'Expected error to mention required field Phone'
        );
    }

    // -----------------------
    // 8) Invalid SourceFieldAPI__c => Permanent_Failed
    //    (exercises buildPayloadFromFieldMaps catch block)
    // -----------------------
    @IsTest
    static void testExecute_invalidSourceFieldName() {
        Account acc = createTestAccount(true);

        String systemName = 'SYS_INVALID_FIELD';
        createSystemConfig(systemName, true);
        createObjectRule('Account', systemName, 'AFTER_INSERT', true);

        // Mapping points to a non-existing field → record.get() throws
        createFieldMap('Account', systemName, 'DoesNotExist__c', 'badField', false);

        Integration_Job__c job = createJob(
            'Account',
            acc.Id,
            systemName,
            'AFTER_INSERT'
        );

        Test.startTest();
        new IntegrationJobWorker(new List<Id>{ job.Id }).execute(null);
        Test.stopTest();

        Integration_Job__c updated = [
            SELECT Status__c, LastError__c
            FROM Integration_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Permanent_Failed', updated.Status__c);
        System.assert(updated.LastError__c.contains('Error reading field DoesNotExist__c'),
            'Expected error to mention invalid field DoesNotExist__c'
        );
    }
}
