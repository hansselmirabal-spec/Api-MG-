/**
 * @description Inbound request DTO for the Nebüla Lead endpoint. Property names mirror the
 *              snake_case JSON contract (docs/API_SPEC.md §3). Unknown JSON properties are
 *              ignored by deserialization (JSON.deserialize is non-strict), which keeps the
 *              contract forward-compatible with fields not implemented yet (campaign_code,
 *              interest_model — PENDING BUSINESS DECISION).
 */
public with sharing class NebulaLeadRequest {
    public String first_name;
    public String last_name;
    public String phone;
    public String email;
    public String branch_code;
    public String external_lead_id;

    /**
     * @description Parses the raw HTTP body into a request DTO.
     * @param body raw request body, may be null or blank
     * @return populated DTO (fields may be null; validation happens in NebulaLeadValidator)
     * @throws NebulaMalformedRequestException when the body is blank, not valid JSON,
     *         or not a top-level JSON object
     */
    public static NebulaLeadRequest parse(String body) {
        if (String.isBlank(body)) {
            throw new NebulaMalformedRequestException('Request body is empty.');
        }
        try {
            Object raw = JSON.deserializeUntyped(body);
            if (!(raw instanceof Map<String, Object>)) {
                throw new NebulaMalformedRequestException('Request body is not a JSON object.');
            }
            return (NebulaLeadRequest) JSON.deserialize(body, NebulaLeadRequest.class);
        } catch (JSONException e) {
            throw new NebulaMalformedRequestException('Request body is not valid JSON.');
        }
    }
}
