# Decision log

Format: date · decision · reason · alternatives considered · impact.

## 2026-08-26 — Apex REST directly in Salesforce, no middleware

- Reason: simplest secure path for v1; avoids a new component to operate.
- Alternatives: external API Gateway / middleware (deferred, needs explicit approval).
- Impact: transport, validation, mapping and logging all live in Apex; governor limits apply.

## 2026-08-26 — Duplicate Leads are created and flagged, not rejected

- Reason: confirmed business requirement.
- Alternatives: reject duplicates with 409.
- Impact: needs a duplicate-flag field and a detection rule (PENDING BUSINESS DECISION).
