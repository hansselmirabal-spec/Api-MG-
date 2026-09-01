---
name: api-contract-review
description: "Trigger: API contract, REST schema, response codes. Review MGAgencia Salesforce v1 request and response behavior."
license: Apache-2.0
metadata:
  author: "Gentle AI"
  version: "1.0"
---

## Activation Contract
Load when defining or reviewing the external v1 REST contract, API specification, payload validation, or error responses.

## Hard Rules
- Read `../../../CLAUDE.md` and `../../../docs/CONTEXT.md` first.
- Keep v1 direct Apex REST; do not introduce middleware.
- Return integration identifiers, never Salesforce internal IDs.
- Never expose raw exceptions, stack traces, credentials, or unnecessary PII.

## Decision Gates
| Contract input | Action |
| --- | --- |
| Field mapping approved | Specify only approved request fields and resolver semantics. |
| Field/mapping unknown | Mark **PENDING BUSINESS DECISION**; do not publish as required. |
| Status query unconfirmed | Do not define a GET endpoint. |

## Execution Steps
1. Verify request schema against discovery and approved mappings.
2. Specify structured JSON response fields: `code`, `status`, `message`, and integration identifier when available.
3. Apply 201, 400, 401, 403, 422, and 500 only to their documented conditions.
4. Require validation responses to return relevant problems when technically reasonable.
5. Check examples and errors for internal-ID, secret, and implementation-detail leakage.

## Output Contract
Return `STATUS`, contract findings/changes, status-code matrix, unresolved decisions, compatibility risks, and required documentation updates.

## References
- `../../../CLAUDE.md`
- `../../../docs/CONTEXT.md`
- `../../../docs/API_SPEC.md`
