// Case 3: First attempt TEMP FAIL, second+ attempts PERMANENT FAIL.
// This demonstrates that after a retry, we can classify it as permanent.
// Also logs the payload structure.
public with sharing class DocAdapter implements IIntegrationAdapter {

    public IntegrationResult send(IntegrationContext ctx) {
        Integer attempt = (ctx.attemptNumber == null) ? 0 : ctx.attemptNumber;

        System.debug('=== DocAdapter – attempt=' + attempt);
        System.debug('DocAdapter payload: ' +
            JSON.serializePretty(ctx.payload)
        );

        // First attempt → temp error
        if (attempt == 0) {
            return IntegrationResult.tempError(
                503,
                'DOC demo – temporary failure on first attempt'
            );
        }

        // Second+ attempts → permanent failure
        return IntegrationResult.permanentError(
            400,
            'DOC demo – permanent failure on attempt ' + attempt
        );
    }
}
