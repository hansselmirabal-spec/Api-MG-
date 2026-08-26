---
name: salesforce-discovery
description: "Trigger: Salesforce discovery, Lead metadata, field mapping. Inspect org requirements before designing or implementing the integration."
license: Apache-2.0
metadata:
  author: "Gentle AI"
  version: "1.0"
---

## Activation Contract
Load before designing mappings, API fields, validation, or Apex behavior for Nebüla Lead creation.

## Hard Rules
- Read `../../../CLAUDE.md` and `../../../docs/CONTEXT.md` first.
- Treat the reference-market document as technical context only.
- Do not invent mandatory fields, mappings, identifiers, catalog values, or duplicate rules.
- Label every unresolved requirement **PENDING BUSINESS DECISION**.

## Decision Gates
| Evidence | Action |
| --- | --- |
| Lead metadata and automation inspected | Produce evidence-based field mapping inputs. |
| Required evidence missing | Stop implementation and request discovery. |
| Duplicate rule unapproved | Preserve create-and-mark direction; do not define matching logic. |

## Execution Steps
1. Inspect Lead fields, requiredness, validation rules, flows, triggers, duplicate and assignment rules, record types, dependent picklists, and relevant custom metadata.
2. Identify dealer and campaign resolution mechanisms without exposing Record IDs.
3. Separate confirmed behavior from unknowns.
4. Record field-level evidence for `docs/FIELD_MAPPING.md` and risks for `docs/DECISIONS.md`.
5. Hand only confirmed mapping inputs to contract/design work.

## Output Contract
Return `STATUS`, inspected sources, confirmed requirements, mapping candidates with evidence, constraints, and **PENDING BUSINESS DECISION** items.

## References
- `../../../CLAUDE.md`
- `../../../docs/CONTEXT.md`
