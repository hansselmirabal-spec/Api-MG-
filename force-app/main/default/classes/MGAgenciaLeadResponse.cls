/**
 * @description Outbound response DTO for the MGAgencia Lead endpoint (docs/API_SPEC.md §4).
 *              Property names mirror the snake_case JSON contract. This class is the single
 *              shape serialized back to the consumer: it never carries Salesforce Record IDs,
 *              raw exception messages, or stack traces. Null properties are suppressed at
 *              serialization time (JSON.serialize with suppressApexObjectNulls = true).
 */
public with sharing class MGAgenciaLeadResponse {
    public String code;
    public String status;
    public String message;
    public String integration_id;
    public Boolean duplicated;
    public List<ErrorDetail> errors;

    /** @description One validation problem: field, machine-readable code, safe message. */
    public class ErrorDetail {
        public String field;
        public String code;
        public String message;

        /**
         * @description Builds one validation problem entry.
         * @param field JSON field name the problem refers to
         * @param code machine-readable problem code (REQUIRED, INVALID_FORMAT, UNKNOWN_VALUE)
         * @param message human-readable, consumer-safe description
         */
        public ErrorDetail(String field, String code, String message) {
            this.field = field;
            this.code = code;
            this.message = message;
        }
    }

    /**
     * @description Success response (201). Used for both fresh and duplicate-flagged Leads.
     * @param integrationId UUID generated for this request
     * @param isDuplicated whether the Lead was flagged as duplicate
     * @return populated response DTO
     */
    public static MGAgenciaLeadResponse created(String integrationId, Boolean isDuplicated) {
        MGAgenciaLeadResponse response = new MGAgenciaLeadResponse();
        response.code = 'LEAD_CREATED';
        response.status = 'success';
        response.message = 'Lead created successfully.';
        response.integration_id = integrationId;
        response.duplicated = isDuplicated;
        return response;
    }

    /**
     * @description Validation failure response (422) carrying every problem found.
     * @param errors aggregated validation problems (never empty when called)
     * @return populated response DTO
     */
    public static MGAgenciaLeadResponse validationError(List<ErrorDetail> errors) {
        MGAgenciaLeadResponse response = new MGAgenciaLeadResponse();
        response.code = 'VALIDATION_ERROR';
        response.status = 'error';
        response.message = 'One or more fields failed validation.';
        response.errors = errors;
        return response;
    }

    /**
     * @description Malformed request response (400).
     * @return populated response DTO
     */
    public static MGAgenciaLeadResponse malformedRequest() {
        MGAgenciaLeadResponse response = new MGAgenciaLeadResponse();
        response.code = 'MALFORMED_REQUEST';
        response.status = 'error';
        response.message = 'Request body is not valid JSON.';
        return response;
    }

    /**
     * @description Generic internal error response (500). Never includes internal detail.
     * @return populated response DTO
     */
    public static MGAgenciaLeadResponse internalError() {
        MGAgenciaLeadResponse response = new MGAgenciaLeadResponse();
        response.code = 'INTERNAL_ERROR';
        response.status = 'error';
        response.message = 'An unexpected error occurred while processing the request.';
        return response;
    }
}
