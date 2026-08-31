/**
 * @description Centralized request validation for the Nebüla Lead endpoint. Aggregates every
 *              problem found in a single pass — it never throws and never stops at the first
 *              error (docs/API_SPEC.md §4.2). Rules implemented: required first_name,
 *              last_name, phone; email format when present; branch_code against the approved
 *              catalog when present.
 */
public with sharing class NebulaLeadValidator {
    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$');

    /**
     * @description Validates the parsed request and returns every problem found.
     * @param request parsed request DTO (never null)
     * @return list of validation problems; empty when the request is valid
     */
    public static List<NebulaLeadResponse.ErrorDetail> validate(NebulaLeadRequest request) {
        List<NebulaLeadResponse.ErrorDetail> errors = new List<NebulaLeadResponse.ErrorDetail>();

        if (String.isBlank(request.first_name)) {
            errors.add(new NebulaLeadResponse.ErrorDetail('first_name', 'REQUIRED', 'first_name is required.'));
        }
        if (String.isBlank(request.last_name)) {
            errors.add(new NebulaLeadResponse.ErrorDetail('last_name', 'REQUIRED', 'last_name is required.'));
        }
        if (String.isBlank(request.phone)) {
            errors.add(new NebulaLeadResponse.ErrorDetail('phone', 'REQUIRED', 'phone is required.'));
        }
        if (String.isNotBlank(request.email) && !EMAIL_PATTERN.matcher(request.email.trim()).matches()) {
            errors.add(new NebulaLeadResponse.ErrorDetail('email', 'INVALID_FORMAT', 'email must be a valid email address.'));
        }
        if (String.isNotBlank(request.branch_code) && !NebulaBranchResolver.isKnownCode(request.branch_code)) {
            errors.add(new NebulaLeadResponse.ErrorDetail('branch_code', 'UNKNOWN_VALUE', 'branch_code does not match a known branch.'));
        }
        return errors;
    }
}
