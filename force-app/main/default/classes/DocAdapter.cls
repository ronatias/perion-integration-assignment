// DocAdapter.cls
// Purpose:
//  - Simulate document generation integration.
//  - Requires contractName (mapped from Contract_Name__c).
public with sharing class DocAdapter implements IIntegrationAdapter {

    public IntegrationResult send(IntegrationContext ctx) {
        Object contractName = ctx.payload.get('contractName');
        if (contractName == null) {
            return IntegrationResult.permanentError(400, 'Missing contract name');
        }

        return IntegrationResult.success('Document generated');
    }
}
