// Case 1: Always SUCCESS.
// Also logs the payload structure that would be sent to the Billing system.
public with sharing class BillingAdapter implements IIntegrationAdapter {

    public IntegrationResult send(IntegrationContext ctx) {
        Integer attempt = (ctx.attemptNumber == null) ? 0 : ctx.attemptNumber;

        System.debug('BillingAdapter payload: ' +
            JSON.serializePretty(ctx.payload)
        );

        return IntegrationResult.success(
            'Billing success (demo, attempt ' + attempt + ')'
        );
    }
}
