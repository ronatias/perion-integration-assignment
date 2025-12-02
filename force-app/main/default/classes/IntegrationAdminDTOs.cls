// IntegrationAdminDTOs.cls
// Purpose:
//  - Simple DTO classes to decouple LWC JSON from internal CMDT/SObject structures.
//  - Used by IntegrationAdminController to send structured data to the UI.
public with sharing class IntegrationAdminDTOs {

    public class SystemConfigDTO {
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Integer maxRetries;
        @AuraEnabled public String handlerClass;
    }

    public class ObjectConfigDTO {
        @AuraEnabled public String developerName;
        @AuraEnabled public String sObjectName;
        @AuraEnabled public String systemApiName;
        @AuraEnabled public String triggerReason;
        @AuraEnabled public Boolean isActive;
    }

    public class FieldMapDTO {
        @AuraEnabled public String developerName;
        @AuraEnabled public String sObjectName;
        @AuraEnabled public String systemApiName;
        @AuraEnabled public String sourceFieldAPI;
        @AuraEnabled public String targetFieldName;
        @AuraEnabled public Boolean isRequired;
        @AuraEnabled public String dataType;
    }

    public class FieldOptionDTO {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
    }
}
