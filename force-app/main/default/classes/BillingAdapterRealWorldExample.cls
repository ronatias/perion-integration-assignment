// Purpose (REAL-LIFE TEMPLATE):
//  - Show how a real Billing integration adapter could look.
//  - Uses an HTTP callout to a Billing system via Named Credential.
//  - Demonstrates classification of:
//      * Success
//      * Temporary errors  (retryable)
//      * Permanent errors  (non-retryable)
//  - This class is NOT wired to any config yet; it's a reference for real-time usage (for assigment solution).
//    To activate it - set Integration_System_Config__c.HandlerClass__c
//    to 'BillingAdapterRealWorldExample' for the BILLING system.
//
// Assumptions:
//  - Named Credential 'Billing_API' is defined in the org.
//    Example endpoint: callout:Billing_API/invoices
//  - Outbound payload is ctx.payload (Map<String,Object>) built by IntegrationJobWorker.
//  - Billing API returns JSON with fields like:
//      status: 'OK' | 'ERROR'
//      errorType: 'BUSINESS' | 'SYSTEM'
//      errorCode: '...'
//      message: '...'
//

public with sharing class BillingAdapterRealWorldExample implements IIntegrationAdapter {

    // Constants to avoid string literals everywhere
    private static final String NAMED_CREDENTIAL = 'callout:Billing_API';
    private static final String INVOICE_ENDPOINT = '/invoices'; // e.g. POST /invoices

    public IntegrationResult send(IntegrationContext ctx) {
        // Log the payload for traceability (remove or mask sensitive fields in prod!)
        System.debug('=== BillingAdapterRealWorldExample – START ===');
        System.debug('System = ' + ctx.systemConfig.DeveloperName__c);
        System.debug('Object = ' + ctx.objectConfig.SObjectName__c +
                     ', Trigger = ' + ctx.objectConfig.TriggerReason__c);
        System.debug('Outbound payload: ' + JSON.serializePretty(ctx.payload));

        try {
            HttpRequest req = buildRequest(ctx);
            Http http = new Http();
            HttpResponse res = http.send(req);

            return handleResponse(res);

        } catch (CalloutException callEx) {
            // Network/timeout/transient issues → treat as temporary
            System.debug('BillingAdapterRealWorldExample – CalloutException: ' + callEx.getMessage());
            return IntegrationResult.tempError(null,
                'Billing callout failed (network/timeout): ' + callEx.getMessage()
            );

        } catch (Exception ex) {
            // Anything else unexpected → treat as permanent (code bug, contract mismatch, etc.)
            System.debug('BillingAdapterRealWorldExample – Unexpected Exception: ' + ex);
            return IntegrationResult.permanentError(null,
                'Billing adapter error (unexpected): ' + ex.getMessage()
            );
        }
    }

    //
    // Build HTTP request from IntegrationContext
    //
    private HttpRequest buildRequest(IntegrationContext ctx) {
        HttpRequest req = new HttpRequest();

        // Target URL: Named Credential + path.
        // Example: 'callout:Billing_API/invoices'
        String endpoint = NAMED_CREDENTIAL + INVOICE_ENDPOINT;
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setTimeout(15000); // now 15s, adjust according to SLA

        // Standard headers for JSON API
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');

        // Body: serialize the prepared payload map.
        // ctx.payload already respects Integration_Field_Map_Config__c mappings.
        String bodyJson = JSON.serialize(ctx.payload);
        req.setBody(bodyJson);

        System.debug('BillingAdapterRealWorldExample – Request endpoint=' + endpoint);
        System.debug('BillingAdapterRealWorldExample – Request body=' + bodyJson);

        return req;
    }

    // Translate HttpResponse into IntegrationResult (success/temp/permanent)
    private IntegrationResult handleResponse(HttpResponse res) {
        Integer statusCode = res.getStatusCode();
        String body        = res.getBody();

        System.debug('BillingAdapterRealWorldExample – Response status=' + statusCode);
        System.debug('BillingAdapterRealWorldExample – Response body=' + body);

        // 1) Happy path: 2xx
        if (statusCode >= 200 && statusCode < 300) {
            // Optionally parse the body to extract invoiceId, etc.
            // Map<String, Object> json = (Map<String, Object>) JSON.deserializeUntyped(body);
            // Object invoiceId = json.get('invoiceId');
            return IntegrationResult.success(body);
        }

        // 2) Parse error body (if JSON) to inspect errorType / errorCode
        String errorType;
        String errorCode;
        String errorMessage;

        try {
            Map<String, Object> json = (Map<String, Object>) JSON.deserializeUntyped(body);
            errorType    = (String) json.get('errorType');
            errorCode    = (String) json.get('errorCode');
            errorMessage = (String) json.get('message');
        } catch (Exception parseEx) {
            // Not JSON or unexpected shape – fallback to raw body
            errorMessage = 'Billing error, raw body: ' + body;
        }

        // 3) HTTP-based classification

        // TEMPORARY: 408 Request Timeout, 429 Too Many Requests, 5xx server errors
        if (statusCode == 408 ||
            statusCode == 429 ||
            (statusCode >= 500 && statusCode < 600)) {

            String msg = 'Billing temporary error (HTTP ' + statusCode + ')';
            if (!String.isBlank(errorMessage)) msg += ' - ' + errorMessage;
            return IntegrationResult.tempError(statusCode, msg);
        }

        // 4xx: usually permanent, but we may refine by errorType
        // Examples:
        //  - 400 / 422 → business validation (amount too large, invalid VAT)
        //  - 401 / 403 → misconfiguration of auth/permissions
        //  - 404       → endpoint/tenant misconfig
        if (statusCode >= 400 && statusCode < 500) {
            // If the API distinguishes BUSINESS vs SYSTEM errors, we can treat SYSTEM as temp.
            if ('SYSTEM'.equalsIgnoreCase(errorType)) {
                // e.g. downstream dependency in Billing system
                String msg = 'Billing system error (HTTP ' + statusCode + ')';
                if (!String.isBlank(errorMessage)) msg += ' - ' + errorMessage;
                return IntegrationResult.tempError(statusCode, msg);
            }

            // Default: permanent business error
            String msg = 'Billing business/validation error (HTTP ' + statusCode + ')';
            if (!String.isBlank(errorCode))    msg += ' [' + errorCode + ']';
            if (!String.isBlank(errorMessage)) msg += ' - ' + errorMessage;
            return IntegrationResult.permanentError(statusCode, msg);
        }

        // Fallback: treat everything else as permanent
        String generic = 'Billing error (HTTP ' + statusCode + ')';
        if (!String.isBlank(errorMessage)) generic += ' - ' + errorMessage;
        return IntegrationResult.permanentError(statusCode, generic);
    }
}
