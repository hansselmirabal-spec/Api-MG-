# API_SPEC — Nebüla → Lead Integration (v1 draft)

Status: **DRAFT — Phase 3**. Consumer-facing contract. This document does not
describe Salesforce implementation details, internal object names beyond the
public field names below, or Record IDs. Several fields and behaviors are
marked **PENDING BUSINESS DECISION** and must not be treated as final; see
§9 "Open questions for Nebüla".

---

## 1. Overview and versioning

Nebüla sends advertising Leads to us via a single HTTPS REST endpoint. Each
request creates one Lead. There is no batch/bulk endpoint in v1.

- **Version**: v1.
- **Endpoint**: `POST https://<salesforce-domain>/services/apexrest/nebula/v1/leads`
  (implemented Apex REST path; the sandbox/production host is shared before UAT).
- **Content type**: `application/json` for both request and response.
- **Transport**: HTTPS only.
- **Scope**: this version creates Leads only. It does not expose Lead status
  querying, updates, or deletion.

---

## 2. Authentication

**CONFIRMED (Decision 8, 2026-08-31).** Bearer token via the **OAuth 2.0
client credentials** grant, on a dedicated Connected App run-as the
least-privilege integration user. Nebüla is issued a `client_id` /
`client_secret`, exchanges them for an access token at the token endpoint,
then sends the token on every request:

```
Authorization: Bearer <access_token>
```

Admin setup (create the Connected App, enable client credentials, set the
run-as user, IP policy, secret handover) is documented in the admin runbook
`docs/AUTH_SETUP.md`. Requests without a valid token receive `401`; a valid
token without the required permission set receives `403` (both handled by
the platform before Apex runs — see §5).

Token endpoints:

- Sandbox: `https://test.salesforce.com/services/oauth2/token`
  (or `https://<MyDomain>--qas.sandbox.my.salesforce.com/services/oauth2/token`)
- Production: `https://<MyDomain>.my.salesforce.com/services/oauth2/token`

```bash
curl -s -X POST "https://<MyDomain>.my.salesforce.com/services/oauth2/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=<CONSUMER_KEY>" \
  -d "client_secret=<CONSUMER_SECRET>"
```

---

## 3. Request schema

All fields use `snake_case`. Send a single JSON object per request (no
array/batch wrapping).

| Field | Type | Required | Status | Constraints / notes |
|---|---|---|---|---|
| `external_lead_id` | string | Proposed required | **PENDING BUSINESS DECISION** | Unique identifier Nebüla assigns to each Lead. Whether Nebüla can send this, and how it is used for idempotency/duplicates, is not yet confirmed. |
| `first_name` | string | Required | Confirmed | Non-empty after trimming. |
| `last_name` | string | Required | Confirmed | Non-empty after trimming. |
| `phone` | string | Required | Confirmed | Paraguayan mobile number. Expected format `595` + 9 digits (e.g. `595981234567`). Other formats may be normalized or rejected — final normalization behavior is an implementation detail, not part of this contract. |
| `email` | string | Optional | Confirmed | Standard email format when present. |
| `campaign_code` | string | Unresolved | **PENDING BUSINESS DECISION** | How Nebüla identifies advertising campaigns is not yet defined. Candidate: an external code that Salesforce resolves internally. Do not treat as available until confirmed. |
| `branch_code` | string | Optional | Confirmed | Cóndor branch preferred by the customer. Approved catalog: `ASUNCION`, `CIUDAD_DEL_ESTE`, `CORONEL_OVIEDO`, `ENCARNACION`. An unknown value is rejected with 422 (`UNKNOWN_VALUE`); omitting the field is valid. |
| `interest_model` | string | Unresolved | **PENDING BUSINESS DECISION** | Vehicle of interest (brand/model/version/year). The catalog of accepted values will be provided by us once confirmed; Nebüla must not send free-form values ahead of that catalog. |

### 3.1 Example request

```json
{
  "external_lead_id": "neb-2026-0000123",
  "first_name": "Maria",
  "last_name": "Gonzalez",
  "phone": "595981234567",
  "email": "maria.gonzalez@example.com",
  "campaign_code": "TBD",
  "branch_code": "ASUNCION",
  "interest_model": "TBD"
}
```

Fields marked PENDING BUSINESS DECISION are shown for shape illustration
only; they are not guaranteed to be accepted, required, or validated in
their final form until confirmed.

---

## 4. Response schema

Every response — success or error — returns a JSON object with at least:

