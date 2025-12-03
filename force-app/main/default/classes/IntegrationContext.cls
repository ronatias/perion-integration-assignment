// IntegrationContext.cls
// Purpose:
//  - Provide adapters with everything they need:
//      - Source SObject record (FLS-filtered data)
//      - System config (retry, handler, active flag)
//      - Object rule (which object + trigger + system)
//      - Prepared payload map (source→target mapping)
//
// v2 – CONFIG SOURCE CHANGE
//  - Original version used CMDT:
//      * Integration_System__mdt
//      * Integration_Object_Config__mdt
//  - New version uses custom objects managed by the Admin UI:
//      * Integration_System_Config__c
//      * Integration_Object_Rule__c

public class IntegrationContext {
    // Business record that triggered the integration
    public SObject record;

    // System-level configuration:
    //  - DeveloperName__c       – system key (matches Integration_Job__c.SystemApiName__c)
    //  - HandlerClass__c        – adapter class name
    //  - MaxRetries__c          – retry policy
    //  - IsActive__c            – system on/off
    public Integration_System_Config__c systemConfig;

    // Object-level rule:
    //  - SObjectName__c         – API name of the object (e.g. 'Opportunity')
    //  - SystemDeveloperName__c – link to systemConfig.DeveloperName__c
    //  - TriggerReason__c       – semantic trigger key (e.g. 'OPP_STAGE_CONTRACTING')
    //  - IsActive__c            – rule on/off
    public Integration_Object_Rule__c objectConfig;

    // Final payload as sent to the external system:
    //  - Keys:   target field names (e.g. 'totalAmount', 'closingDate')
    //  - Values: SObject field values after FLS and mapping
    public Map<String, Object> payload;
}
