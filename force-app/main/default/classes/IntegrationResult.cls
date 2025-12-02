// IntegrationResult.cls
// Purpose:
//  - Encapsulate the result of an external integration call.
//  - Distinguish success, temporary errors (retryable) and permanent errors.
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
