---
name: integration-test-review
description: "Trigger: Apex tests, integration test review, REST behavior. Verify behavior-first coverage for Nebüla Salesforce v1."
license: Apache-2.0
metadata:
  author: "Gentle AI"
  version: "1.0"
---

## Activation Contract
Load when reviewing or adding automated tests for the Apex REST Lead integration.

## Hard Rules
- Read `../../../CLAUDE.md` and `../../../docs/CONTEXT.md` first.
- Test observable behavior and contract outcomes, not coverage percentage alone.
- Do not encode unapproved mappings, fields, or duplicate criteria; label them **PENDING BUSINESS DECISION**.
- Use isolated, deterministic test data and avoid production mutation.

## Decision Gates
| Scenario | Required assertion |
| --- | --- |
| Successful submission | Lead outcome, integration identifier, response schema, and 201. |
| Invalid/malformed input or resolver failure | Safe validation response and documented 400/422 behavior. |
| Duplicate or DML failure | Create-and-mark approved duplicate behavior; safe failure without raw exception leakage. |

## Execution Steps
1. Trace tests to confirmed contract and discovery evidence.
2. Cover happy path, missing/invalid values, malformed JSON, dealer/campaign resolver failures, duplicates, DML failures, and response schema/status.
3. Assess authentication/permission considerations where testable.
4. Evaluate bulk/governor-limit concerns when queries or DML can scale.
5. Run available tests and report behavioral gaps.

## Output Contract
Return `STATUS`, scenarios covered, results, missing behaviors, pending decisions, and regression risks.

## References
- `../../../CLAUDE.md`
- `../../../docs/CONTEXT.md`
- `../../../docs/TEST_PLAN.md`
- `../../../docs/API_SPEC.md`
