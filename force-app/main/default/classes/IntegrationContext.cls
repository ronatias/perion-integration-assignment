// Purpose:
//  - Provide adapters with:
//      - Source record (SObject)
//      - System config (Integration_System_Config__c)
//      - Object rule (Integration_Object_Rule__c)
//      - Prepared payload (mapped fields)
//      - attemptNumber: how many times we've tried this job so far (0 = first attempt)
public class IntegrationContext {
    public SObject record;
    public Integration_System_Config__c systemConfig;
    public Integration_Object_Rule__c objectConfig;
    public Map<String, Object> payload;
    public Integer attemptNumber;
}
