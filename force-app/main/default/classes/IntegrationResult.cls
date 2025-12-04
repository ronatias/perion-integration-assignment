// PURPOSE:
// ----------
//  - A lightweight DTO (Data Transfer Object) that standardizes how adapters
//    communicate the outcome of an outbound integration call back to the
//    IntegrationJobWorker.
//
//  - The worker does NOT inspect exceptions directly. It only interprets this
//    result object.
//    This creates a clean separation between:
//       * adapter implementation details (callout code, mapping, protocol)
//       * framework-level retry / failure handling
//
//  - This object allows the Worker to:
//       * identify whether the call succeeded
//       * distinguish retryable errors (temporary) from permanent failures
//       * store the raw response or the error message back on Integration_Job__c

public class IntegrationResult {
    public Boolean isSuccess;
    public Boolean isTemporaryError;
    public Integer statusCode;
    public String message;
    public String rawResponse;

    public static IntegrationResult success(String rawResponse) {
        IntegrationResult r = new IntegrationResult();
        r.isSuccess = true;
        r.isTemporaryError = false;
        r.rawResponse = rawResponse;
        return r;
    }

    public static IntegrationResult tempError(Integer statusCode, String message) {
        IntegrationResult r = new IntegrationResult();
        r.isSuccess = false;
        r.isTemporaryError = true;
        r.statusCode = statusCode;
        r.message = message;
        return r;
    }

    public static IntegrationResult permanentError(Integer statusCode, String message) {
        IntegrationResult r = new IntegrationResult();
        r.isSuccess = false;
        r.isTemporaryError = false;
        r.statusCode = statusCode;
        r.message = message;
        return r;
    }
}
