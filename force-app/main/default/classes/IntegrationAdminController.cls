// IntegrationAdminController.cls
// Purpose:
//  - Back-end for the Integration Admin LWC (integrationAdminApp).
//  - Allows admins to view and edit integration configuration stored in Custom Metadata:
//      * Integration_System__mdt
//      * Integration_Object_Config__mdt
//      * Integration_Field_Map__mdt
//      * Integration_Enabled_Object__mdt (governed list of allowed SObjects)
//  - Uses the Apex Metadata API (Metadata.Operations.enqueueDeployment) because
//    DML is NOT allowed on Custom Metadata types.
//
// Key design points:
//  - Read paths use normal SOQL on CMDT.
//  - Write paths build Metadata.CustomMetadata records and deploy them.
//  - DTO types come from IntegrationAdminDTOs to keep UI and storage decoupled.

public with sharing class IntegrationAdminController {

    //
    // SYSTEM CONFIG
    //

    @AuraEnabled(cacheable=true)
    public static List<IntegrationAdminDTOs.SystemConfigDTO> getSystems() {
        List<IntegrationAdminDTOs.SystemConfigDTO> result = new List<IntegrationAdminDTOs.SystemConfigDTO>();

        for (Integration_System__mdt sys : [
            SELECT DeveloperName, MasterLabel, IsActive__c, HandlerClass__c, MaxRetries__c
            FROM Integration_System__mdt
            ORDER BY MasterLabel
        ]) {
            IntegrationAdminDTOs.SystemConfigDTO dto = new IntegrationAdminDTOs.SystemConfigDTO();
            dto.developerName = sys.DeveloperName;
            dto.label         = sys.MasterLabel;
            dto.isActive      = sys.IsActive__c;

            // MaxRetries__c is Number(Decimal) on CMDT; DTO uses Integer.
            dto.maxRetries = (sys.MaxRetries__c == null)
                ? null
                : Integer.valueOf(sys.MaxRetries__c.intValue());

            dto.handlerClass = sys.HandlerClass__c;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static void saveSystems(List<IntegrationAdminDTOs.SystemConfigDTO> systems) {
        // Purpose:
        //  - Persist edited Integration_System__mdt rows using Metadata API.
        // Notes:
        //  - We “upsert” based on fullName = 'Integration_System__mdt.<DeveloperName>'.
        if (systems == null || systems.isEmpty()) return;

        List<Metadata.CustomMetadata> toDeploy = new List<Metadata.CustomMetadata>();

        for (IntegrationAdminDTOs.SystemConfigDTO dto : systems) {
            if (String.isBlank(dto.developerName)) continue;

            Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
            cmd.fullName = 'Integration_System__mdt.' + dto.developerName;
            cmd.label    = dto.label;

            // Initialize values list
            cmd.values = new List<Metadata.CustomMetadataValue>();

            addCmdValue(cmd, 'IsActive__c', dto.isActive);
            addCmdValue(cmd, 'MaxRetries__c', dto.maxRetries);
            addCmdValue(cmd, 'HandlerClass__c', dto.handlerClass);

            toDeploy.add(cmd);
        }

        deployCustomMetadata(toDeploy);
    }

    //
    // OBJECT CONFIG
    //

    @AuraEnabled(cacheable=true)
    public static List<IntegrationAdminDTOs.ObjectConfigDTO> getObjectConfigs() {
        List<IntegrationAdminDTOs.ObjectConfigDTO> result = new List<IntegrationAdminDTOs.ObjectConfigDTO>();

        for (Integration_Object_Config__mdt cfg : [
            SELECT DeveloperName, SObjectName__c, SystemApiName__c,
                   TriggerReason__c, IsActive__c
            FROM Integration_Object_Config__mdt
            ORDER BY SObjectName__c, SystemApiName__c
        ]) {
            IntegrationAdminDTOs.ObjectConfigDTO dto = new IntegrationAdminDTOs.ObjectConfigDTO();
            dto.developerName = cfg.DeveloperName;
            dto.sObjectName   = cfg.SObjectName__c;
            dto.systemApiName = cfg.SystemApiName__c;
            dto.triggerReason = cfg.TriggerReason__c;
            dto.isActive      = cfg.IsActive__c;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static void saveObjectConfigs(List<IntegrationAdminDTOs.ObjectConfigDTO> configs) {
        // Purpose:
        //  - Create/update Integration_Object_Config__mdt records
        //    via Metadata API (no direct DML on CMDT).
        // Notes:
        //  - We build a deterministic DeveloperName when missing.
        if (configs == null || configs.isEmpty()) return;

        List<Metadata.CustomMetadata> toDeploy = new List<Metadata.CustomMetadata>();

        for (IntegrationAdminDTOs.ObjectConfigDTO dto : configs) {
            if (String.isBlank(dto.sObjectName) || String.isBlank(dto.systemApiName)) continue;

            String devName = dto.developerName;
            if (String.isBlank(devName)) {
                devName = (dto.sObjectName + '_' + dto.systemApiName).replace(' ', '_');
            }

            Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
            cmd.fullName = 'Integration_Object_Config__mdt.' + devName;
            cmd.label    = dto.sObjectName + ' - ' + dto.systemApiName;

            cmd.values = new List<Metadata.CustomMetadataValue>();

            addCmdValue(cmd, 'SObjectName__c', dto.sObjectName);
            addCmdValue(cmd, 'SystemApiName__c', dto.systemApiName);
            addCmdValue(cmd, 'TriggerReason__c', dto.triggerReason);
            addCmdValue(cmd, 'IsActive__c', dto.isActive);

            toDeploy.add(cmd);
        }

        deployCustomMetadata(toDeploy);
    }

    //
    // FIELD MAPPINGS
    //

    @AuraEnabled(cacheable=true)
    public static List<IntegrationAdminDTOs.FieldMapDTO> getFieldMappings(
        String sObjectName,
        String systemApiName
    ) {
        List<IntegrationAdminDTOs.FieldMapDTO> result = new List<IntegrationAdminDTOs.FieldMapDTO>();
        if (String.isBlank(sObjectName) || String.isBlank(systemApiName)) return result;

        for (Integration_Field_Map__mdt fm : [
            SELECT DeveloperName, SObjectName__c, SystemApiName__c,
                   SourceFieldAPI__c, TargetFieldName__c, IsRequired__c, DataType__c
            FROM Integration_Field_Map__mdt
            WHERE SObjectName__c = :sObjectName
              AND SystemApiName__c = :systemApiName
            ORDER BY SourceFieldAPI__c
        ]) {
            IntegrationAdminDTOs.FieldMapDTO dto = new IntegrationAdminDTOs.FieldMapDTO();
            dto.developerName   = fm.DeveloperName;
            dto.sObjectName     = fm.SObjectName__c;
            dto.systemApiName   = fm.SystemApiName__c;
            dto.sourceFieldAPI  = fm.SourceFieldAPI__c;
            dto.targetFieldName = fm.TargetFieldName__c;
            dto.isRequired      = fm.IsRequired__c;
            dto.dataType        = fm.DataType__c;
            result.add(dto);
        }

        return result;
    }

    @AuraEnabled
    public static void saveFieldMappings(
        String sObjectName,
        String systemApiName,
        List<IntegrationAdminDTOs.FieldMapDTO> mappings
    ) {
        // Purpose:
        //  - Create/update Integration_Field_Map__mdt records via Metadata API.
        if (String.isBlank(sObjectName) || String.isBlank(systemApiName) ||
            mappings == null || mappings.isEmpty()) {
            return;
        }

        List<Metadata.CustomMetadata> toDeploy = new List<Metadata.CustomMetadata>();

        for (IntegrationAdminDTOs.FieldMapDTO dto : mappings) {
            if (String.isBlank(dto.sourceFieldAPI)) continue;

            String devName = dto.developerName;
            if (String.isBlank(devName)) {
                devName = (sObjectName + '_' + systemApiName + '_' + dto.sourceFieldAPI)
                    .replace(' ', '_');
            }

            Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
            cmd.fullName = 'Integration_Field_Map__mdt.' + devName;
            cmd.label    = sObjectName + ' ' + systemApiName + ' ' + dto.sourceFieldAPI;

            cmd.values = new List<Metadata.CustomMetadataValue>();

            addCmdValue(cmd, 'SObjectName__c', sObjectName);
            addCmdValue(cmd, 'SystemApiName__c', systemApiName);
            addCmdValue(cmd, 'SourceFieldAPI__c', dto.sourceFieldAPI);
            addCmdValue(cmd, 'TargetFieldName__c', dto.targetFieldName);
            addCmdValue(cmd, 'IsRequired__c', dto.isRequired);
            addCmdValue(cmd, 'DataType__c', dto.dataType);

            toDeploy.add(cmd);
        }

        deployCustomMetadata(toDeploy);
    }

    //
    // AVAILABLE FIELDS (for field-mapping dropdown)
    //

    @AuraEnabled(cacheable=true)
    public static List<IntegrationAdminDTOs.FieldOptionDTO> getAvailableFields(String sObjectName) {
        // Purpose:
        //  - Return all fields for a given SObject so the admin can choose
        //    which ones to map in Integration_Field_Map__mdt.
        List<IntegrationAdminDTOs.FieldOptionDTO> result =
            new List<IntegrationAdminDTOs.FieldOptionDTO>();

        if (String.isBlank(sObjectName)) return result;

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(sObjectName);
        if (sType == null) return result;

        Schema.DescribeSObjectResult d = sType.getDescribe();
        Map<String, Schema.SObjectField> fields = d.fields.getMap();

        for (String api : fields.keySet()) {
            Schema.DescribeFieldResult fd = fields.get(api).getDescribe();
            IntegrationAdminDTOs.FieldOptionDTO f = new IntegrationAdminDTOs.FieldOptionDTO();
            f.apiName = api;
            f.label   = fd.getLabel();
            result.add(f);
        }

        return result;
    }

    //
    // INTEGRATABLE OBJECTS (governed by CMDT)
    //

    @AuraEnabled(cacheable=true)
    public static List<IntegrationAdminDTOs.FieldOptionDTO> getIntegratableObjects() {
        // Purpose:
        //  - Provide the list of SObject API names the admin can select
        //    when configuring Object→System mappings.
        // Governance:
        //  - Driven by Integration_Enabled_Object__mdt, so only objects
        //    explicitly marked IsActive__c = true appear in the UI.
        List<IntegrationAdminDTOs.FieldOptionDTO> result =
            new List<IntegrationAdminDTOs.FieldOptionDTO>();

        for (Integration_Enabled_Object__mdt def : [
            SELECT SObjectName__c, DisplayLabel__c, IsActive__c
            FROM Integration_Enabled_Object__mdt
            WHERE IsActive__c = true
            ORDER BY SObjectName__c
        ]) {
            IntegrationAdminDTOs.FieldOptionDTO dto = new IntegrationAdminDTOs.FieldOptionDTO();
            dto.apiName = def.SObjectName__c;
            dto.label   = String.isBlank(def.DisplayLabel__c)
                ? def.SObjectName__c
                : def.DisplayLabel__c;
            result.add(dto);
        }

        return result;
    }

    //
    // PRIVATE HELPERS: Metadata deployment helpers
    //

    // Helper to add a CustomMetadataValue to a CustomMetadata record
    private static void addCmdValue(Metadata.CustomMetadata cmd, String fieldApi, Object value) {
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
        v.field = fieldApi;
        v.value = value;
        if (cmd.values == null) {
            cmd.values = new List<Metadata.CustomMetadataValue>();
        }
        cmd.values.add(v);
    }

    // Helper to deploy a batch of CustomMetadata records
    private static void deployCustomMetadata(List<Metadata.CustomMetadata> records) {
        if (records == null || records.isEmpty()) return;

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        for (Metadata.CustomMetadata cmd : records) {
            container.addMetadata(cmd);
        }

        // We don't need a callback for this assignment, so pass null.
        // Admin may need to refresh the UI after a few seconds to see changes.
        Metadata.Operations.enqueueDeployment(container, null);
    }
}
