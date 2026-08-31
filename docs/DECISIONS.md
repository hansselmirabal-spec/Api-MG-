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
- FINDING: the active assignment rule `Reglas de Meta` explicitly excludes `Family__c = AUTOMÓVILES MG`, and the distribution flow `Asignacion_Lead_a_Vendedor` keys on `Sucursal_Seleccionada_Meta__c`, `Family__c`, `Status = Formulario Meta` and the `Reglas Meta` queue. Nebüla leads will not be auto-assigned unless they adopt those values or a new assignment path is defined.
- FINDING: no dealer/concessionaire object exists. Branch identity lives in `Lead.Nearest_Branch__c` (picklist, 4 cities) and `Lead.Sucursal_Seleccionada_Meta__c` (text, same 4 values + `pre-calificacion`); third-party dealers only exist as `Opportunity.Dealer__c` picklist. `VendorCode__c.VendorCode__c` is the only relevant External ID and identifies sellers, not dealers.
- FINDING: `Campaign` has no external code / External ID field. The Meta flow resolves campaigns by `Name` and auto-creates them under a parent campaign.
- FINDING: several flows hard-code record IDs (queues, users, parent campaign, record type) that differ between sandbox and production. The API must resolve every reference by developer name / code, never by ID.
- FINDING: flows `DatosInicialesProspecto` and `CONTROL_CUENTA_EXISTENTE` mutate data after insert (upper-case names, phone normalisation to `595…`, `Company` cleared for `Fisica`, account linkage by CI/RUC). `MobileFormat` rejects later user edits if the phone is not `595` + 9 digits. The API should normalise phones before DML and should not echo values that automation may change.
- FINDING: Apex trigger `LeadTriggerHandler` raises `Error en el formato del RUC.` when `RUC__c` lacks the `-` check digit. RUC must be validated in the API layer or not sent.
- FINDING: `Conf_Parameters__c` (hierarchy custom setting used by the trigger for the admin role) also stores DW/SAP credentials. The Nebüla permission set must not grant access to it.

## 2026-08-29 — Assignment via dedicated queue + distribution flow (Decision 1)

- Decision: API-created Leads are owned by a dedicated queue (`Nebüla Leads`). A distribution flow (Meta pattern) routes them by branch / product family. The `CodigoVendedorAsignacion` validation rule is bypassed with a custom permission granted only to the integration user. Nebüla never sends seller codes.
- Alternatives: Nebüla sends a seller code resolved via `VendorCode__c` External ID (couples Nebüla to seller roster); integration user owns `ProductSeller__c` rows so the trigger auto-assigns (all leads land on one seller).
- Impact: requires queue, custom permission, VR edit, distribution flow, and integration-user permission set.

## 2026-08-29 — New Status and LeadSource values (Decision 2)

- Decision: new `Lead.Status` value `Formulario Nebüla` as the initial status of API-created Leads (distribution flow trigger; moves to the standard pipeline on assignment) and new `LeadSource` value `Nebüla`.
- Reason: replicates the Meta pattern (`Formulario Meta`), avoiding `Prospecto`-stage validation rules and silent vehicle defaults; enables filtering and reporting.
- Impact: picklist changes on Status and LeadSource; distribution flow keys on the new status.

## 2026-08-31 — Fixed record type, family and brand (Decision 3)

- Decision: every API-created Lead uses record type `Fisica` ("Persona Física"); `Family__c` = "AUTOMÓVILES MG" and `Brand__c` = "MG" are fixed via configuration (Custom Metadata). Nebüla sends none of these.
- Reason: advertising leads are individuals; the project scope is MG only; `Family__c` drives assignment and the dependent chain Family → Brand → Segmento → Model.
- Impact: interest model resolution (Segmento__c / interest_model__c) remains the only vehicle input expected from Nebüla — PENDING BUSINESS DECISION (external catalog).

## 2026-08-31 — Duplicate rule and flag (Decision 4)

- Decision: a Lead is marked duplicate when an existing non-lost Lead matches on MobilePhone OR Email (more aggressive than the org duplicate rule, which requires AND). If Nebüla provides `external_lead_id`, an identical value is a certain duplicate. Duplicates are always created, never rejected. New fields on Lead: checkbox `Duplicated_Lead__c` ("Lead Duplicado") plus a text field recording the match reason.
- Reason: advertising users resubmit forms changing one datum; business direction is create-and-mark.
- Impact: duplicate evaluator in the application service; two new Lead fields; reporting on duplicates becomes possible.

## 2026-08-31 — Phone mandatory, email optional (Decision 5)

- Decision: the API contract requires phone; email is optional.
- Reason: in Paraguay the effective contact channel is phone; advertising-form emails are frequently fabricated.
- Impact: contract validation; org flows normalize phone to `595…` format (MobileFormat VR) — normalization must happen before or during Lead creation.

## 2026-08-31 — Decision 1 amended: reuse the active assignment rule, no new flow

- Decision: routing to the `Nebüla Leads` queue is done by adding a rule entry to the org's single active Lead assignment rule ("Reglas de Meta"): `LeadSource = 'Nebüla'` → queue `Nebüla Leads`. No new distribution flow in v1. Apex opts in via `Database.DMLOptions.assignmentRuleHeader`.
- Evidence: Salesforce allows only one active assignment rule per object; the active rule routes Meta leads (`LeadSource = 'Redes Sociales Empresa'`, `Status = 'Formulario Meta'`, `Family__c ≠ 'AUTOMÓVILES MG'`) to queue `Reglas_Meta`. The "Asignación de prospectos Lead Capture" flow only maps Facebook page identifiers to advisors via `Conexion_Facebook__c` and is out of scope.
- Impact: smaller metadata footprint (queue + rule entry + custom permission); advisor-level distribution from the queue is a later, optional phase.
