# CLAUDE.md

## Project

Nebüla → Salesforce Lead Integration

## Objective

Build a secure Salesforce REST API that allows Nebüla to send advertising Leads directly into Salesforce.

Nebüla is the API consumer. Salesforce is the system receiving and creating the Leads.

The first version will be implemented directly in Salesforce using Apex REST. No middleware or external API Gateway will be introduced unless explicitly approved later.

## Environments

- Development / testing: sandbox `condor-qas` (`adminsalesforce@condor.com.py.qas`). Default target org.
- Production: `mi-org` (`adminsalesforce@condor.com.py`). Never deploy or write here without explicit confirmation.

---

# Core principles

1. Do not expose Salesforce administrative access to Nebüla.
2. Do not expose Salesforce internal Record IDs unless there is a confirmed functional requirement.
3. Do not invent business rules, field mappings, identifiers or catalog values.
4. Any unresolved business decision must be marked as: **PENDING BUSINESS DECISION**
5. Prefer configuration over hardcoded values.
6. Keep REST transport logic separate from business logic.
7. All external requests must have traceability.
8. Error responses must be predictable and documented.
9. Salesforce governor limits must always be considered.
10. Every implementation must include automated tests.

---

# Integration direction

Nebüla → HTTPS REST API → Salesforce → Validation → Mapping → Lead creation → Integration logging → API response

---

# Current confirmed requirements

- Nebüla will connect to our Salesforce API and send Leads.
- The Salesforce implementation will use Apex REST.
- The API will create records in the Salesforce Lead object.
- Dealer / Concessionaire identifiers already exist in Salesforce.
- If a duplicated Lead is received, it must still be created. The newly created record must be marked as duplicated according to a rule that will be defined during implementation.
- The API must clearly inform Nebüla whether the operation succeeded or failed.
- The API should return an integration identifier instead of exposing Salesforce internal identifiers unless explicitly required.

---

# Pending external decisions

The following items must not be invented.

## Nebüla Lead Identifier
Confirm whether Nebüla can send a unique identifier for every Lead. Preferred field name: `external_lead_id`.
Status: PENDING BUSINESS DECISION

## Campaign identification
Confirm how Nebüla identifies advertising campaigns. Preferred approach: Nebüla sends an external campaign code; Salesforce resolves that code internally. Nebüla should not be required to know Salesforce Campaign Record IDs.
Status: PENDING BUSINESS DECISION

## Lead status query
Confirm whether Nebüla only needs confirmation when a Lead is created or whether it must later query the Lead status.
Status: PENDING BUSINESS DECISION
Do not implement a GET status endpoint until this requirement is confirmed.

---

# Lead fields

Do not assume that fields from reference implementations in other markets apply to this Salesforce organization.

The actual mandatory fields must be determined by inspecting:

- Lead object fields
- required fields
- validation rules
- flows
- Apex triggers
- duplicate rules
- assignment rules
- record types
- dependent picklists
- custom metadata involved in Lead creation

Produce a field mapping document before implementing the REST API.

---

# Target architecture

Use a layered architecture.

## REST Layer
Responsible only for: receiving HTTP requests, parsing input, invoking the application service, setting HTTP response codes, serializing the response. Do not place business logic here.

## Application Service
Responsible for: orchestration, validation, duplicate evaluation, mappings, Lead creation, integration logging, response generation.

## Validation
Centralize request validation. Validation should return all relevant validation problems whenever technically reasonable rather than failing silently. Never rely exclusively on Salesforce DML exceptions for API validation.

## Mapping
External values must be translated internally when required (external campaign code → Salesforce Campaign, dealer code → Salesforce Dealer representation). Avoid hardcoding these mappings inside Apex classes. Prefer External ID fields, Custom Metadata or Custom Settings depending on the use case.

---

# Duplicate handling

Duplicates must NOT automatically be rejected. Current business direction: create the Lead and mark it as duplicate. The exact duplicate detection rules remain pending.

Potential signals may include: external lead identifier, phone, email, campaign, combination of fields.

Do not establish the final duplicate algorithm without explicit approval.

---

# API behavior

The API must return structured JSON responses including at minimum: code, status, message, integration identifier when available.

Do not expose implementation details, stack traces or Salesforce exception messages to external consumers.

---

# HTTP response strategy

Use standard HTTP semantics. Recommended baseline:

- 201 Lead successfully created.
- 400 Malformed or invalid request.
- 401 Authentication failure.
- 403 Authenticated but unauthorized.
- 422 Business validation failure.
- 500 Unexpected Salesforce processing error.

Additional codes may be introduced only when justified.

---

# Logging

Every request must be traceable. Record enough information to determine: when the request was received, origin, external identifier, processing result, Salesforce Lead created, validation problems, unexpected errors, API response, processing duration when practical.

Never store credentials, access tokens or secrets in logs. Avoid storing unnecessary personal information.

---

# Security

Apply least privilege. The integration user must only have the permissions required for this integration.

Review: API Enabled, Apex class access, Lead create/read permissions, field-level security, Dealer lookup access, Campaign lookup access, integration log permissions.

No System Administrator profile should be required. Authentication architecture must be documented before production deployment.

---

# Salesforce development standards

Use Salesforce DX project structure. Use meaningful Apex class names.

Prefer: REST controller → service → validators / resolvers → DML

Avoid: business logic inside REST controllers, SOQL inside loops, DML inside loops, hardcoded Salesforce IDs, hardcoded credentials, hardcoded environment URLs, swallowing exceptions, returning raw exception messages.

All queries and DML must be designed with governor limits in mind.

---

# Apex tests

Every production Apex component must have tests. Testing must include at least:

- successful Lead creation
- missing mandatory field
- invalid payload
- invalid dealer
- invalid campaign when applicable
- duplicate Lead
- malformed JSON
- Salesforce DML failure
- authentication / permission-related considerations where testable
- response structure
- correct HTTP status

Tests must verify behavior, not merely code coverage.

---

# Documentation

Maintain:

- docs/CONTEXT.md (business context and reference-document summary)
- docs/API_SPEC.md
- docs/FIELD_MAPPING.md
- docs/ARCHITECTURE.md
- docs/DECISIONS.md
- docs/TEST_PLAN.md

The API specification must be understandable by Nebüla without access to Salesforce implementation details.

---

# Decision log

Important architectural or business decisions must be recorded in docs/DECISIONS.md. For every decision document: date, decision, reason, alternatives considered, impact.

---

# Reference documentation

The provided Nebüla / Orbi API document ("Orbi Leads API Documentation v1.0") comes from another market. Use it only as a technical reference.

Do NOT assume its fields, IDs, mandatory attributes, URLs, authentication credentials, campaign codes or vehicle identifiers apply to this project.

---

# Workflow for Claude Code

Before implementing a feature:

1. Read CLAUDE.md.
2. Inspect existing project code and metadata.
3. Review relevant documentation under /docs.
4. Identify unresolved decisions.
5. Do not guess unresolved business requirements.
6. Present the proposed change.
7. Implement only after requirements are sufficiently defined.
8. Add tests.
9. Run available validation/tests.
10. Update documentation when behavior changes.

---

# Implementation phases

1. Salesforce discovery.
2. Field mapping.
3. API contract.
4. Salesforce metadata.
5. Apex implementation.
6. Automated tests.
7. Sandbox integration testing.
8. Nebüla UAT.
9. Production deployment.

Do not skip directly to Apex development before completing Salesforce discovery and API contract definition.
