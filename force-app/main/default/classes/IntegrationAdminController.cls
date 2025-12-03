// IntegrationAdminController.cls
// Purpose:
//  - Back-end for the Integration Admin LWC (integrationAdminApp).
//  - Manages three custom config objects:
//      * Integration_System_Config__c
//      * Integration_Object_Rule__c
//      * Integration_Field_Map_Config__c
//  - Also exposes:
//      * getAvailableFields(sObjectName) via Schema
//      * getIntegratableObjects() via Schema
//
// IMPORTANT IMPLEMENTATION DETAIL:
//
//  - LWC can RECEIVE custom DTOs (Apex → LWC) just fine.
//  - But sending DTOs *from* LWC back to Apex as method parameters is unreliable.
//  - Therefore all *input* methods use List<Object> and normalize via
//      JSON.deserializeUntyped(JSON.serialize(...))
//    to get a List<Map<String,Object>>.
//
//  - Parameter names for save methods are aligned with the LWC calls:
//
//    LWC: saveSystems({ systems: this.systems })
//         → Apex: saveSystems(List<Object> systems)
//
//    LWC: saveObjectConfigs({ configs: this.objectConfigs })
//         → Apex: saveObjectConfigs(List<Object> configs)
//
//    LWC: saveFieldMappings({
//           sObjectName: this.selectedSObjectName,
//           systemApiName: this.selectedSystemApiName,
//           mappings: this.fieldMappings
//         })
//         → Apex: saveFieldMappings(String sObjectName, String systemApiName, List<Object> mappings)
//

