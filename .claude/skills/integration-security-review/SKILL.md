---
name: integration-security-review
description: "Trigger: Salesforce security review, OAuth, permissions, PII logging. Review integration access and data exposure controls."
license: Apache-2.0
metadata:
  author: "Gentle AI"
  version: "1.0"
---

## Activation Contract
Load for authentication, integration-user permissions, logging, error handling, or production-readiness review.

## Hard Rules
- Read `../../../CLAUDE.md` and `../../../docs/CONTEXT.md` first.
- Define and document an approved authentication architecture before production; prefer standards-based token authentication with a dedicated least-privilege integration identity, and mark the selection **PENDING BUSINESS DECISION** until explicitly approved.
- Review CRUD, FLS, sharing, Apex access, API Enabled, and resolver/log object access.
- Keep tokens, credentials, secrets, raw exceptions, Salesforce IDs, and unnecessary PII out of logs and responses.

## Decision Gates
| Review result | Action |
| --- | --- |
| Authentication architecture undocumented | Mark **PENDING BUSINESS DECISION** and block production readiness. |
| Excess privilege or leakage found | Require remediation before approval. |
| Sandbox activity | Allow as default; production requires explicit confirmation. |

## Execution Steps
1. Trace request authentication, authorization, data access, and response paths.
2. Inspect permission dependencies for Lead creation, dealer/campaign resolution, and integration logging.
3. Verify safe failure messages and redacted traceability.
4. Check production safeguards and deployment prerequisites.
5. Report evidence-backed findings with remediation priority.

## Output Contract
Return `STATUS`, scope, findings with severity/evidence, remediations, residual risk, and readiness verdict.

## References
- `../../../CLAUDE.md`
- `../../../docs/CONTEXT.md`
- `../../../docs/ARCHITECTURE.md`
