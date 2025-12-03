@IsTest
private class IntegrationAdminControllerTest {

    // -----------------------
    // Helpers
    // -----------------------

    // Create a system config record (Name is auto / read-only)
    private static Integration_System_Config__c createSystemConfig(
        String devName,
        Boolean isActive,
        Integer maxRetries,
        String handlerClass
    ) {
        Integration_System_Config__c sys = new Integration_System_Config__c(
            DeveloperName__c = devName,
            IsActive__c      = isActive,
            MaxRetries__c    = maxRetries,
            HandlerClass__c  = handlerClass
        );
        insert sys;
        return sys;
    }

    private static Integration_Object_Rule__c createObjectRule(
        String sObjectName,
        String systemDevName,
        String triggerReason,
        Boolean isActive,
        String devName
    ) {
        Integration_Object_Rule__c rule = new Integration_Object_Rule__c(
            SObjectName__c         = sObjectName,
            SystemDeveloperName__c = systemDevName,
            TriggerReason__c       = triggerReason,
            IsActive__c            = isActive,
            DeveloperName__c       = devName
        );
        insert rule;
        return rule;
    }

    private static Integration_Field_Map_Config__c createFieldMap(
        String sObjectName,
        String systemDevName,
        String sourceFieldApi,
        String targetFieldName,
        Boolean isRequired,
        String dataType,
        String devName
    ) {
        Integration_Field_Map_Config__c fm = new Integration_Field_Map_Config__c(
            SObjectName__c         = sObjectName,
            SystemDeveloperName__c = systemDevName,
            SourceFieldAPI__c      = sourceFieldApi,
            TargetFieldName__c     = targetFieldName,
            IsRequired__c          = isRequired,
            DataType__c            = dataType,
            DeveloperName__c       = devName
        );
        insert fm;
        return fm;
    }

    // =========================================================
    // SYSTEMS: getSystems + saveSystems
    // =========================================================

    @IsTest
    static void testGetSystemsAndSaveSystems() {
        // Existing system (will be updated)
        createSystemConfig('SYS_EXIST', true, 5, 'HandlerA');

        // Call getSystems to cover DTO mapping
        List<IntegrationAdminDTOs.SystemConfigDTO> systemsDto =
            IntegrationAdminController.getSystems();
        System.assert(systemsDto.size() >= 1, 'Expected at least one system DTO');

        // Prepare payload for saveSystems
        List<Object> payload = new List<Object>();

        // 1) Non-map row → should be skipped
        payload.add('not a map');

        // 2) Existing system: Boolean isActive, numeric maxRetries
        Map<String, Object> rowExisting = new Map<String, Object>();
        rowExisting.put('developerName', 'SYS_EXIST');
        rowExisting.put('isActive', false);
        rowExisting.put('maxRetries', 7);
        payload.add(rowExisting);

        // 3) New system: String isActive, String maxRetries
        Map<String, Object> rowNew = new Map<String, Object>();
        rowNew.put('developerName', 'SYS_NEW');
        rowNew.put('isActive', 'true');
        rowNew.put('maxRetries', '10');
        payload.add(rowNew);

        // 4) New system: String isActive 'false', invalid maxRetries string
        Map<String, Object> rowNoMax = new Map<String, Object>();
        rowNoMax.put('developerName', 'SYS_NO_MAX');
        rowNoMax.put('isActive', 'false');
        rowNoMax.put('maxRetries', 'abc'); // parse fails → ignored
        payload.add(rowNoMax);

        // 5) Row with empty developerName → skipped
        Map<String, Object> rowBlankDev = new Map<String, Object>();
        rowBlankDev.put('developerName', '');
        rowBlankDev.put('isActive', true);
        rowBlankDev.put('maxRetries', 1);
        payload.add(rowBlankDev);

        Test.startTest();
        IntegrationAdminController.saveSystems(payload);
        Test.stopTest();

        // Verify existing system was updated
        Integration_System_Config__c updated = [
            SELECT DeveloperName__c, IsActive__c, MaxRetries__c
            FROM Integration_System_Config__c
            WHERE DeveloperName__c = 'SYS_EXIST'
            LIMIT 1
        ];
        System.assertEquals(false, updated.IsActive__c);
        System.assertEquals(7, updated.MaxRetries__c);

        // Verify new systems inserted
        Integration_System_Config__c newSys = [
            SELECT DeveloperName__c, IsActive__c, MaxRetries__c
            FROM Integration_System_Config__c
            WHERE DeveloperName__c = 'SYS_NEW'
            LIMIT 1
        ];
        System.assertEquals(true, newSys.IsActive__c);
        System.assertEquals(10, newSys.MaxRetries__c);

        Integration_System_Config__c noMax = [
            SELECT DeveloperName__c, IsActive__c, MaxRetries__c
            FROM Integration_System_Config__c
            WHERE DeveloperName__c = 'SYS_NO_MAX'
            LIMIT 1
        ];
        System.assertEquals(false, noMax.IsActive__c);
        System.assertEquals(null, noMax.MaxRetries__c);
    }

