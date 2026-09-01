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

## 2026-08-26 — Discovery findings (technical constraints, not decisions)

Source: read-only inspection of sandbox `condor-qas`. Details in `docs/FIELD_MAPPING.md`.

- FINDING: validation rule `CodigoVendedorAsignacion` blocks any insert where `Status <> 'Nuevo'` (an inactive value), `VendorCode2__c` is empty and the profile is not `Pre-calificación` / `Administrador del sistema`. A least-privilege integration user cannot create Leads today unless `VendorCode2__c` is resolved, the trigger auto-fills it (requires `ProductSeller__c` rows owned by the integration user) or the rule gets a bypass. Must be handled before Apex implementation.
- FINDING: validation rule `FirstNameRequired` requires `FirstName` for every role except `SystemAdministrator`. `FirstName` becomes mandatory in the API contract unless the rule is changed.
- FINDING: `Status` defaults to `Prospecto`, which activates `Segmento_y_o_Modelo_vacio_o_otros`; `Segmento__c` / `interest_model__c` carry defaults (`HS PHEV` / `MG RX9 LUX`) that silently store a wrong vehicle. Initial status and vehicle mapping must be decided together.
- FINDING: the only active duplicate rule (`Prospecto_Duplicado_por_Telefono`, matching `MobilePhone` AND `Email` exact, excluding `Perdido`) is Allow + Report on insert. Creation is never blocked; a dedicated duplicate flag field does not exist and must be added.
- FINDING: the active assignment rule `Reglas de Meta` explicitly excludes `Family__c = AUTOMÓVILES MG`, and the distribution flow `Asignacion_Lead_a_Vendedor` keys on `Sucursal_Seleccionada_Meta__c`, `Family__c`, `Status = Formulario Meta` and the `Reglas Meta` queue. MGAgencia leads will not be auto-assigned unless they adopt those values or a new assignment path is defined.
- FINDING: no dealer/concessionaire object exists. Branch identity lives in `Lead.Nearest_Branch__c` (picklist, 4 cities) and `Lead.Sucursal_Seleccionada_Meta__c` (text, same 4 values + `pre-calificacion`); third-party dealers only exist as `Opportunity.Dealer__c` picklist. `VendorCode__c.VendorCode__c` is the only relevant External ID and identifies sellers, not dealers.
- FINDING: `Campaign` has no external code / External ID field. The Meta flow resolves campaigns by `Name` and auto-creates them under a parent campaign.
- FINDING: several flows hard-code record IDs (queues, users, parent campaign, record type) that differ between sandbox and production. The API must resolve every reference by developer name / code, never by ID.
- FINDING: flows `DatosInicialesProspecto` and `CONTROL_CUENTA_EXISTENTE` mutate data after insert (upper-case names, phone normalisation to `595…`, `Company` cleared for `Fisica`, account linkage by CI/RUC). `MobileFormat` rejects later user edits if the phone is not `595` + 9 digits. The API should normalise phones before DML and should not echo values that automation may change.
- FINDING: Apex trigger `LeadTriggerHandler` raises `Error en el formato del RUC.` when `RUC__c` lacks the `-` check digit. RUC must be validated in the API layer or not sent.
- FINDING: `Conf_Parameters__c` (hierarchy custom setting used by the trigger for the admin role) also stores DW/SAP credentials. The MGAgencia permission set must not grant access to it.

## 2026-08-29 — Assignment via dedicated queue + distribution flow (Decision 1)

- Decision: API-created Leads are owned by a dedicated queue (`MGAgencia Leads`). A distribution flow (Meta pattern) routes them by branch / product family. The `CodigoVendedorAsignacion` validation rule is bypassed with a custom permission granted only to the integration user. MGAgencia never sends seller codes.
- Alternatives: MGAgencia sends a seller code resolved via `VendorCode__c` External ID (couples MGAgencia to seller roster); integration user owns `ProductSeller__c` rows so the trigger auto-assigns (all leads land on one seller).
- Impact: requires queue, custom permission, VR edit, distribution flow, and integration-user permission set.

## 2026-08-29 — New Status and LeadSource values (Decision 2)

- Decision: new `Lead.Status` value `Formulario MGAgencia` as the initial status of API-created Leads (distribution flow trigger; moves to the standard pipeline on assignment) and new `LeadSource` value `MGAgencia`.
- Reason: replicates the Meta pattern (`Formulario Meta`), avoiding `Prospecto`-stage validation rules and silent vehicle defaults; enables filtering and reporting.
- Impact: picklist changes on Status and LeadSource; distribution flow keys on the new status.

