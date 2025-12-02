// IntegrationContext.cls
// Purpose:
//  - Provide adapters with everything they need:
//      - Source SObject record (FLS-filtered data)
//      - System config (retry, activity)
//      - Object config (trigger context)
//      - Prepared payload map (source→target mapping)
public class IntegrationContext {
    public SObject record;
    public Integration_System__mdt systemConfig;
    public Integration_Object_Config__mdt objectConfig;
    public Map<String, Object> payload;
}
