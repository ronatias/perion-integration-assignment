@IsTest
private class BillingAdapterTest {

    @IsTest
    static void testSend_withNullAttemptNumber() {
        // Arrange
        BillingAdapter adapter = new BillingAdapter();

        IntegrationContext ctx = new IntegrationContext();
        ctx.attemptNumber = null;
        ctx.payload = new Map<String, Object>{
            'amount' => 100,
            'currency' => 'USD'
        };

        // Act
        IntegrationResult result = adapter.send(ctx);

        // Assert
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.isSuccess, 'BillingAdapter should always return success');
        System.assertEquals(false, result.isTemporaryError, 'Success should not be temporary error');
        System.assert(result.rawResponse.contains('attempt 0'),
            'Expected rawResponse to mention attempt 0 when attemptNumber is null'
        );
    }

    @IsTest
    static void testSend_withNonNullAttemptNumber() {
        // Arrange
        BillingAdapter adapter = new BillingAdapter();

        IntegrationContext ctx = new IntegrationContext();
        ctx.attemptNumber = 3;
        ctx.payload = new Map<String, Object>{
            'amount' => 250,
            'currency' => 'EUR'
        };

        // Act
        IntegrationResult result = adapter.send(ctx);

        // Assert
        System.assertEquals(true, result.isSuccess, 'BillingAdapter should always return success');
        System.assertEquals(false, result.isTemporaryError);
        System.assert(result.rawResponse.contains('attempt 3'),
            'Expected rawResponse to mention the correct attempt number'
        );
    }
}
