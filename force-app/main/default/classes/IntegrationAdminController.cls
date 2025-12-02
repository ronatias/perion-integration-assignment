// IntegrationAdminController.cls
// Purpose:
//  - Back-end for the Integration Admin LWC.
//  - Allows admins to view and edit:
//      * Integration_System__mdt
//      * Integration_Object_Config__mdt
//      * Integration_Field_Map__mdt
//  - Also exposes available fields for each SObject for dropdowns.
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
            dto.maxRetries    = sys.MaxRetries__c;
            dto.handlerClass  = sys.HandlerClass__c;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static void saveSystems(List<IntegrationAdminDTOs.SystemConfigDTO> systems) {
        if (systems == null || systems.isEmpty()) return;

        List<Integration_System__mdt> toUpsert = new List<Integration_System__mdt>();

        for (IntegrationAdminDTOs.SystemConfigDTO dto : systems) {
            Integration_System__mdt sys = Integration_System__mdt.getInstance(dto.developerName);
            if (sys == null) continue;

            sys.IsActive__c   = dto.isActive;
            sys.MaxRetries__c = dto.maxRetries;
            // HandlerClass__c typically controlled by dev team.

            toUpsert.add(sys);
        }
        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
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
        if (configs == null || configs.isEmpty()) return;

        List<Integration_Object_Config__mdt> toUpsert = new List<Integration_Object_Config__mdt>();

        for (IntegrationAdminDTOs.ObjectConfigDTO dto : configs) {
            if (String.isBlank(dto.sObjectName) || String.isBlank(dto.systemApiName)) continue;

            Integration_Object_Config__mdt cfg =
                String.isBlank(dto.developerName)
                    ? null
                    : Integration_Object_Config__mdt.getInstance(dto.developerName);

            if (cfg == null) {
                String devName = (dto.sObjectName + '_' + dto.systemApiName).replace(' ', '_');
                cfg = new Integration_Object_Config__mdt(
                    DeveloperName = devName,
                    MasterLabel   = dto.sObjectName + ' - ' + dto.systemApiName
                );
            }

            cfg.SObjectName__c   = dto.sObjectName;
            cfg.SystemApiName__c = dto.systemApiName;
            cfg.TriggerReason__c = dto.triggerReason;
            cfg.IsActive__c      = dto.isActive;

            toUpsert.add(cfg);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
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
            dto.developerName  = fm.DeveloperName;
            dto.sObjectName    = fm.SObjectName__c;
            dto.systemApiName  = fm.SystemApiName__c;
            dto.sourceFieldAPI = fm.SourceFieldAPI__c;
            dto.targetFieldName = fm.TargetFieldName__c;
            dto.isRequired     = fm.IsRequired__c;
            dto.dataType       = fm.DataType__c;
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
        if (String.isBlank(sObjectName) || String.isBlank(systemApiName) ||
            mappings == null || mappings.isEmpty()) {
            return;
        }

        List<Integration_Field_Map__mdt> toUpsert = new List<Integration_Field_Map__mdt>();

        for (IntegrationAdminDTOs.FieldMapDTO dto : mappings) {
            if (String.isBlank(dto.sourceFieldAPI)) continue;

            Integration_Field_Map__mdt fm =
                String.isBlank(dto.developerName)
                    ? null
                    : Integration_Field_Map__mdt.getInstance(dto.developerName);

            if (fm == null) {
                String devName = (dto.sObjectName + '_' +
                                  dto.systemApiName + '_' +
                                  dto.sourceFieldAPI).replace(' ', '_');
                fm = new Integration_Field_Map__mdt(
                    DeveloperName = devName,
                    MasterLabel   = dto.sObjectName + ' ' +
                                    dto.systemApiName + ' ' +
                                    dto.sourceFieldAPI
                );
            }

            fm.SObjectName__c    = sObjectName;
            fm.SystemApiName__c  = systemApiName;
            fm.SourceFieldAPI__c = dto.sourceFieldAPI;
            fm.TargetFieldName__c = dto.targetFieldName;
            fm.IsRequired__c     = dto.isRequired;
            fm.DataType__c       = dto.dataType;

            toUpsert.add(fm);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
    }

    //
    // AVAILABLE FIELDS (for dropdown in UI)
    //
    @AuraEnabled(cacheable=true)
    public static List<IntegrationAdminDTOs.FieldOptionDTO> getAvailableFields(String sObjectName) {
        List<IntegrationAdminDTOs.FieldOptionDTO> result = new List<IntegrationAdminDTOs.FieldOptionDTO>();
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

    // IntegrationAdminController.cls
    // NEW VERSION of getIntegratableObjects() – now CMDT-driven
    @AuraEnabled(cacheable=true)
    public static List<IntegrationAdminDTOs.FieldOptionDTO> getIntegratableObjects() {
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
}