| Field | Type | Present on | Description |
|---|---|---|---|
| `code` | string | always | Machine-readable outcome code (e.g. `LEAD_CREATED`, `VALIDATION_ERROR`). |
| `status` | string | always | `success` or `error`. |
| `message` | string | always | Human-readable summary, safe to log/display. Never a raw system error. |
| `integration_id` | string (UUID) | success only | Identifier to reference this request in future correspondence. Not a Salesforce Record ID. |
| `duplicated` | boolean | success only | `true` if this Lead matched an existing one and was created and flagged as a duplicate (see §7). |
| `errors` | array | error only | All validation problems found, not just the first (see §4.2). |

### 4.1 Success example — `201`

```json
{
  "code": "LEAD_CREATED",
  "status": "success",
  "message": "Lead created successfully.",
  "integration_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "duplicated": false
}
```

### 4.2 Error envelope

```json
{
  "code": "VALIDATION_ERROR",
  "status": "error",
  "message": "One or more fields failed validation.",
  "errors": [
    { "field": "phone", "code": "REQUIRED", "message": "phone is required." },
    { "field": "email", "code": "INVALID_FORMAT", "message": "email must be a valid email address." }
  ]
}
```

`errors[]` always reports every problem found in a single pass — the API
does not fail on the first invalid field.

---

## 5. Status codes

| Code | Meaning | Condition |
|---|---|---|
| `201` | Created | Lead was created, including when created and flagged as duplicate. |
| `400` | Bad request | Body is missing, not valid JSON, or not a JSON object. No business validation is attempted. |
| `401` | Unauthorized | Missing or invalid authentication credentials. |
| `403` | Forbidden | Credentials are valid but not authorized for this operation. |
| `422` | Business validation failure | Body is valid JSON but fails field-level or business rules (missing required field, invalid format, unknown campaign/branch code once those catalogs exist). |
| `500` | Internal error | Unexpected processing failure on our side. Response never includes stack traces or raw system error text. |

### 5.1 `400` — malformed JSON

```json
{
  "code": "MALFORMED_REQUEST",
  "status": "error",
  "message": "Request body is not valid JSON."
}
```

### 5.2 `422` — validation failure (missing required field)

```json
{
  "code": "VALIDATION_ERROR",
  "status": "error",
  "message": "One or more fields failed validation.",
  "errors": [
    { "field": "last_name", "code": "REQUIRED", "message": "last_name is required." },
    { "field": "phone", "code": "REQUIRED", "message": "phone is required." }
  ]
}
```

### 5.3 `422` — unknown campaign or branch code

```json
{
  "code": "VALIDATION_ERROR",
  "status": "error",
  "message": "One or more fields failed validation.",
  "errors": [
    { "field": "branch_code", "code": "UNKNOWN_VALUE", "message": "branch_code does not match a known branch." }
  ]
}
```

This behavior depends on the `campaign_code` catalog, still
**PENDING BUSINESS DECISION** (§9). Shown for shape illustration only.

---

## 6. Duplicate behavior

Duplicate Leads are **never rejected**. If an incoming Lead matches an
existing, non-lost Lead (current rule: matching phone or email — see
`docs/DECISIONS.md`), the Lead is still created and the response sets
`"duplicated": true`. Nebüla does not need to take any corrective action;
the duplicate is flagged internally for reporting.

```json
{
  "code": "LEAD_CREATED",
  "status": "success",
  "message": "Lead created successfully.",
  "integration_id": "9c858901-8a57-4791-81fe-4c455b099bc9",
  "duplicated": true
}
```

---

## 7. Idempotency

**PENDING BUSINESS DECISION**, tied to `external_lead_id` (§3, §9). If
Nebüla is confirmed able to send a stable `external_lead_id` per Lead, that
value is the intended key for future idempotent-retry behavior (e.g. safely
resubmitting after a timeout without creating a second Lead). Until
`external_lead_id` is confirmed, every accepted request creates a new Lead —
retries are not deduplicated.

---

## 8. Rate and volume expectations

**PENDING.** Expected request volume and rate limits from Nebüla have not
been provided. No throttling behavior is documented yet; this section will
be completed once Nebüla shares expected peak/average send rates.

---

## 9. Open questions for Nebüla

1. Can you send a unique identifier per Lead (`external_lead_id`)? If so,
   what are its format and uniqueness guarantees?
2. How do you identify advertising campaigns? Can you send an external
   campaign code we resolve internally, rather than a Salesforce identifier?
3. How do you identify the target branch/dealer for a Lead? Do you need a
   catalog of values from us first?
4. What is the catalog of vehicle values (`interest_model`: brand, model,
   version, year) you intend to send? We will provide the accepted value
   list once this is confirmed.
5. Do you need to query a Lead's status after creation, or is the synchronous
   creation response sufficient? (Determines whether a GET endpoint is built
   in a future phase.)
6. What request volume/rate do you expect (peak and average), so we can size
   the endpoint and document limits?