    @IsTest
    static void testSaveSystems_nullAndEmpty() {
        Test.startTest();
        // null
        IntegrationAdminController.saveSystems(null);
        // empty
        IntegrationAdminController.saveSystems(new List<Object>());
        Test.stopTest();

        // Just checking no exceptions, nothing to assert
        System.assertEquals(0, [SELECT COUNT() FROM Integration_System_Config__c]);
    }

    // =========================================================
    // OBJECT RULES: getObjectConfigs + saveObjectConfigs
    // =========================================================

    @IsTest
    static void testGetAndSaveObjectConfigs_insertAndUpdate() {
        // Pre-existing rule for Account + SYS1, with blank DeveloperName
        createObjectRule('Account', 'SYS1', 'AFTER_INSERT', true, null);

        // Call getObjectConfigs to cover DTO mapping
        List<IntegrationAdminDTOs.ObjectConfigDTO> existing =
            IntegrationAdminController.getObjectConfigs();
        // May be >1 because of other tests, just ensure method works
        System.assert(existing.size() >= 1);

        // Build payload with:
        // 1) Update existing rule (Account, SYS1)
        // 2) Insert new rule (Contact, SYS2)
        List<Object> payload = new List<Object>();

        Map<String, Object> rowUpdate = new Map<String, Object>();
        rowUpdate.put('sObjectName',   'Account');
        rowUpdate.put('systemApiName', 'SYS1');
        rowUpdate.put('triggerReason', 'AFTER_UPDATE');
        rowUpdate.put('isActive',      true);
        rowUpdate.put('developerName', null);
        payload.add(rowUpdate);

        Map<String, Object> rowInsert = new Map<String, Object>();
        rowInsert.put('sObjectName',   'Contact');
        rowInsert.put('systemApiName', 'SYS2');
        rowInsert.put('triggerReason', 'AFTER_INSERT');
        rowInsert.put('isActive',      false);
        rowInsert.put('developerName', 'CONTACT_SYS2_DEV');
        payload.add(rowInsert);

        Test.startTest();
        IntegrationAdminController.saveObjectConfigs(payload);
        Test.stopTest();

        // Verify update (Account, SYS1)
        Integration_Object_Rule__c updated = [
            SELECT SObjectName__c, SystemDeveloperName__c, TriggerReason__c,
                   IsActive__c, DeveloperName__c
            FROM Integration_Object_Rule__c
            WHERE SObjectName__c = 'Account'
              AND SystemDeveloperName__c = 'SYS1'
            LIMIT 1
        ];
        System.assertEquals('AFTER_UPDATE', updated.TriggerReason__c);
        System.assertEquals(true, updated.IsActive__c);
        System.assert(!String.isBlank(updated.DeveloperName__c),
            'DeveloperName__c should be auto-generated if missing');

        // Verify insert (Contact, SYS2)
        Integration_Object_Rule__c inserted = [
            SELECT SObjectName__c, SystemDeveloperName__c, TriggerReason__c,
                   IsActive__c, DeveloperName__c
            FROM Integration_Object_Rule__c
            WHERE SObjectName__c = 'Contact'
              AND SystemDeveloperName__c = 'SYS2'
            LIMIT 1
        ];
        System.assertEquals('AFTER_INSERT', inserted.TriggerReason__c);
        System.assertEquals(false, inserted.IsActive__c);
        System.assertEquals('CONTACT_SYS2_DEV', inserted.DeveloperName__c);
    }

    @IsTest
    static void testGetObjectConfigs_noData() {
        // No rules in this test context
        List<IntegrationAdminDTOs.ObjectConfigDTO> result =
            IntegrationAdminController.getObjectConfigs();
        // Just ensure method returns non-null list
        System.assertNotEquals(null, result);
    }

    // =========================================================
    // FIELD MAPPINGS: getFieldMappings + saveFieldMappings
    // =========================================================