## 2026-08-31 — Fixed record type, family and brand (Decision 3)

- Decision: every API-created Lead uses record type `Fisica` ("Persona Física"); `Family__c` = "AUTOMÓVILES MG" and `Brand__c` = "MG" are fixed via configuration (Custom Metadata). MGAgencia sends none of these.
- Reason: advertising leads are individuals; the project scope is MG only; `Family__c` drives assignment and the dependent chain Family → Brand → Segmento → Model.
- Impact: interest model resolution (Segmento__c / interest_model__c) remains the only vehicle input expected from MGAgencia — PENDING BUSINESS DECISION (external catalog).

## 2026-08-31 — Duplicate rule and flag (Decision 4)

- Decision: a Lead is marked duplicate when an existing non-lost Lead matches on MobilePhone OR Email (more aggressive than the org duplicate rule, which requires AND). If MGAgencia provides `external_lead_id`, an identical value is a certain duplicate. Duplicates are always created, never rejected. New fields on Lead: checkbox `Duplicated_Lead__c` ("Lead Duplicado") plus a text field recording the match reason.
- Reason: advertising users resubmit forms changing one datum; business direction is create-and-mark.
- Impact: duplicate evaluator in the application service; two new Lead fields; reporting on duplicates becomes possible.

## 2026-08-31 — Phone mandatory, email optional (Decision 5)

- Decision: the API contract requires phone; email is optional.
- Reason: in Paraguay the effective contact channel is phone; advertising-form emails are frequently fabricated.
- Impact: contract validation; org flows normalize phone to `595…` format (MobileFormat VR) — normalization must happen before or during Lead creation.

## 2026-08-31 — Decision 1 amended: reuse the active assignment rule, no new flow

- Decision: routing to the `MGAgencia Leads` queue is done by adding a rule entry to the org's single active Lead assignment rule ("Reglas de Meta"): `LeadSource = 'MGAgencia'` → queue `MGAgencia Leads`. No new distribution flow in v1. Apex opts in via `Database.DMLOptions.assignmentRuleHeader`.
- Evidence: Salesforce allows only one active assignment rule per object; the active rule routes Meta leads (`LeadSource = 'Redes Sociales Empresa'`, `Status = 'Formulario Meta'`, `Family__c ≠ 'AUTOMÓVILES MG'`) to queue `Reglas_Meta`. The "Asignación de prospectos Lead Capture" flow only maps Facebook page identifiers to advisors via `Conexion_Facebook__c` and is out of scope.
- Impact: smaller metadata footprint (queue + rule entry + custom permission); advisor-level distribution from the queue is a later, optional phase.

## 2026-08-31 — No document number in the API contract (Decision 6)

- Decision: the API does not request any identity document (CI/RUC). `document_number` removed from the contract and mapping.
- Reason: leads are individuals (Persona Física) and the document is not needed to work an advertising lead; less PII collected.
- Impact: `CONTROL_CUENTA_EXISTENTE` account-linking automation (keyed on CI/RUC) will not act on API-created Leads; RUC trigger validation is never hit.

## 2026-08-31 — Optional branch_code mapped to Nearest_Branch__c (Decision 7)

- Decision: MGAgencia may optionally send `branch_code` (catalog: `ASUNCION`, `CIUDAD_DEL_ESTE`, `CORONEL_OVIEDO`, `ENCARNACION`), resolved to the `Nearest_Branch__c` picklist. Unknown values → 422; omission is valid. "Branch" means a Cóndor branch; third-party dealers are out of scope for v1. `Sucursal_Seleccionada_Meta__c` is not used (Meta-flow specific).
- Reason: the branch preference exists in the org and helps routing/reporting, but advertising leads often lack it.
- Impact: resolver validates against a fixed 4-code catalog; closes the dealer/branch-semantics pending item.

## 2026-08-31 — Phone normalization replicates the org flow (Decision, Phase 7)

