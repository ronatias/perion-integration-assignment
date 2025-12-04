@IsTest
private class DwhAdapterTest {

    @IsTest
    static void testSend_firstAttempt_tempFailure() {
        // Arrange – simulate an initial delivery attempt where the adapter intentionally returns a retryable error
        DwhAdapter adapter = new DwhAdapter();

        IntegrationContext ctx = new IntegrationContext();
        ctx.attemptNumber = 0; // First attempt → adapter should classify as temporary failure
        ctx.payload = new Map<String, Object>{
            'recordId' => '001XXXXXXXXXXXX',
            'event'    => 'UPDATE'
        };

        // Act – execute adapter logic for first attempt
        IntegrationResult result = adapter.send(ctx);

        // Assert – ensure this attempt is recognized as a temporary DWH error
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(false, result.isSuccess,
            'First attempt should not be success'
        );
        System.assertEquals(true, result.isTemporaryError,
            'First attempt should be a temporary error'
        );
        System.assertEquals(503, result.statusCode,
            'Expected 503 for temporary DWH error'
        );
        System.assert(result.message.contains('temporary failure'),
            'Expected message to indicate temporary failure'
        );
    }

    @IsTest
    static void testSend_secondAttempt_success() {
        // Arrange – simulate a subsequent retry where the adapter transitions to success
        DwhAdapter adapter = new DwhAdapter();

        IntegrationContext ctx = new IntegrationContext();
        ctx.attemptNumber = 2; // Second+ attempt → adapter should return success
        ctx.payload = new Map<String, Object>{
            'recordId' => '001YYYYYYYYYYYY',
            'event'    => 'INSERT'
        };

        // Act – run adapter logic after retry threshold
        IntegrationResult result = adapter.send(ctx);

        // Assert – validate successful classification on later attempts
        System.assertEquals(true, result.isSuccess,
            'Attempt > 0 should be success'
        );
        System.assertEquals(false, result.isTemporaryError,
            'Success should not be marked as temporary'
        );
        System.assertEquals(null, result.statusCode,
            'Success result does not set statusCode'
        );
        System.assert(result.rawResponse.contains('success on attempt 2'),
            'Raw response should mention the attempt number'
        );
    }
}
