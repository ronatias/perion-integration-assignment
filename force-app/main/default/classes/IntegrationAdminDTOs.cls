// IntegrationAdminDTOs.cls
// Purpose:
//  - Simple DTO containers used between LWC and Apex for the Integration Admin UI.
//  - All fields are @AuraEnabled so LWC can send/receive them over the wire.

public with sharing class IntegrationAdminDTOs {

    // ----------------- SYSTEM CONFIG DTO -----------------
    public class SystemConfigDTO {
        @AuraEnabled public String  developerName; // e.g. 'BILLING'
        @AuraEnabled public String  label;         // UI label (Name / auto-number)
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Integer maxRetries;
        @AuraEnabled public String  handlerClass;
    }

    // ----------------- OBJECT CONFIG DTO -----------------
    // Represents Integration_Object_Rule__c
    public class ObjectConfigDTO {
        @AuraEnabled public String  developerName; // optional for now
        @AuraEnabled public String  sObjectName;   // e.g. 'Opportunity'
        @AuraEnabled public String  systemApiName; // e.g. 'BILLING'
        @AuraEnabled public String  triggerReason; // e.g. 'OPP_STAGE_CONTRACTING'
        @AuraEnabled public Boolean isActive;
    }

    // ----------------- FIELD MAP DTO -----------------
    // Represents Integration_Field_Map_Config__c
    public class FieldMapDTO {
        @AuraEnabled public String  developerName;   // optional
        @AuraEnabled public String  sObjectName;     // e.g. 'Opportunity'
        @AuraEnabled public String  systemApiName;   // e.g. 'BILLING'
        @AuraEnabled public String  sourceFieldAPI;  // e.g. 'Amount'
        @AuraEnabled public String  targetFieldName; // e.g. 'totalAmount'
        @AuraEnabled public Boolean isRequired;
        @AuraEnabled public String  dataType;        // 'String', 'Number', 'Date', ...
    }

    // ----------------- FIELD OPTION DTO -----------------
    // Used for combobox options (both fields & objects)
    public class FieldOptionDTO {
        @AuraEnabled public String apiName; // e.g. 'Amount'
        @AuraEnabled public String label;   // e.g. 'Amount'
    }
}
