@IsTest
private class IntegrationResultTest {

    // Verify success() populates flags and fields correctly
    @IsTest
    static void testSuccessFactory() {
        String raw = '{"status":"ok"}';

        IntegrationResult r = IntegrationResult.success(raw);

        System.assertEquals(true, r.isSuccess);
        System.assertEquals(false, r.isTemporaryError);
        System.assertEquals(raw, r.rawResponse);
        System.assertEquals(null, r.statusCode);
        System.assertEquals(null, r.message);
    }

    // Verify tempError() produces a retryable error shape
    @IsTest
    static void testTempErrorFactory() {
        Integer code = 503;
        String msg   = 'Service unavailable';

        IntegrationResult r = IntegrationResult.tempError(code, msg);

        System.assertEquals(false, r.isSuccess);
        System.assertEquals(true, r.isTemporaryError);
        System.assertEquals(code, r.statusCode);
        System.assertEquals(msg, r.message);
        System.assertEquals(null, r.rawResponse);
    }

    // Verify permanentError() produces a non-retryable error shape
    @IsTest
    static void testPermanentErrorFactory() {
        Integer code = 400;
        String msg   = 'Bad request';

        IntegrationResult r = IntegrationResult.permanentError(code, msg);

        System.assertEquals(false, r.isSuccess);
        System.assertEquals(false, r.isTemporaryError);
        System.assertEquals(code, r.statusCode);
        System.assertEquals(msg, r.message);
        System.assertEquals(null, r.rawResponse);
    }
}
