@IsTest
private class BillingAdapterTest {

    @IsTest
    static void testSend_withNullAttemptNumber() {
        // Arrange – simulate a context where the retry attempt is not initialized
        BillingAdapter adapter = new BillingAdapter();

        IntegrationContext ctx = new IntegrationContext();
        ctx.attemptNumber = null;   // Expected to default internally to attempt 0
        ctx.payload = new Map<String, Object>{
            'amount' => 100,
            'currency' => 'USD'
        };

        // Act – execute adapter logic
        IntegrationResult result = adapter.send(ctx);

        // Assert – validate default attempt handling and successful result
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.isSuccess, 'BillingAdapter should always return success');
        System.assertEquals(false, result.isTemporaryError, 'Success should not be temporary error');
        System.assert(
            result.rawResponse.contains('attempt 0'),
            'Expected rawResponse to mention attempt 0 when attemptNumber is null'
        );
    }

    @IsTest
    static void testSend_withNonNullAttemptNumber() {
        // Arrange – context explicitly provides an existing retry attempt count
        BillingAdapter adapter = new BillingAdapter();

        IntegrationContext ctx = new IntegrationContext();
        ctx.attemptNumber = 3;  // Simulate 3rd retry cycle
        ctx.payload = new Map<String, Object>{
            'amount' => 250,
            'currency' => 'EUR'
        };

        // Act – perform the outbound call simulation
        IntegrationResult result = adapter.send(ctx);

        // Assert – ensure the adapter reports success and echoes the attempt number
        System.assertEquals(true, result.isSuccess, 'BillingAdapter should always return success');
        System.assertEquals(false, result.isTemporaryError);
        System.assert(
            result.rawResponse.contains('attempt 3'),
            'Expected rawResponse to mention the correct attempt number'
        );
    }
}