    @IsTest
    static void testGetAndSaveFieldMappings_insertAndUpdate() {
        // Pre-existing mapping for Account + SYS_FM, source Phone
        // DevName blank to test auto-generation
        createFieldMap('Account', 'SYS_FM', 'Phone', 'phone_old', false, 'String', null);

        // Call getFieldMappings to cover DTO mapping
        List<IntegrationAdminDTOs.FieldMapDTO> existing =
            IntegrationAdminController.getFieldMappings('Account', 'SYS_FM');
        System.assert(existing.size() >= 1);

        List<Object> mappings = new List<Object>();

        // 1) Row with blank sourceFieldAPI → skipped
        Map<String, Object> rowBlank = new Map<String, Object>();
        rowBlank.put('sourceFieldAPI', '');
        rowBlank.put('targetFieldName', 'ignored');
        rowBlank.put('isRequired', false);
        rowBlank.put('dataType', 'String');
        rowBlank.put('developerName', null);
        mappings.add(rowBlank);

        // 2) Update existing mapping for Phone
        Map<String, Object> rowUpdate = new Map<String, Object>();
        rowUpdate.put('sourceFieldAPI',  'Phone');
        rowUpdate.put('targetFieldName', 'phone_new');
        rowUpdate.put('isRequired',      true);
        rowUpdate.put('dataType',        'String');
        rowUpdate.put('developerName',   null); // force auto devName
        mappings.add(rowUpdate);

        // 3) New mapping for Name
        Map<String, Object> rowInsert = new Map<String, Object>();
        rowInsert.put('sourceFieldAPI',  'Name');
        rowInsert.put('targetFieldName', 'name_out');
        rowInsert.put('isRequired',      false);
        rowInsert.put('dataType',        'String');
        rowInsert.put('developerName',   'ACCOUNT_SYS_FM_NAME');
        mappings.add(rowInsert);

        Test.startTest();
        IntegrationAdminController.saveFieldMappings('Account', 'SYS_FM', mappings);
        Test.stopTest();

        // Verify existing Phone mapping updated
        Integration_Field_Map_Config__c phoneFm = [
            SELECT SourceFieldAPI__c, TargetFieldName__c, IsRequired__c,
                   DataType__c, DeveloperName__c
            FROM Integration_Field_Map_Config__c
            WHERE SObjectName__c = 'Account'
              AND SystemDeveloperName__c = 'SYS_FM'
              AND SourceFieldAPI__c = 'Phone'
            LIMIT 1
        ];
        System.assertEquals('phone_new', phoneFm.TargetFieldName__c);
        System.assertEquals(true, phoneFm.IsRequired__c);
        System.assertEquals('String', phoneFm.DataType__c);
        System.assert(!String.isBlank(phoneFm.DeveloperName__c),
            'DeveloperName__c should be auto-generated for Phone mapping');

        // Verify new Name mapping inserted
        Integration_Field_Map_Config__c nameFm = [
            SELECT SourceFieldAPI__c, TargetFieldName__c, IsRequired__c,
                   DataType__c, DeveloperName__c
            FROM Integration_Field_Map_Config__c
            WHERE SObjectName__c = 'Account'
              AND SystemDeveloperName__c = 'SYS_FM'
              AND SourceFieldAPI__c = 'Name'
            LIMIT 1
        ];
        System.assertEquals('name_out', nameFm.TargetFieldName__c);
        System.assertEquals(false, nameFm.IsRequired__c);
        System.assertEquals('String', nameFm.DataType__c);
        System.assertEquals('ACCOUNT_SYS_FM_NAME', nameFm.DeveloperName__c);
    }

    @IsTest
    static void testSaveFieldMappings_earlyReturns() {
        // Blank sObjectName / systemApiName / null or empty mappings → return
        Test.startTest();
        IntegrationAdminController.saveFieldMappings('', 'SYS', new List<Object>());
        IntegrationAdminController.saveFieldMappings('Account', '', new List<Object>());
        IntegrationAdminController.saveFieldMappings('Account', 'SYS', null);
        IntegrationAdminController.saveFieldMappings('Account', 'SYS', new List<Object>());
        Test.stopTest();

        // No DML expected
        System.assertEquals(0, [SELECT COUNT() FROM Integration_Field_Map_Config__c]);
    }

    @IsTest
    static void testGetFieldMappings_earlyReturns() {
        List<IntegrationAdminDTOs.FieldMapDTO> res1 =
            IntegrationAdminController.getFieldMappings('', 'SYS');
        System.assertEquals(0, res1.size());

        List<IntegrationAdminDTOs.FieldMapDTO> res2 =
            IntegrationAdminController.getFieldMappings('Account', '');
        System.assertEquals(0, res2.size());
    }

    // =========================================================
    // AVAILABLE FIELDS & INTEGRATABLE OBJECTS
    // =========================================================

    @IsTest
    static void testGetAvailableFields() {
        // Blank sObjectName → empty
        List<IntegrationAdminDTOs.FieldOptionDTO> empty =
            IntegrationAdminController.getAvailableFields('');
        System.assertEquals(0, empty.size());

        // Valid sObjectName: Account
        List<IntegrationAdminDTOs.FieldOptionDTO> fields =
            IntegrationAdminController.getAvailableFields('Account');
        System.assert(fields.size() > 0, 'Expected some fields for Account');

        Boolean hasName = false;
        for (IntegrationAdminDTOs.FieldOptionDTO f : fields) {
            if (f.apiName == 'Name') {
                hasName = true;
                break;
            }
        }
        System.assert(hasName, 'Expected Name field to be available for Account');
    }

    @IsTest
    static void testGetIntegratableObjects() {
        // We cannot create CMDT records in test,
        // but we can still call the method to cover the logic.
        List<IntegrationAdminDTOs.FieldOptionDTO> objs =
            IntegrationAdminController.getIntegratableObjects();

        // Either empty or populated depending on CMDT data in the org
        System.assertNotEquals(null, objs);
    }
}
