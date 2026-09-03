/**
 * @description Centralized request validation for the MGAgencia Lead endpoint. Aggregates every
 *              problem found in a single pass — it never throws and never stops at the first
 *              error (docs/API_SPEC.md §4.2). Rules implemented: required first_name,
 *              last_name, phone; email format when present; branch_code against the approved
 *              catalog when present; contact_preference against the 3-value Salesforce picklist
 *              catalog when present (added 2026-09-03).
 *
 *              Max-length policy for the 4 optional free-text fields (interest_model,
 *              payment_method, purchase_timeline, trade_in), added 2026-09-03: validate and
 *              reject with 422 INVALID_FORMAT when the trimmed value exceeds the target Lead
 *              field's max length, rather than silently truncating. Silent truncation would
 *              store a value MGAgencia never sent without telling them; a 422 keeps behavior
 *              visible and predictable (CLAUDE.md "Error responses must be predictable"), and
 *              avoids a DML STRING_TOO_LONG surfacing as an opaque 500 instead.
 */
public with sharing class MGAgenciaLeadValidator {
    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$');

    // Matches the target Lead field lengths (VehicleOfInterestOfTheWeb__c, Forma_de_Pago__c,
    // Plazo_de_Compra__c, Entrega_su_Auto__c) confirmed via `sf sobject describe -s Lead`.
    private static final Integer INTEREST_MODEL_MAX_LENGTH = 80;
    private static final Integer PAYMENT_METHOD_MAX_LENGTH = 50;
    private static final Integer PURCHASE_TIMELINE_MAX_LENGTH = 50;
    private static final Integer TRADE_IN_MAX_LENGTH = 50;

    /**
     * @description Validates the parsed request and returns every problem found.
     * @param request parsed request DTO (never null)
     * @return list of validation problems; empty when the request is valid
     */
    public static List<MGAgenciaLeadResponse.ErrorDetail> validate(MGAgenciaLeadRequest request) {
        List<MGAgenciaLeadResponse.ErrorDetail> errors = new List<MGAgenciaLeadResponse.ErrorDetail>();

        if (String.isBlank(request.first_name)) {
            errors.add(new MGAgenciaLeadResponse.ErrorDetail('first_name', 'REQUIRED', 'first_name is required.'));
        }
        if (String.isBlank(request.last_name)) {
            errors.add(new MGAgenciaLeadResponse.ErrorDetail('last_name', 'REQUIRED', 'last_name is required.'));
        }
        if (String.isBlank(request.phone)) {
            errors.add(new MGAgenciaLeadResponse.ErrorDetail('phone', 'REQUIRED', 'phone is required.'));
        }
        if (String.isNotBlank(request.email) && !EMAIL_PATTERN.matcher(request.email.trim()).matches()) {
            errors.add(new MGAgenciaLeadResponse.ErrorDetail('email', 'INVALID_FORMAT', 'email must be a valid email address.'));
        }
        if (String.isNotBlank(request.branch_code) && !MGAgenciaBranchResolver.isKnownCode(request.branch_code)) {
            errors.add(new MGAgenciaLeadResponse.ErrorDetail('branch_code', 'UNKNOWN_VALUE', 'branch_code does not match a known branch.'));
        }
        if (String.isNotBlank(request.contact_preference)
                && !MGAgenciaContactPreferenceResolver.isKnownValue(request.contact_preference)) {
            errors.add(new MGAgenciaLeadResponse.ErrorDetail('contact_preference', 'UNKNOWN_VALUE',
                'contact_preference does not match a known value.'));
        }
        addMaxLengthError(errors, 'interest_model', request.interest_model, INTEREST_MODEL_MAX_LENGTH);
        addMaxLengthError(errors, 'payment_method', request.payment_method, PAYMENT_METHOD_MAX_LENGTH);
        addMaxLengthError(errors, 'purchase_timeline', request.purchase_timeline, PURCHASE_TIMELINE_MAX_LENGTH);
        addMaxLengthError(errors, 'trade_in', request.trade_in, TRADE_IN_MAX_LENGTH);
        return errors;
    }

    /**
     * @description Adds an INVALID_FORMAT error when the trimmed value exceeds maxLength.
     * @param errors accumulator list, mutated in place
     * @param field JSON field name for the error entry
     * @param value raw field value (may be null/blank)
     * @param maxLength maximum allowed length of the trimmed value
     */
    private static void addMaxLengthError(List<MGAgenciaLeadResponse.ErrorDetail> errors,
                                          String field, String value, Integer maxLength) {
        if (String.isNotBlank(value) && value.trim().length() > maxLength) {
            errors.add(new MGAgenciaLeadResponse.ErrorDetail(field, 'INVALID_FORMAT',
                field + ' must be at most ' + maxLength + ' characters.'));
        }
    }
}
