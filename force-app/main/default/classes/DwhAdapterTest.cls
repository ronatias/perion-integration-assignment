@IsTest
private class DwhAdapterTest {

    @IsTest
    static void testSend_firstAttempt_tempFailure() {
        // Arrange
        DwhAdapter adapter = new DwhAdapter();

        IntegrationContext ctx = new IntegrationContext();
        ctx.attemptNumber = 0; // first attempt
        ctx.payload = new Map<String, Object>{
            'recordId' => '001XXXXXXXXXXXX',
            'event'    => 'UPDATE'
        };

        // Act
        IntegrationResult result = adapter.send(ctx);

        // Assert
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
        // Arrange
        DwhAdapter adapter = new DwhAdapter();

        IntegrationContext ctx = new IntegrationContext();
        ctx.attemptNumber = 2; // second+ attempt
        ctx.payload = new Map<String, Object>{
            'recordId' => '001YYYYYYYYYYYY',
            'event'    => 'INSERT'
        };

        // Act
        IntegrationResult result = adapter.send(ctx);

        // Assert
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
