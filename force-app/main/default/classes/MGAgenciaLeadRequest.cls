/**
 * @description Inbound request DTO for the MGAgencia Lead endpoint. Property names mirror the
 *              snake_case JSON contract (docs/API_SPEC.md §3). Unknown JSON properties are
 *              ignored by deserialization (JSON.deserialize is non-strict), which keeps the
 *              contract forward-compatible with fields not implemented yet (campaign_code —
 *              PENDING BUSINESS DECISION).
 */
public with sharing class MGAgenciaLeadRequest {
    public String first_name;
    public String last_name;
    public String phone;
    public String email;
    public String branch_code;
    public String external_lead_id;

    // Added 2026-09-03: MGAgencia UAT follow-up fields (all optional, additive, v1 — no
    // version bump per API_SPEC's non-breaking-addition policy).
    /** @description Vehicle of interest, free text (docs/API_SPEC.md §3). Max 80 chars. */
    public String interest_model;
    /** @description Contact channel preference. Must match one of 3 exact Salesforce picklist
     *              values (case-sensitive, with accents) — see MGAgenciaContactPreferenceResolver. */
    public String contact_preference;
    /** @description Financing / payment method, free text. Max 50 chars. */
    public String payment_method;
    /** @description Purchase timeline, free text. Max 50 chars. */
    public String purchase_timeline;
    /** @description Trade-in intent, free text. Max 50 chars. */
    public String trade_in;
    /** @description Whether a test drive was requested. Simple pass-through. */
    public Boolean test_drive_requested;

    /**
     * @description Parses the raw HTTP body into a request DTO.
     * @param body raw request body, may be null or blank
     * @return populated DTO (fields may be null; validation happens in MGAgenciaLeadValidator)
     * @throws MGAgenciaMalformedRequestException when the body is blank, not valid JSON,
     *         or not a top-level JSON object
     */
    public static MGAgenciaLeadRequest parse(String body) {
        if (String.isBlank(body)) {
            throw new MGAgenciaMalformedRequestException('Request body is empty.');
        }
        try {
            Object raw = JSON.deserializeUntyped(body);
            if (!(raw instanceof Map<String, Object>)) {
                throw new MGAgenciaMalformedRequestException('Request body is not a JSON object.');
            }
            return (MGAgenciaLeadRequest) JSON.deserialize(body, MGAgenciaLeadRequest.class);
        } catch (JSONException e) {
            throw new MGAgenciaMalformedRequestException('Request body is not valid JSON.');
        }
    }
}