- Decision: the API normalizes `phone` before duplicate matching AND before storing `MobilePhone`, replicating the exact rule of the org flow `DatosInicialesProspecto` ("Limpiar Teléfono (Siempre)"): strip `+`, spaces, `-`, `(`, `)`; if the result starts with `0`, replace the leading `0` with `595`; otherwise pass through unchanged. Implemented as `MGAgenciaPhoneNormalizer`.
- Reason: the flow rewrites `MobilePhone` to `595…` after insert, so duplicate matching on the un-normalized value would miss same-person resubmissions in local `0981…` format, and the stored value would briefly diverge from org convention.
- Evidence: flow formula `formula_5` (strip) + `formula_5_normalizado` (`IF(BEGINS(x,"0"), "595" & RIGHT(x, LEN(x)-1), x)`) retrieved from `condor-qas`.
- Impact: `0981123456` and `595981123456` are now treated as the same number; foreign/odd input is only stripped, never rewritten (documented behavior).

## 2026-08-31 — Authentication: OAuth 2.0 Client Credentials on a dedicated Connected App (Decision 8)

- Decision: target production authentication is the **OAuth 2.0 Client Credentials** flow on a dedicated Connected App, run-as the least-privilege integration user (profile "Minimum Access - API Only Integrations" + permission set `MGAgencia_Integration`). MGAgencia receives only a `client_id` / `client_secret`.
- Interim: the sandbox Phase 7 E2E used SOAP session auth because a Connected App consumer secret must be created and revealed by a human admin in the UI; automation must never handle that secret.
- Reason: client credentials is the standard server-to-server grant with no user interaction, no password/token sharing, and per-app IP and scope control; it maps cleanly onto a dedicated run-as user for least privilege and auditability.
- Alternatives: username/password + security token over SOAP (rejected for production — shares a password, brittle with IP/token policy); JWT bearer (viable but requires MGAgencia to hold a private key and manage certificate rotation).
- Impact: production REQUIRES the Connected App + secret-handover procedure — see the admin runbook `docs/AUTH_SETUP.md`. `docs/API_SPEC.md` §2 updated: client credentials CONFIRMED as target (PENDING removed). Admin follow-ups tracked in `docs/ADMIN_FOLLOWUPS.md`.

## 2026-09-01 — Provider renamed to MGAgencia (rebrand)

- Decision: the integration provider was wrongly referred to as "Nebüla" during discovery and implementation; the real client is **MGAgencia** (Nebüla is a different, unrelated client). Everything was rebranded before UAT: endpoint `/mgagencia/v1/leads`, `MGAgencia*` Apex classes, queue `MGAgencia_Leads`, CMDT `MGAgencia_Integration_Setting__mdt`, custom permission `MGAgencia_Integration_Bypass`, permission set `MGAgencia_Integration`, log object `MGAgencia_Integration_Log__c`, picklist values `Formulario MGAgencia` / `MGAgencia`, assignment rule entry, field labels, integration user `mgagencia.integration@condor.com.py.qas.mga`, and all project docs.
- Reason: shipping UAT and production metadata under the wrong client name would create permanent confusion (Nebüla is a real, distinct client of the group).
- Alternatives: keep internal API names and change only labels (rejected — the wrong name would live on in code, logs and security objects).
- Impact: earlier entries in this log were written under the old name and now read "MGAgencia" after a global rename; functional decisions are unchanged. Old Nebula-named org components are removed (or listed in `docs/ADMIN_FOLLOWUPS.md` if deletion was blocked).

## 2026-09-01 — Duplicate scan runs in system mode (DEF-001)

- Decision: the duplicate-detection SOQL in `MGAgenciaDuplicateEvaluator` runs in SYSTEM_MODE via a private `without sharing` inner class; every other operation (validation, Lead DML, logging) stays in user mode / `with sharing`.
- Reason: duplicate detection must scan Leads org-wide. The least-privilege integration user is not a member of the `MGAgencia_Leads` queue that owns API-created Leads, so a sharing-enforced scan saw nothing and silently reported `duplicated: false` on every request (UAT defect DEF-001). No record data crosses the API boundary beyond the boolean flag and generic reason codes, so the sharing bypass is contained and auditable.
- Alternatives: adding the integration user to the queue (rejected — grants broad record visibility and inbox noise for a non-human user); a sharing rule to the integration user (rejected — same over-exposure, more admin surface).
- Impact: `MGAgenciaDuplicateEvaluator` refactor + regression test `duplicateIsDetectedUnderLeastPrivilegeIntegrationUser`; TEST_PLAN §6 documents DEF-001.
