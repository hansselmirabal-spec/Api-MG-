# Business context

## Goal

Nebüla collects Leads from advertising platforms and needs to insert them directly into our Salesforce org, removing manual processes.

Target flow:

Advertising platforms → Nebüla → Salesforce REST API → Validation → Lead creation → Response to Nebüla

## Reference document: Orbi Leads API Documentation v1.0

Provided by Nebüla. Describes the API of another market. Technical reference only — nothing in it is assumed to apply here.

- Transport: HTTP POST JSON, Bearer Token authentication.
- Flow: external system → POST → validation → Lead creation → response with unique identifier (UUID). The UUID must be stored by the consumer to query Lead status later.
- Fields (all mandatory in that market): `campaign_id`, `name`, `phone`, `email`, `document_number`, `concessionaire_id`, `years`, `brands`, `models`, `versions`.
- Numeric catalog IDs (`campaign_id`, `concessionaire_id`, `years`, `brands`, `models`, `versions`) are provided by Nebüla and must never be invented.
- Success response: `code`, `status`, `message`, echoed payload, `uuid`.
- Errors: 200 created; 422 mandatory field missing/empty/null (fails on first missing field); 400 internal processing error.

## How our implementation differs (by design)

- Mandatory fields come from our own Lead object requirements, not from the reference.
- External codes / External IDs instead of Salesforce Record IDs; mapping resolved inside Salesforce.
- Standard HTTP semantics (201 / 400 / 401 / 403 / 422 / 500).
- Validation returns all problems, not only the first.
- Response returns an integration identifier, not a Salesforce Record ID.

## Confirmed decisions

1. Nebüla consumes our API and sends the Leads.
2. Implementation directly in Salesforce with Apex REST, no middleware in v1.
3. Mandatory fields defined by the real Lead creation requirements of our org.
4. A Dealer / Concessionaire identifier already exists in Salesforce.
5. Duplicate Leads are still created and marked as duplicate; the detection rule is PENDING BUSINESS DECISION.

## Pending business decisions

See CLAUDE.md: Nebüla Lead identifier, campaign identification, Lead status query.
