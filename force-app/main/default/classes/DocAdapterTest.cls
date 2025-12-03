@IsTest
private class DocAdapterTest {

    @IsTest
    static void testSend_firstAttempt_tempFailure() {
        // Arrange
        DocAdapter adapter = new DocAdapter();

        IntegrationContext ctx = new IntegrationContext();
        ctx.attemptNumber = 0;
        ctx.payload = new Map<String, Object>{
            'fileId' => '123',
            'name'   => 'TestDoc.pdf'
        };

        // Act
        IntegrationResult result = adapter.send(ctx);

        // Assert
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(false, result.isSuccess, 'Should not be success on attempt 0');
        System.assertEquals(true, result.isTemporaryError,
            'First attempt should return a temp error'
        );
        System.assertEquals(503, result.statusCode,
            'Expected temp error status code 503'
        );
        System.assert(result.message.contains('temporary failure'),
            'Expected temporary failure message in result'
        );
    }

    @IsTest
    static void testSend_secondAttempt_permanentFailure() {
        // Arrange
        DocAdapter adapter = new DocAdapter();

        IntegrationContext ctx = new IntegrationContext();
        ctx.attemptNumber = 2;
        ctx.payload = new Map<String, Object>{
            'fileId' => '987',
            'name'   => 'FinalDoc.pdf'
        };

        // Act
        IntegrationResult result = adapter.send(ctx);

        // Assert
        System.assertEquals(false, result.isSuccess,
            'Permanent failure should not be success'
        );
        System.assertEquals(false, result.isTemporaryError,
            'Attempt > 0 should be permanent error'
        );
        System.assertEquals(400, result.statusCode,
            'Expected permanent error status code 400'
        );
        System.assert(result.message.contains('permanent failure'),
            'Expected permanent failure message'
        );
        System.assert(result.message.contains('attempt 2'),
            'Should mention the correct attempt in the error message'
        );
    }
}
