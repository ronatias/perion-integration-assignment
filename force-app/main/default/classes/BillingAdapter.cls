// BillingAdapter.cls
// Purpose:
//  - Simulate Billing system integration.
//  - Demonstrate temp vs permanent failures based on payload.
public with sharing class BillingAdapter implements IIntegrationAdapter {

    public IntegrationResult send(IntegrationContext ctx) {
        // Value mapped via Integration_Field_Map__mdt.TargetFieldName__c = 'totalAmount'
        Decimal amount = (Decimal) ctx.payload.get('totalAmount');

        // Simulate a business validation error (permanent)
        if (amount != null && amount > 100000) {
            return IntegrationResult.permanentError(400, 'Amount too large for Billing');
        }

        // Simulate 503 transient issues
        if (Math.random() < 0.3) {
            return IntegrationResult.tempError(503, 'Billing system temporarily unavailable');
        }

        return IntegrationResult.success('Billing OK');
    }
}
