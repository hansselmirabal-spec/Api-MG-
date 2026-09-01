---
name: salesforce-apex-rest
description: "Trigger: Apex REST, Lead integration, Salesforce endpoint. Implement approved v1 REST behavior with layered Apex design."
license: Apache-2.0
metadata:
  author: "Gentle AI"
  version: "1.0"
---

## Activation Contract
Load when implementing or changing approved Apex REST behavior for the MGAgencia Lead integration.

## Hard Rules
- Read `../../../CLAUDE.md`, `../../../docs/CONTEXT.md`, and approved mapping/contract artifacts first.
- Keep REST transport separate from service, validation, resolution/mapping, DML, logging, and response serialization.
- Create duplicates and mark them under the approved rule; never reject solely as duplicates.
- Avoid SOQL/DML in loops, hardcoded IDs, credentials, URLs, and raw exception responses.

## Decision Gates
| Condition | Action |
| --- | --- |
| Discovery, mapping, and contract are approved | Implement the minimal required behavior. |
| Any field/rule is unapproved | Stop and label **PENDING BUSINESS DECISION**. |
| Resolver cannot find external code | Return documented validation/business failure without leaking internals. |

## Execution Steps
1. Parse and validate input at the REST boundary without business logic.
2. Invoke an application service that validates, resolves external values, evaluates the approved duplicate rule, creates the Lead, and records traceability.
3. Use safe, structured responses and standard HTTP statuses.
4. Apply CRUD/FLS, sharing, and governor-limit-safe query/DML patterns.
5. Add behavior-first tests and update docs for visible changes.

## Output Contract
Return `STATUS`, files changed, requirement traceability, tests run, pending decisions, and risks.

## References
- `../../../CLAUDE.md`
- `../../../docs/CONTEXT.md`
- `../../../docs/ARCHITECTURE.md`
- `../../../docs/FIELD_MAPPING.md`
