// Case 2: First attempt TEMP FAIL, second (and later) attempts SUCCESS.
// Uses ctx.attemptNumber to know which phase we are in.
// Also logs the payload sent to DWH.
public with sharing class DwhAdapter implements IIntegrationAdapter {

    public IntegrationResult send(IntegrationContext ctx) {
        Integer attempt = (ctx.attemptNumber == null) ? 0 : ctx.attemptNumber;

        System.debug('=== DwhAdapter – attempt=' + attempt);
        System.debug('DwhAdapter payload: ' +
            JSON.serializePretty(ctx.payload)
        );

        // First attempt → temp error (retryable)
        if (attempt == 0) {
            return IntegrationResult.tempError(
                503,
                'DWH demo – temporary failure on first attempt'
            );
        }

        // Second+ attempt → success
        return IntegrationResult.success(
            'DWH demo – success on attempt ' + attempt
        );
    }
}
