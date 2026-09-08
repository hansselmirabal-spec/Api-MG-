# MGAgencia → Salesforce Leads API — Functional Specification v1.0

**Date:** 2026-09-07
**Prepared by:** Grupo Cóndor

**What's new (2026-09-07):** Production go-live. The production base URL and
token endpoint are now confirmed (§2, §3). Credentials (`client_id` /
`client_secret`) are pending delivery through our secure channel — see §3.

**What's new (2026-09-03):** 6 optional request fields were added, surfaced by MGAgencia's UAT: `interest_model`, `contact_preference`, `payment_method`, `purchase_timeline`, `trade_in`, and `test_drive_requested`. These are non-breaking additions within v1 (§1) — no changes required for existing integrations.

---

## 1. Overview

**Purpose.** MGAgencia collects advertising leads from marketing platforms and sends them to Grupo Cóndor's CRM (Salesforce) so they can be worked by our sales team, without manual data entry.

**Flow**

```
MGAgencia  --HTTPS POST-->  Salesforce API
                              |
                              v
                        Field validation
                              |
                              v
                        Lead creation (+ duplicate flag if applicable)
                              |
                              v
                        JSON response  -->  MGAgencia
```

**Versioning policy.** The current contract is **v1**. Any breaking change (removed/renamed fields, changed status codes, changed semantics) will be released as a new version (e.g. `v2`) with its own endpoint path. Non-breaking additions (new optional fields, new catalog values) may be introduced within v1.

---

## 2. Environments

| Environment | Base URL | Notes |
|---|---|---|
| Sandbox (UAT) | `https://condorsaci--qas.sandbox.my.salesforce.com` | For integration testing. Kept available after go-live. |
| Production | `https://condorsaci.my.salesforce.com` | Live as of 2026-09-07. |
> **Important:** the token must always be requested from the org's own domain (`*.my.salesforce.com` format), never from `test.salesforce.com` or `login.salesforce.com` — those generic domains reject this authentication flow.

| Item | Value |
|---|---|
| Endpoint path | `/services/apexrest/mgagencia/v1/leads` |
| HTTP method | `POST` |
| Content-Type | `application/json; charset=UTF-8` |
| Transport | HTTPS only |

---

## 3. Authentication

**Grant type:** OAuth 2.0 **Client Credentials**.

| Environment | Token endpoint |
|---|---|
| Sandbox | `https://condorsaci--qas.sandbox.my.salesforce.com/services/oauth2/token` |
| Production | `https://condorsaci.my.salesforce.com/services/oauth2/token` |

Request parameters (`application/x-www-form-urlencoded`):

| Parameter | Value |
|---|---|
| `grant_type` | `client_credentials` |
| `client_id` | Provided by Grupo Cóndor |
| `client_secret` | Provided by Grupo Cóndor |

Credentials (`client_id` / `client_secret`) will be delivered by Grupo Cóndor through a secure channel (e.g. a password manager share). **They will never be sent by email or chat in plain text.** The production Connected App is provisioned; credential delivery is in progress.

Every API request must include the access token:

```
Authorization: Bearer <access_token>
```

**Token expiry and renewal.** Tokens expire according to the org's session policy. MGAgencia should request a new token whenever a request fails with `401 Unauthorized`, rather than caching a token indefinitely or assuming a fixed lifetime.

**Example**

```bash
# 1. Get an access token
curl -s -X POST "https://condorsaci--qas.sandbox.my.salesforce.com/services/oauth2/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=<CLIENT_ID>" \
  -d "client_secret=<CLIENT_SECRET>"

# 2. Send a lead
curl -s -X POST "https://condorsaci--qas.sandbox.my.salesforce.com/services/apexrest/mgagencia/v1/leads" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "Maria",
    "last_name": "Gonzalez",
    "phone": "0981123456",
    "email": "maria.gonzalez@example.com",
    "branch_code": "ASUNCION"
  }'
```

> The example above uses the sandbox host; swap in the production host from
> §2/§3 once you have production credentials. Credentials (`client_id` /
> `client_secret`) are **pending delivery** through our secure channel.

---

## 4. Request specification

One JSON object per request. No batch/array wrapping. Unknown properties sent by MGAgencia are ignored (not rejected).

