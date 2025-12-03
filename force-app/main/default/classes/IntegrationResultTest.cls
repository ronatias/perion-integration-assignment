@IsTest
private class IntegrationResultTest {

    @IsTest
    static void testSuccessFactory() {
        String raw = '{"status":"ok"}';

        IntegrationResult r = IntegrationResult.success(raw);

        System.assertEquals(true, r.isSuccess, 'Success result should be successful');
        System.assertEquals(false, r.isTemporaryError, 'Success should not be temporary error');
        System.assertEquals(raw, r.rawResponse, 'Raw response should be set from input');
        System.assertEquals(null, r.statusCode, 'Status code should remain null on success');
        System.assertEquals(null, r.message, 'Message should remain null on success');
    }

    @IsTest
    static void testTempErrorFactory() {
        Integer code = 503;
        String msg   = 'Service unavailable';

        IntegrationResult r = IntegrationResult.tempError(code, msg);

        System.assertEquals(false, r.isSuccess, 'Temp error is not success');
        System.assertEquals(true, r.isTemporaryError, 'Temp error must be marked as temporary');
        System.assertEquals(code, r.statusCode, 'Status code should be set');
        System.assertEquals(msg, r.message, 'Message should be set');
        System.assertEquals(null, r.rawResponse, 'Raw response should be null unless explicitly set');
    }

    @IsTest
    static void testPermanentErrorFactory() {
        Integer code = 400;
        String msg   = 'Bad request';

        IntegrationResult r = IntegrationResult.permanentError(code, msg);

        System.assertEquals(false, r.isSuccess, 'Permanent error is not success');
        System.assertEquals(false, r.isTemporaryError, 'Permanent error must NOT be temporary');
        System.assertEquals(code, r.statusCode, 'Status code should be set');
        System.assertEquals(msg, r.message, 'Message should be set');
        System.assertEquals(null, r.rawResponse, 'Raw response should be null unless explicitly set');
    }
}