public with sharing class IntegrationAdminController {

    // =========================================================
    // SYSTEM CONFIG  (Integration_System_Config__c)
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static List<IntegrationAdminDTOs.SystemConfigDTO> getSystems() {
        List<IntegrationAdminDTOs.SystemConfigDTO> result =
            new List<IntegrationAdminDTOs.SystemConfigDTO>();

        for (Integration_System_Config__c sys : [
            SELECT Name,
                   DeveloperName__c,
                   IsActive__c,
                   HandlerClass__c,
                   MaxRetries__c
            FROM Integration_System_Config__c
            ORDER BY Name
        ]) {
            IntegrationAdminDTOs.SystemConfigDTO dto =
                new IntegrationAdminDTOs.SystemConfigDTO();
            dto.developerName = sys.DeveloperName__c;
            dto.label         = sys.Name;
            dto.isActive      = sys.IsActive__c;
            dto.handlerClass  = sys.HandlerClass__c;
            dto.maxRetries    = (sys.MaxRetries__c == null)
                ? null
                : Integer.valueOf(sys.MaxRetries__c.intValue());
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static void saveSystems(List<Object> systems) {
        System.debug('===== RAW systems FROM LWC ===== ' + JSON.serialize(systems));

        if (systems == null || systems.isEmpty()) {
            System.debug('===== systems NULL/EMPTY =====');
            return;
        }

        // ============================================================
        // UPDATE: normalize payload to List<Map<String,Object>>
        // ============================================================
        List<Object> normalized =
            (List<Object>) JSON.deserializeUntyped(JSON.serialize(systems));
        System.debug('saveSystems – NORMALIZED payload: ' + normalized);

        // Load existing systems keyed by DeveloperName__c
        Map<String, Integration_System_Config__c> byDevName =
            new Map<String, Integration_System_Config__c>();

        for (Integration_System_Config__c sys : [
            SELECT Id, DeveloperName__c, IsActive__c, MaxRetries__c, HandlerClass__c
            FROM Integration_System_Config__c
        ]) {
            if (!String.isBlank(sys.DeveloperName__c)) {
                byDevName.put(sys.DeveloperName__c, sys);
            }
        }
        System.debug('saveSystems – existing keys: ' + byDevName.keySet());

        List<Integration_System_Config__c> toInsert = new List<Integration_System_Config__c>();
        List<Integration_System_Config__c> toUpdate = new List<Integration_System_Config__c>();

        Integer rowIndex = 0;
        for (Object raw : normalized) {
            rowIndex++;
            if (!(raw instanceof Map<String, Object>)) {
                System.debug('saveSystems – row ' + rowIndex +
                             ' is not a Map<String,Object>, skipping: ' + raw);
                continue;
            }

            Map<String, Object> row = (Map<String, Object>) raw;

            String devName      = (String) row.get('developerName');
            Object isActiveVal  = row.get('isActive');
            Object mrVal        = row.get('maxRetries');

            System.debug('saveSystems – row ' + rowIndex +
                         ' devName=' + devName +
                         ', raw isActive=' + isActiveVal +
                         ', raw maxRetries=' + mrVal);

            if (String.isBlank(devName)) {
                System.debug('saveSystems – row ' + rowIndex +
                             ' has EMPTY developerName, skipping');
                continue;
            }

            // ============================================================
            // UPDATE: ROBUST BOOLEAN PARSER
            // Always produces TRUE or FALSE, never NULL.
            // ============================================================
            Boolean isActiveParsed = null;

            if (isActiveVal instanceof Boolean) {
                isActiveParsed = (Boolean) isActiveVal;
            }
            else if (isActiveVal instanceof String) {
                String s = ((String) isActiveVal).trim();
                if (!String.isBlank(s)) {
                    isActiveParsed = 'true'.equalsIgnoreCase(s);
                }
            }

            System.debug('saveSystems – row ' + rowIndex +
                         ' parsed isActive=' + isActiveParsed);

            // ============================================================
            // UPDATE: ROBUST INTEGER PARSER
            // ============================================================
            Integer maxRetriesParsed = null;

            if (mrVal instanceof Integer) {
                maxRetriesParsed = (Integer) mrVal;
            } else if (mrVal instanceof Long) {
                maxRetriesParsed = Integer.valueOf((Long) mrVal);
            } else if (mrVal instanceof Decimal) {
                maxRetriesParsed = ((Decimal) mrVal).intValue();
            } else if (mrVal instanceof String) {
                String s = ((String) mrVal).trim();
                if (!String.isBlank(s)) {
                    try {
                        maxRetriesParsed = Integer.valueOf(s);
                    } catch (Exception e) {
                        System.debug('saveSystems – cannot parse maxRetries from String: ' + s);
                    }
                }
            }

            System.debug('saveSystems – row ' + rowIndex +
                         ' parsed maxRetries=' + maxRetriesParsed);

            // ============================================================
            // Existing or new system row
            // ============================================================
            Integration_System_Config__c sys = byDevName.get(devName);
            Boolean isNew = (sys == null);

            if (isNew) {
                sys = new Integration_System_Config__c();
                sys.DeveloperName__c = devName;
                System.debug('saveSystems – INSERT new system for devName=' + devName);
            } else {
                System.debug('saveSystems – UPDATE existing Id=' + sys.Id +
                             ' for devName=' + devName);
            }

            // ============================================================
            // UPDATE: always assign the value (false MUST overwrite true)
            // If null → keep existing value
            // ============================================================
            if (isActiveParsed != null) {
                sys.IsActive__c = isActiveParsed;
            }

            if (maxRetriesParsed != null) {
                sys.MaxRetries__c = maxRetriesParsed;
            }

            // HandlerClass__c remains read-only (by design)

            if (isNew) {
                toInsert.add(sys);
            } else {
                toUpdate.add(sys);
            }
        }

        if (!toInsert.isEmpty()) insert toInsert;
        if (!toUpdate.isEmpty()) update toUpdate;

        System.debug('saveSystems – DML completed.');
    }


    // =========================================================
    // OBJECT RULES  (Integration_Object_Rule__c)
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static List<IntegrationAdminDTOs.ObjectConfigDTO> getObjectConfigs() {
        List<IntegrationAdminDTOs.ObjectConfigDTO> result =
            new List<IntegrationAdminDTOs.ObjectConfigDTO>();

        for (Integration_Object_Rule__c cfg : [
            SELECT DeveloperName__c,
                   SObjectName__c,
                   SystemDeveloperName__c,
                   TriggerReason__c,
                   IsActive__c
            FROM Integration_Object_Rule__c
            ORDER BY SObjectName__c, SystemDeveloperName__c
        ]) {
            IntegrationAdminDTOs.ObjectConfigDTO dto =
                new IntegrationAdminDTOs.ObjectConfigDTO();
            dto.developerName = cfg.DeveloperName__c;
            dto.sObjectName   = cfg.SObjectName__c;
            dto.systemApiName = cfg.SystemDeveloperName__c;
            dto.triggerReason = cfg.TriggerReason__c;
            dto.isActive      = cfg.IsActive__c;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static void saveObjectConfigs(List<Object> configs) {

        if (configs == null || configs.isEmpty()) {
            return;
        }

        // Normalize to plain maps
        List<Object> normalized =
            (List<Object>) JSON.deserializeUntyped(JSON.serialize(configs));

        // Existing rules keyed by "SObject|System"
        // NOTE: TriggerReason__c is intentionally NOT part of the key anymore.
        //       We enforce exactly one rule per (SObjectName__c, SystemDeveloperName__c).
        Map<String, Integration_Object_Rule__c> existingByKey =
            new Map<String, Integration_Object_Rule__c>();

        for (Integration_Object_Rule__c cfg : [
            SELECT Id,
                DeveloperName__c,
                SObjectName__c,
                SystemDeveloperName__c,
                TriggerReason__c,
                IsActive__c
            FROM Integration_Object_Rule__c
        ]) {
            String key = cfg.SObjectName__c + '|' + cfg.SystemDeveloperName__c;
            existingByKey.put(key, cfg);
        }

        List<Integration_Object_Rule__c> toInsert = new List<Integration_Object_Rule__c>();
        List<Integration_Object_Rule__c> toUpdate = new List<Integration_Object_Rule__c>();

        // Track duplicates in the incoming payload itself.
        Set<String> seenInPayload = new Set<String>();

        Integer idx = 0;
        for (Object raw : normalized) {
            Map<String, Object> row = (Map<String, Object>) raw;

            String sObjectName   = (String)  row.get('sObjectName');
            String systemApiName = (String)  row.get('systemApiName');
            String triggerReason = (String)  row.get('triggerReason');
            Boolean isActive     = (Boolean) row.get('isActive');
            String devName       = (String)  row.get('developerName');

            if (String.isBlank(sObjectName) || String.isBlank(systemApiName)) {
                continue;
            }

            String key = sObjectName + '|' + systemApiName;

            if (seenInPayload.contains(key)) {
                throw new AuraHandledException(
                    'Duplicate Object + System combination detected for ' +
                    sObjectName + ' / ' + systemApiName +
                    '. Only one Integration_Object_Rule__c is allowed per Object + System.'
                );
            }
            seenInPayload.add(key);

            Integration_Object_Rule__c cfg = existingByKey.get(key);
            Boolean isNew = (cfg == null);

            if (isNew) {
                cfg = new Integration_Object_Rule__c();
                cfg.SObjectName__c         = sObjectName;
                cfg.SystemDeveloperName__c = systemApiName;
                cfg.TriggerReason__c       = triggerReason;
            } else {
                cfg.TriggerReason__c = triggerReason;
            }

            cfg.IsActive__c = isActive;

            if (String.isBlank(cfg.DeveloperName__c)) {
                if (String.isBlank(devName)) {
                    devName = (sObjectName + '_' + systemApiName).replace(' ', '_');
                    if (!String.isBlank(triggerReason)) {
                        devName += '_' + triggerReason.replace(' ', '_');
                    }
                }
                cfg.DeveloperName__c = devName;
            }

            if (isNew) {
                toInsert.add(cfg);
            } else {
                toUpdate.add(cfg);
            }
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // =========================================================
    // FIELD MAPPINGS  (Integration_Field_Map_Config__c)
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static List<IntegrationAdminDTOs.FieldMapDTO> getFieldMappings(
        String sObjectName,
        String systemApiName
    ) {
        List<IntegrationAdminDTOs.FieldMapDTO> result =
            new List<IntegrationAdminDTOs.FieldMapDTO>();
        if (String.isBlank(sObjectName) || String.isBlank(systemApiName)) return result;

        for (Integration_Field_Map_Config__c fm : [
            SELECT DeveloperName__c,
                   SObjectName__c,
                   SystemDeveloperName__c,
                   SourceFieldAPI__c,
                   TargetFieldName__c,
                   IsRequired__c,
                   DataType__c
            FROM Integration_Field_Map_Config__c
            WHERE SObjectName__c = :sObjectName
              AND SystemDeveloperName__c = :systemApiName
            ORDER BY SourceFieldAPI__c
        ]) {
            IntegrationAdminDTOs.FieldMapDTO dto =
                new IntegrationAdminDTOs.FieldMapDTO();
            dto.developerName   = fm.DeveloperName__c;
            dto.sObjectName     = fm.SObjectName__c;
            dto.systemApiName   = fm.SystemDeveloperName__c;
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
        List<Object> mappings
    ) {
        if (String.isBlank(sObjectName) || String.isBlank(systemApiName)) {
            return;
        }
        if (mappings == null || mappings.isEmpty()) {
            return;
        }

        List<Object> normalized =
            (List<Object>) JSON.deserializeUntyped(JSON.serialize(mappings));

        Map<String, Integration_Field_Map_Config__c> existingBySource =
            new Map<String, Integration_Field_Map_Config__c>();

        for (Integration_Field_Map_Config__c fm : [
            SELECT Id,
                DeveloperName__c,
                SObjectName__c,
                SystemDeveloperName__c,
                SourceFieldAPI__c,
                TargetFieldName__c,
                IsRequired__c,
                DataType__c
            FROM Integration_Field_Map_Config__c
            WHERE SObjectName__c = :sObjectName
            AND SystemDeveloperName__c = :systemApiName
        ]) {
            if (!String.isBlank(fm.SourceFieldAPI__c)) {
                existingBySource.put(fm.SourceFieldAPI__c, fm);
            }
        }

        List<Integration_Field_Map_Config__c> toInsert =
            new List<Integration_Field_Map_Config__c>();
        List<Integration_Field_Map_Config__c> toUpdate =
            new List<Integration_Field_Map_Config__c>();

        Set<String> seenInPayload = new Set<String>();

        Integer idx = 0;
        for (Object raw : normalized) {
            Map<String, Object> row = (Map<String, Object>) raw;

            String sourceFieldAPI  = (String)  row.get('sourceFieldAPI');
            String targetFieldName = (String)  row.get('targetFieldName');
            Boolean isRequired     = (Boolean) row.get('isRequired');
            String dataType        = (String)  row.get('dataType');
            String devName         = (String)  row.get('developerName');

            if (String.isBlank(sourceFieldAPI)) {
                continue;
            }

            if (seenInPayload.contains(sourceFieldAPI)) {
                throw new AuraHandledException(
                    'Duplicate field mapping detected for source field ' +
                    sourceFieldAPI + ' on ' + sObjectName + ' / ' + systemApiName +
                    '. Each source field can only be mapped once per Object + System.'
                );
            }
            seenInPayload.add(sourceFieldAPI);

            Integration_Field_Map_Config__c fm = existingBySource.get(sourceFieldAPI);
            Boolean isNew = (fm == null);

            if (isNew) {
                fm = new Integration_Field_Map_Config__c();
                fm.SObjectName__c         = sObjectName;
                fm.SystemDeveloperName__c = systemApiName;
                fm.SourceFieldAPI__c      = sourceFieldAPI;
            }

            fm.TargetFieldName__c = targetFieldName;
            fm.IsRequired__c      = isRequired;
            fm.DataType__c        = dataType;

            if (String.isBlank(fm.DeveloperName__c)) {
                if (String.isBlank(devName)) {
                    devName = (sObjectName + '_' + systemApiName + '_' + sourceFieldAPI)
                        .replace(' ', '_');
                }
                fm.DeveloperName__c = devName;
            }

            if (isNew) {
                toInsert.add(fm);
            } else {
                toUpdate.add(fm);
            }
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // =========================================================
    // AVAILABLE FIELDS (for field-mapping dropdown)
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static List<IntegrationAdminDTOs.FieldOptionDTO> getAvailableFields(String sObjectName) {
        List<IntegrationAdminDTOs.FieldOptionDTO> result =
            new List<IntegrationAdminDTOs.FieldOptionDTO>();

        if (String.isBlank(sObjectName)) return result;

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(sObjectName);
        if (sType == null) return result;

        Schema.DescribeSObjectResult d = sType.getDescribe();
        Map<String, Schema.SObjectField> fields = d.fields.getMap();

        for (String api : fields.keySet()) {
            Schema.DescribeFieldResult fd = fields.get(api).getDescribe();
            IntegrationAdminDTOs.FieldOptionDTO f =
                new IntegrationAdminDTOs.FieldOptionDTO();
            f.apiName = api;
            f.label   = fd.getLabel();
            result.add(f);
        }

        return result;
    }

    // =========================================================
    // INTEGRATABLE OBJECTS (for SObject dropdown)
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static List<IntegrationAdminDTOs.FieldOptionDTO> getIntegratableObjects() {
        List<IntegrationAdminDTOs.FieldOptionDTO> result =
            new List<IntegrationAdminDTOs.FieldOptionDTO>();

        // Governed list of integratable objects via CMDT
        for (Integration_Enabled_Object__mdt def : [
            SELECT SObjectName__c, DisplayLabel__c, IsActive__c
            FROM Integration_Enabled_Object__mdt
            WHERE IsActive__c = true
            ORDER BY SObjectName__c
        ]) {
            Schema.SObjectType sType = Schema.getGlobalDescribe().get(def.SObjectName__c);
            if (sType == null) {
                System.debug('WARN [getIntegratableObjects]: CMDT declares SObject ' +
                            def.SObjectName__c + ' but it does not exist in this org');
                continue;
            }

            Schema.DescribeSObjectResult sDesc = sType.getDescribe();

            IntegrationAdminDTOs.FieldOptionDTO dto =
                new IntegrationAdminDTOs.FieldOptionDTO();
            dto.apiName = def.SObjectName__c;
            dto.label   = String.isBlank(def.DisplayLabel__c)
                ? sDesc.getLabel()
                : def.DisplayLabel__c;

            result.add(dto);
        }

        return result;
    }
}