| Field | Type | Required | Max length | Format | Description | Example |
|---|---|---|---|---|---|---|
| `first_name` | string | Yes | — | Non-empty after trimming | Lead's first name. | `"Maria"` |
| `last_name` | string | Yes | — | Non-empty after trimming | Lead's last name. | `"Gonzalez"` |
| `phone` | string | Yes | — | Paraguayan mobile number | Accepted in local (`0981123456`) or international (`595981123456`) format. Normalized server-side to a single canonical format before storage and duplicate matching. | `"0981123456"` |
| `email` | string | No | — | Standard email format | Optional contact email. | `"maria.gonzalez@example.com"` |
| `branch_code` | string | No | — | One of the catalog values below | Preferred Cóndor branch. Omitting the field is valid; an unrecognized value is rejected. | `"ASUNCION"` |
| `external_lead_id` | string | No *(see open questions)* | — | Free text | Unique identifier MGAgencia may assign to a lead. Not required today; whether it becomes required and used as an idempotency key is open — see §10. | `"neb-2026-0000123"` |
| `interest_model` | string | No | 80 characters | Free text | Vehicle of interest (brand/model/version/year), sent as-is by MGAgencia. No catalog — any text within the max length is accepted. | `"Toyota Hilux 2026"` |
| `contact_preference` | string | No | — | One of the catalog values below | Customer's preferred contact channel. | `"WhatsApp"` |
| `payment_method` | string | No | 50 characters | Free text | Payment/financing method indicated by the customer. | `"financiacion_bancaria"` |
| `purchase_timeline` | string | No | 50 characters | Free text | Purchase timeline estimated by the customer. | `"inmediatamente"` |
| `trade_in` | string | No | 50 characters | Free text | Whether the customer is trading in their current vehicle. | `"si"` |
| `test_drive_requested` | boolean | No | — | `true` / `false` | Whether the customer requested a test drive. Stored as received. | `true` |

**`branch_code` catalog**

| Value |
|---|
| `ASUNCION` |
| `CIUDAD_DEL_ESTE` |
| `CORONEL_OVIEDO` |
| `ENCARNACION` |

**`contact_preference` catalog**

| Value |
|---|
| `Correo Electrónico` |
| `WhatsApp` |
| `Teléfono` |

> Values must match exactly (case and accents included). A value outside this catalog is rejected with `422` (`UNKNOWN_VALUE`); omitting the field is valid.

### 4.1 Example request

```json
{
  "first_name": "Maria",
  "last_name": "Gonzalez",
  "phone": "0981123456",
  "email": "maria.gonzalez@example.com",
  "branch_code": "ASUNCION",
  "external_lead_id": "neb-2026-0000123",
  "interest_model": "Toyota Hilux 2026",
  "contact_preference": "WhatsApp",
  "payment_method": "financiacion_bancaria",
  "purchase_timeline": "inmediatamente",
  "trade_in": "si",
  "test_drive_requested": true
}
```

Every field in this section except `interest_model`, `payment_method`, `purchase_timeline`, and `trade_in` has no declared length limit; those four return `422` (`INVALID_FORMAT`) when a value exceeds the stated maximum, rather than silently truncating it.

---

## 5. Response specification

### 5.1 Success — `201 Created`

| Field | Type | Description |
|---|---|---|
| `code` | string | Machine-readable outcome code (`LEAD_CREATED`). |
| `status` | string | `success`. |
| `message` | string | Human-readable summary. |
| `integration_id` | string (UUID) | Reference identifier for this request. **MGAgencia must store it** for support requests. It is not a Salesforce record identifier. |
| `duplicated` | boolean | `true` if this lead matched an existing one (see §7). |

```json
{
  "code": "LEAD_CREATED",
  "status": "success",
  "message": "Lead created successfully.",
  "integration_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "duplicated": false
}
```

### 5.2 Error envelope

All error responses share this shape. When the failure is field-level, `errors[]` reports **every** problem found in a single pass, not just the first.

| Field | Type | Description |
|---|---|---|
| `code` | string | Machine-readable outcome code. |
| `status` | string | `error`. |
| `message` | string | Human-readable, safe-to-log summary. Never a raw internal error. |
| `errors` | array | Present when the failure is field-level. Each item has `field`, `code`, `message`. |

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

### 5.3 Error catalog

| HTTP status | `code` | Meaning |
|---|---|---|
| `400` | `MALFORMED_REQUEST` | Body missing, not valid JSON, or not a JSON object. No field validation is attempted. |
| `401` | *(auth error)* | Missing or invalid access token. |
| `403` | *(auth error)* | Valid token, but not authorized for this operation. |
| `422` | `VALIDATION_ERROR` with sub-code `REQUIRED` | A required field is missing or empty. |
| `422` | `VALIDATION_ERROR` with sub-code `INVALID_FORMAT` | A field does not match the expected format (e.g. `email`). |
| `422` | `VALIDATION_ERROR` with sub-code `UNKNOWN_VALUE` | A field value is not in its catalog (e.g. an unrecognized `branch_code`). |
| `500` | `INTERNAL_ERROR` | Unexpected processing failure on our side. Never includes stack traces or internal error text. |

**Example — `400` malformed JSON**

```json
{
  "code": "MALFORMED_REQUEST",
  "status": "error",
  "message": "Request body is not valid JSON."
}
```

**Example — `422` unknown branch code**

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

---

## 6. Duplicate handling

Duplicate leads are **never rejected**. If an incoming lead matches an existing one, it is still created, and the response returns `"duplicated": true`.

**Matching signals:** normalized `phone`, or `email`, or `external_lead_id` when provided.

MGAgencia does not need to take corrective action on a duplicate response — it is flagged internally for reporting. Even so, MGAgencia should avoid blindly retrying an already-successful request, since every accepted request currently creates a new lead record (see the idempotency note in §10, item 1).

---

## 7. Operational behavior

| Topic | Guidance |
|---|---|
| Timeout | Configure a reasonable client-side timeout (e.g. 30 seconds) per request. |
| Retries | Retry only on `5xx` responses, with backoff between attempts. Do **not** retry `4xx` responses — they indicate the request itself must be corrected, not resent as-is. |
| Rate limits | Not yet defined — see open question in §10. |
| Support traceability | Always log the `integration_id` returned on success. It is required to look up a request when contacting Grupo Cóndor for support. |

---

## 8. UAT plan for MGAgencia

Run the following scenarios against the sandbox environment before go-live:

| # | Scenario | Expected result |
|---|---|---|
| 1 | Valid lead with all fields | `201`, `code: LEAD_CREATED`, `duplicated: false`. |
| 2 | Duplicate lead (same phone/email/`external_lead_id` as a previous one) | `201`, `code: LEAD_CREATED`, `duplicated: true`. |
| 3 | Missing required field(s) (`first_name`, `last_name`, or `phone`) | `422`, `code: VALIDATION_ERROR`, `errors[]` lists every missing field. |
| 4 | Invalid `branch_code` (not in catalog) | `422`, `code: VALIDATION_ERROR`, `errors[].code: UNKNOWN_VALUE`. |
| 5 | Malformed JSON body | `400`, `code: MALFORMED_REQUEST`. |
| 6 | Request without a valid access token | `401`. |

---

## 9. Open questions for MGAgencia

| # | Question | Why it matters | Proposed answer |
|---|---|---|---|
| 1 | Can you send a unique `external_lead_id` per lead? | If confirmed, it becomes a **required** field and the idempotency key for safe retries (avoiding duplicate creation on resubmission). | Yes — MGAgencia assigns and sends a stable, unique `external_lead_id` per lead. |
| 2 | How do you identify advertising campaigns? | Needed to attribute leads to campaigns for reporting. | MGAgencia sends a `campaign_code` from a catalog agreed with Grupo Cóndor; we resolve it internally. |
| 3 | ~~Do you need to send the vehicle model of interest?~~ **Resolved (2026-09-03).** | — | `interest_model` was implemented as free text (max 80 characters, no catalog) — see §4. |
| 4 | Do you need to query lead status after creation, or is the creation response enough? | Determines whether a `GET` status endpoint is needed in a future phase. | The synchronous creation response (`integration_id`, `duplicated`) is sufficient for v1; no `GET` endpoint planned unless confirmed otherwise. |
| 5 | What request volume do you expect (leads/day, peak rate)? | Needed to size the endpoint and define rate limits. | Please share expected average and peak volumes. |

---

## 10. Support & change management

| Item | Detail |
|---|---|
| Contact | *[Grupo Cóndor integration contact — to be provided]* |
| Change communication | Any change to this contract (new/changed fields, status codes, or behavior) will be communicated to MGAgencia in writing before deployment. Breaking changes are released under a new API version (§1); non-breaking changes are documented as an update to this specification. |

---

*End of document.*
