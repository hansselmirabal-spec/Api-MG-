# FIELD_MAPPING — Lead (Nebüla → Salesforce)

## 1. Discovery summary

- Org inspected: sandbox `condor-qas` (`adminsalesforce@condor.com.py.qas`), read-only.
- Date: 2026-08-26.
- Sources inspected:
  - `sf sobject describe` for `Lead`, `Campaign`, `ProductSeller__c`, `VendorCode__c`, `Branch__c`, `BranchCode__c`, `Region__c`, `Calendario_de_Asignaciones__c`, `Opportunity`, `Account`.
  - Tooling API: `ValidationRule`, `ApexTrigger`, `ApexClass` bodies (`LeadTrigger`, `LeadTriggerHandler`, `TriggerLogicsCommon`, `Utils`), `WorkflowRule`, `Flow.Metadata` of the create-triggered flows.
  - Metadata retrieve: `CustomObject:Lead` (validation rule formulas, record-type picklist values), `DuplicateRule`, `AssignmentRules:Lead`.
  - SOQL: `MatchingRule`/`MatchingRuleItem`, `FlowDefinitionView`, `PermissionSet`, `ObjectPermissions`, `EntityDefinition`, record counts and picklist usage on `Lead` (aggregates only).
- Lead object size: 219 fields, 5 record types, 31 validation rules (23 active), 28 active record-triggered flows, 12 workflow rules, 1 active Apex trigger, 1 active duplicate rule, 1 active assignment rule.

Conventions: **Confirmed** = observed in metadata. **PROPOSED** = suggestion by the integration team, not approved. **PENDING BUSINESS DECISION** = requires an answer from the business/Salesforce owner before implementation.

---

## 2. Lead record types

| Label | Developer name | Active | Default (admin profile) | Usage in sandbox |
|---|---|---|---|---|
| Persona Física | `Fisica` | yes | yes | ~9.9k |
| Persona Física Precali | `Fisica_Precali` | yes | no | 4 |
| Persona Jurídica | `Juridica` | yes | no | 157 |
| Gobierno o ente público | `GobiernoEntePublico` | yes | no | 0 |
| Principal | `Principal` | yes | no (master) | 0 |

All record types expose the same values for `LeadSource`, `Family__c`, `Nearest_Branch__c`, `Preferencia_de_contacto__c`, `VehicleType__c`, `lead_type__c`. `Fisica_Precali` adds `Estatus__c = Precalificado`. Note: flows `Asignacion_para_Precalificacion` / `Asignacion_Lead_a_Vendedor` may switch the record type to `Fisica_Precali` after creation.

Record type for API-created Leads: **PENDING BUSINESS DECISION** (evidence suggests `Fisica` for consumer leads; `Juridica` if Nebüla sends company data).

---

## 3. Lead mandatory fields (evidence-based)

### 3.1 System-required (describe: `nillable=false`, no default)

| Field | Type | Evidence |
|---|---|---|
| `LastName` | string(80) | Only createable field with `nillable=false` and no default. |
| `Company` | string | Standard-required in UI only; API accepts null. Flow `DatosInicialesProspecto` **clears** `Company` when record type is `Fisica`. |
| `Status` | picklist | Defaults to `Prospecto` if omitted. |
| `OwnerId` | lookup | Defaults to the running (integration) user if omitted; see assignment section. |
| `CurrencyIsoCode` | picklist | Defaults to `USD`. |

### 3.2 Required by active validation rules at INSERT time

| Field | Rule | Condition | Impact on API |
|---|---|---|---|
| `FirstName` | `FirstNameRequired` | Blank `FirstName` and user role ≠ `SystemAdministrator`. | **Blocks insert** for an integration user unless it has the `SystemAdministrator` role (not acceptable per least-privilege). Nebüla must send a first name, or the rule must be adjusted. |
| `VendorCode2__c` (Vendedor producto) | `CodigoVendedorAsignacion` | `ISNEW()` AND `Status <> 'Nuevo'` AND `VendorCode2__c` blank AND profile ∉ {`Pre-calificación`, `Administrador del sistema`}. | **Blocks insert** for any non-admin integration profile because `Nuevo` is not an active `Status` value (active values: Formulario Meta, Lead MQL, Lead SQL, Nurturing, Lead Gestionado, Prospecto, Convertido, Perdido). The trigger auto-fills `VendorCode2__c` from a `ProductSeller__c` owned by the running user matching `Family__c`, so the integration user would need its own `ProductSeller__c` rows, or the rule/profile must be handled. **Design blocker.** |
| `Campana__c` (Evento) | `Completar_Evento` | `LeadSource = 'Campaña'` OR `Visit_to_the_showroom__c = 'Eventos'`, and `Campana__c` blank. | Only if API uses `LeadSource = Campaña`. |
| `Visit_to_the_showroom__c` | `Completar_Visita_al_Showroom` | `LeadSource = 'Visita a Showroom'`. | Avoid that LeadSource. |
| `Colaborador_que_refiri__c` | `Completar_colaborador_que_refirio` | `LeadSource = 'Referido colaborador'`. | Avoid that LeadSource. |
| `VehicleObservation__c` | `ValidarFamiliaProducto` | `Family__c = 'Otros'` (value not active in picklist). | N/A. |
| `Segmento__c` + `interest_model__c` | `Segmento_y_o_Modelo_vacio_o_otros` | `Status = 'Prospecto'` (or conversion) AND family not "usados" AND segment/model blank or "otro(s)", unless `Validation_Bypass__c` is in the future. | **Blocks insert if `Status` defaults to `Prospecto`** and vehicle segment/model are not sent. Note both fields carry defaults (`Segmento__c = HS PHEV`, `interest_model__c = MG RX9 LUX`), so an insert without them passes but records a wrong vehicle. Must be handled. |
| `RUC__c` format | Apex `LeadTriggerHandler` | If `RUC__c` sent without `-` → `addError('Error en el formato del RUC.')`. | Validate RUC format `NNNNNNN-D` before DML or do not send RUC. |
| `MobilePhone` format | `MobileFormat` | Only on update (`ISNEW()=false`), `LeadSource <> 'Web'`, must start with `595`, 12 digits. Flow `DatosInicialesProspecto` normalises `MobilePhone` (strips `+ - ( ) space`, leading `0` → `595`). | Not blocking at insert; later updates by users will fail if the number is not `595XXXXXXXXX`. API should normalise to that format. |

Rules that only fire on status transitions / conversion (`CI_obligatorio_para_Fisica`, `RUC_obligatorio_para_Juridica`, `ConvertirLead`, `ValidateSearchData`, `ControlVendedorAsignado`, `Motivo_de_Perdida`, `CompletarCampoObservacionDeCierre`, `InteresCompraCalificado`, `ValidarTarea*`, `No_volver_a_estado_por_asignar`, `Completar_Tratamiento_para_convertir`, `CampoObligatorioModeloDeInteres`, `ValidateProductVendorCode`, `Cambiar_Vehiculo_de_Interes`) do not affect API creation as long as `Status` at insert is not `Convertido`/`Perdido`/`Calificado`.

### 3.3 Mandatory set — summary

| Field | Required because | Status |
|---|---|---|
| `LastName` | system | Confirmed |
| `FirstName` | `FirstNameRequired` | Confirmed (unless integration user holds SystemAdministrator role — not recommended) |
| `Status` | must be an explicit value chosen for API leads; the default `Prospecto` triggers `Segmento_y_o_Modelo_vacio_o_otros` | **PENDING BUSINESS DECISION** (candidate values: `Formulario Meta` → enters existing Meta assignment pipeline; `Lead MQL`; `Nurturing`) |
| `Family__c` | drives vendor assignment, assignment calendars and the `Reglas de Meta` assignment rule | **PENDING BUSINESS DECISION** (likely fixed `AUTOMÓVILES MG` for this project, but must be confirmed) |
| `VendorCode2__c` or bypass | `CodigoVendedorAsignacion` | **Design blocker — see Risks** |
| `MobilePhone` and/or `Email` | duplicate detection (matching rule uses both) and contact | **PENDING BUSINESS DECISION** (which of the two is mandatory from Nebüla) |
| `RecordTypeId` | record type selection | **PENDING BUSINESS DECISION** |

---

## 4. Relevant optional fields (candidates for the mapping)

| API name | Label | Type | Notes |
|---|---|---|---|
| `Salutation` | Tratamiento | picklist | Trigger resolves `ClientTreatment__c` from it. |
| `Email`, `Email_2__c`, `Email_3__c` | e-mail | email | `Email` used by matching rule `Lead_Duplicados`. |
| `Phone`, `MobilePhone`, `Phone_2__c`, `Movil_2__c` … | phones | phone | `MobilePhone` used by matching rules and by flows (account lookup by phone). |
| `Tel_fono_Meta__c` | Teléfono Meta | text | Raw phone as received from Meta (precedent for storing the raw external value). |
| `CI__c`, `RUC__c` | document numbers | text | RUC validated/auto-corrected in trigger; `CONTROL_CUENTA_EXISTENTE` flow links existing Account by CI/RUC and sets `Codigo_vendedor__c`/`Nuevo__c`. |
| `LeadSource` | Origen | picklist | See §8. |
| `Campana__c` | Evento | lookup(Campaign) | Campaign link. `campa_a_meta__c` (text) is the raw Meta campaign name; flow `Actualizar_Campa_as_Digitales` resolves/creates a Campaign by `Name` when `LeadSource` ∈ {Redes Sociales Empresa, Redes Sociales Propias del Vendedor}. |
| `Family__c` → `Brand__c` → `Segmento__c` → `interest_model__c` | product hierarchy | dependent picklists | Controlling chain: `Family__c` controls `Brand__c`, `Brand__c` controls `Segmento__c`, `Segmento__c` controls `interest_model__c`. MG values exist (`Family__c = AUTOMÓVILES MG`; models such as MG RX9 LUX). Exact value list to be sent by Nebüla: **PENDING BUSINESS DECISION**. |
| `Brand1__c`, `Model__c`, `VehicleOfInterestOfTheWeb__c` | free text brand/model | text | Non-validated free-text alternatives (used by web forms). |
| `Nearest_Branch__c` | Sucursal más cercana | picklist | `ASUNCIÓN | CIUDAD DEL ESTE | CORONEL OVIEDO | ENCARNACIÓN`. |
| `Sucursal_Seleccionada_Meta__c` | Sucursal Seleccionada Meta | text | Values in use: `asunción`, `ciudad_del_este`, `encarnación`, `coronel_oviedo`. Flow `Asignacion_Lead_a_Vendedor` matches it against `Calendario_de_Asignaciones__c.Sucursal__c`. |
| `Preferencia_de_contacto__c` | Preferencia de contacto | picklist | `Correo Electrónico | WhatsApp | Teléfono`. |
| `PurchaseTerm__c` | Interés de compra | picklist | `INMEDIATA | EN 3 MESES | 6 MESES | 1 AÑO | SIN INTERES DE COMPRA`. |
| `Description`, `Comments__c`, `Descripci_n_de_Meta__c` | free text | textarea/text | |
| `sfleadcaphfprod__External_Lead_ID__c` | External Lead ID | text, **External ID** | Managed package (Salesforce Lead Capture). Populated on ~8.1k leads (Meta). Reusing it for Nebüla would mix sources: **PENDING BUSINESS DECISION**. |
| `ID_Meta__c`, `Meta_CTWA_CLID__c`, `Meta_Conversion_Data__c` | Meta identifiers | text | Precedent of source-specific ID fields. |
| `TestDriveRequested__c`, `WebIdentification__c` | test drive | boolean/picklist | Flow sets `TestDriveRequested__c` when `WebIdentification__c = TEST DRIVE`. |
| `Country__c`, `GeographicalDepartment__c`, `City__c` | geography | lookups/picklist | `Region__c` has `RegionCode__c` and `IntegrationCode__c`. |
| `Validation_Bypass__c` | datetime | | Grace window that disables `Segmento_y_o_Modelo_vacio_o_otros`. Could be leveraged but is a workaround. |

---

## 5. Automation inventory and impact on API-created Leads

### 5.1 Validation rules
Listed in §3.2. Blocking at insert for a non-admin integration user: `FirstNameRequired`, `CodigoVendedorAsignacion`, `Segmento_y_o_Modelo_vacio_o_otros` (if `Status = Prospecto`), Apex RUC format check.

### 5.2 Apex trigger
`LeadTrigger` (before insert, before update) → `LeadTriggerHandler`. On insert:
- Normalises `RUC__c` check digit; adds error if the format is not `ci-dv`.
- Sets `ClientTreatment__c` from `Salutation`.
- Auto-assigns `VendorCode2__c` from `ProductSeller__c` where `KindOfProduct__r.Name = Family__c` **and `OwnerId = running user`**, only when the user is not the configured admin role (`Conf_Parameters__c.AdminRole__c`) or has `User.AssignCodesAutomatically__c = true`.
Inactive trigger `ValidateLead` ignored.

### 5.3 Record-triggered flows fired on CREATE (active)

| Flow | Trigger | Entry condition | Effect |
|---|---|---|---|
| `DatosInicialesProspecto` | after save | always | Upper-cases names; clears `Company` for `Fisica`; normalises `MobilePhone`; sets seller e-mails from `VendorCode2__r.Owner`; sets `TestDriveRequested__c`; e-mail alert on status change. |
| `CONTROL_CUENTA_EXISTENTE` | before save | `RUC__c` or `CI__c` present | Looks up Account by RUC/CI; links `Cuenta__c`; sets `Codigo_vendedor__c` from `AccountCodes__c` (cartera). |
| `Asignacion_de_Vendedor_Producto` | after save | always | Looks up `ProductSeller__c` by `Nombre_completo_del_vendedor__c` + `Family__c`. |
| `Actualizar_Campa_as_Digitales` | after save | `LeadSource` ∈ {Redes Sociales Empresa, Redes Sociales Propias del Vendedor} | Finds Campaign by `Name = campa_a_meta__c`, **creates one** under parent "Campañas Meta" if missing, sets `Campana__c`. |
| `Asignacion_Lead_a_Vendedor` | after save | `OwnerId` = queue **Reglas Meta** | Round-robin via `Calendario_de_Asignaciones__c` (branch from `Sucursal_Seleccionada_Meta__c`, product from `Family__c`), business hours, cartera match by phone; sets `OwnerId`, `Estatus__c = Asignado`, `VendorCode2__c`, may set record type `Fisica_Precali`. |
| `Asignacion_para_Precalificacion` | after save | `OwnerId` = a specific queue (pre-qualification) | Assigns a pre-qualifier, sets `Fisica_Precali`. |
| `Asignaci_n_de_prospectos_Lead_Capture` | after save | `Identificador_Lead_Capture__c` not null | Owner from `Conexion_Facebook__c`. |
| `Actualizar_Propietario_del_Propecto_Precali` | before save | owner is one of 3 hard-coded users | Sets `Precalificado_por__c`, record type. |
| `ACTUALIZAPROPIETARIOLEAD` | after save | `VendorCode2__c` set/changed | `OwnerId` ← seller owner. |
| `Notificacion_Lead_Asignado` | after save | owner is a User ≠ creator | Apex `LeadAssignmentNotificationService` (notification). |
| `WA_Lead_Asignado_Registro` | after save | owner is a User, not converted | Apex `WaLeadConversationRegistrar` (WhatsApp). |
| `Crear_Tarea_si_Asignado` / `Crear_Tarea_si_No_Contactado` / `Pasar_a_No_Contactado_Despues_de_2H` | after save | `Estatus__c` = Asignado / No Contactado | Task creation, scheduled status change. |
| `Alerta_para_Covering`, `Flujo_Tasacion_Usados_3`, `Creaci_n_de_una_tarea_cuando_es_showroom_1`, `Lead_Registrar_Cambio_Propietario`, `JBSystem_Lead_RecordFlow` | after/before save | status change / `Tasacion_Usados__c` / showroom / owner change | Not triggered by a plain API insert unless those fields are set. |

Update-only flows (not fired on insert): `ACTUALIZA_ETAPA_ASIGNADO_LEAD`, `Actualizar_Ultimo_Estado_Lead`, `Al_cambiar_Propietario_Actualizar_Vendedor_Producto`, `Asignar_a_Vendedor_al_cambiar_a_Lead_SQL`, `Borrar_*`, `Crear_Tarea_por_Reasignacion_*`, `Registrar_Contacto`.

Workflow rules on Lead (12, legacy): `Al Crear Precali Ale/Fio`, `Asignar a Lead MQL a Vendedor`, `Cambiar a SQL`, `Cambiar Estado a Lead Gestionado`, `Cambiar Estado a Lead MQL`, `Recordatorio de volver a intentar`, `Tarea Para Contactar`, `Tarea si Tarea Futura`, `WF_AL_*`. Criteria not retrieved in this pass (impact: field updates/tasks; to be reviewed before go-live).

Impact: an API-created Lead enters the same pipeline as Meta leads **only if** `LeadSource`, `Status`, `Family__c` and `Sucursal_Seleccionada_Meta__c` carry the values those automations expect. Otherwise it stays owned by the integration user with no assignment.

### 5.4 Duplicate rules / matching rules

| Duplicate rule | Active | Matching rule | Fields | On insert | On update | Filter |
|---|---|---|---|---|---|---|
| `Prospecto_Duplicado_por_Telefono` | yes | `Lead_Duplicados` (exact) | `MobilePhone` AND `Email` (both exact, null not allowed) | **Allow + Report** | Allow + Report | Existing lead `Status <> Perdido` |
| `Standard_Lead_Duplicate_Rule` | no | `Standard_Lead_Match_Rule_v1_0` | — | — | — | — |
| `Standard_Rule_for_Leads_with_Duplicate_Contacts` | no | — | — | — | — | — |

Other active matching rule without a duplicate rule: `regla_de_coincidencia_de_Prospecto_Duplicado_por_Telefono` (`MobilePhone` exact).

Impact: **no duplicate rule blocks creation**. Duplicates are reported (`DuplicateRecordSet`/`DuplicateRecordItem`) only; the API can create the Lead and must implement its own flag (see §7).

### 5.5 Assignment rules

| Rule | Active | Criteria | Assign to |
|---|---|---|---|
| `Reglas de Meta` | yes | `LeadSource = Redes Sociales Empresa` AND `Status = Formulario Meta` AND `Family__c <> AUTOMÓVILES MG` | Queue `Reglas Meta` (then flow `Asignacion_Lead_a_Vendedor` distributes) |
| `Asignacion al Admin`, `PreCalificacion` | no | — | — |

Assignment rules only run via API when the `AssignmentRuleHeader` / `DMLOptions.useDefaultRule` is set. Note the active rule explicitly **excludes** `AUTOMÓVILES MG`; MG leads are therefore not queued by this rule today. How MG leads are assigned: **PENDING BUSINESS DECISION**.

### 5.6 Custom metadata / custom settings referenced by Lead automation

- `Conf_Parameters__c` (hierarchy custom setting): `AdminRole__c` used by `TriggerLogicsCommon.hasPermission()`; also holds DW/SAP endpoints and credentials (do not expose).
- `Protocolo_Contacto_Cadencia__mdt` (contact cadence, used by contact protocol automation).
- `WA_Chat_Setting__mdt`, `WA_Quick_Reply__mdt` (WhatsApp).
- No custom metadata type currently exists for dealer or campaign code mapping.

---

## 6. Dealer / Concessionaire resolution candidates

No object named "Dealer/Concesionario" exists. Candidates found:

| Candidate | API name | Identifying code | Records | Evidence / fit |
|---|---|---|---|---|
| Branch picklist on Lead | `Lead.Nearest_Branch__c` | picklist value (4) | — | Used by UI; values ASUNCIÓN, CIUDAD DEL ESTE, CORONEL OVIEDO, ENCARNACIÓN. Mirrors `Opportunity.Nearest_Branch__c`. |
| Meta branch text on Lead | `Lead.Sucursal_Seleccionada_Meta__c` | free text (`asunción`, `ciudad_del_este`, `encarnación`, `coronel_oviedo`, `pre-calificacion`) | — | **Drives the assignment flow** via `Calendario_de_Asignaciones__c.Sucursal__c` (picklist with the same 5 values). |
| Sales zone | `Zone__c` | `Name` | 5 (Central, Coronel Oviedo, Encarnación, Ciudad del Este, Filial DEALERS) | Referenced by `VendorCode__c.Zone__c`. |
| Vendor code | `VendorCode__c` | `VendorCode__c` (**External ID**) | 217 | Seller code (with `Zone__c`), not a dealer. |
| Product seller | `ProductSeller__c` | `Name` (code) | 548 | Seller × product family; target of `Lead.VendorCode2__c`. |
| Branch ("Ramo") | `Branch__c` | `Code__c` | 19 | Payroll/collection branches (names of people, RRHH) — **not** dealers. |
| Branch code | `BranchCode__c` | `BranchCode__c` | 4 | Account classification — not dealers. |
| Dealer picklist on Opportunity | `Opportunity.Dealer__c` | picklist (`GOROSTIAGA`, `AUTOMALL`) | — | Third-party dealers; no equivalent on Lead. |
| Region | `Region__c` | `RegionCode__c`, `IntegrationCode__c` | 1525 | Geographic departments, not dealers. |

PROPOSED: Nebüla sends a `dealer_code` resolved through a new custom metadata type (e.g. `Nebula_Dealer_Mapping__mdt`: external code → `Nearest_Branch__c` value + `Sucursal_Seleccionada_Meta__c` value). Whether "concessionaire" in Nebüla means Cóndor branch (4 cities) or third-party dealer (Gorostiaga/Automall): **PENDING BUSINESS DECISION**.

---

## 7. Campaign resolution candidates

- `Campaign` custom fields: `DB_Campaign_Tactic__c` (picklist), `Asistencia__c` (boolean). **No External ID / external code field exists.**
- Record types: `Principal` only. Active campaigns: 139 of 829.
- `Campaign.Type` values: PARTNERS, Shopping, Expo, Eventos propios, Bancos / Cooperativas, Activaciones puntuales, Campañas WhatsApp, Universidades. `Status`: PLANIFICACIÓN, EN PROGRESO, CANCELADO, COMPLETADO.
- Precedent: Meta integration stores the raw campaign name in `Lead.campa_a_meta__c` and flow `Actualizar_Campa_as_Digitales` resolves by `Campaign.Name` (auto-creating under parent "Campañas Meta").

Options (evidence-based, not decided):
1. Add an External ID text field on Campaign (e.g. `Nebula_Campaign_Code__c`) and resolve `campaign_code` → `Campana__c`. Requires the marketing team to populate codes.
2. Resolve by `Campaign.Name` like the Meta flow (fragile, name collisions).
3. Auto-create campaigns under a "Campañas Nebüla" parent when unknown (mirrors Meta behaviour).

Which option: **PENDING BUSINESS DECISION**.

---

## 8. Lead Source, Status and existing duplicate signals

- `LeadSource` active values: Asignado por Gerencia, Campaña Digital, Dealer, Campaña, Freelance, Funcionarios, Gestión Cartera, Gestión propia, Intercompany, Lead recuperado, Licitaciones, Llamada Telefónica del Prospecto, Pop-up delSol, Redes Sociales Empresa, Redes Sociales Propias del Vendedor, Referido, Referido colaborador, Referido Vendedor, Taller, Visita a Showroom, Web, WhatsApp Corporativo, WhatsApp Corporativo Empresa. Most used: Redes Sociales Empresa (~5.3k), Redes Sociales Propias del Vendedor (~2.8k). No value for "Nebüla" exists. Value to use (existing `Campaña Digital`/`Dealer`, or a new `Nebüla` value): **PENDING BUSINESS DECISION**.
- `Status` active values: Formulario Meta, Lead MQL, Lead SQL, Nurturing, Lead Gestionado, Prospecto (default), Convertido, Perdido. Validation rules also reference inactive values (`Nuevo`, `Calificado`, `Asignado`…).
- `Estatus__c` (secondary status): Asignado, Nuevo, No Responde, No Contactado, Contactado, Sin Tarea, Reasignado, Precalificado.
- Existing duplicate signals on Lead:
  - `ItIsNotADuplicateOpportunity__c` (boolean, semantics relate to Opportunity, not Lead duplicates).
  - `loss_reason__c` value `Duplicado` (used when a Lead is closed as lost because duplicated).
  - Duplicate rule reporting into `DuplicateRecordSet` (Allow/Report).
  - No boolean "duplicate lead" flag exists. A new field (e.g. `Nebula_Is_Duplicate__c` + `Nebula_Duplicate_Of__c`) would be needed: PROPOSED, rule **PENDING BUSINESS DECISION**.

---

## 9. Integration user / permission set candidates

Permission sets whose names suggest integration/API use: `WebServices`, `Salesforce_Lead_Capture` (Lead CRE), `Meta_Lead_Automation`, `Lead_Ciclo_Propietario`, `ExactTarget_Integration`, `sfdc_scrt2`, `sfdc_a360`, `MuleSoftXAPIAIPermSet`, plus Salesforce-managed integration sets (`Anc*IntegrationUser`, `C2C*`, `E360MessagingC2CPermSet`, `HighScaleFlowC2CPermSet`, `D360HomeOrgPermSet`).
Profiles of interest: `Minimum Access - API Only Integrations`, `Salesforce API Only System Integrations`, `Minimum Access - Salesforce`, `Anypoint Integration`.
None is Nebüla-specific. PROPOSED: dedicated API-only user + new permission set (Apex class access, Lead create/read, FLS on mapped fields, read on Campaign/dealer mapping, create on integration log).

---

## 10. Proposed mapping skeleton

| Nebüla field (PROPOSED) | Salesforce field | Type | Required | Transformation / resolution | Status |
|---|---|---|---|---|---|
| `external_lead_id` | new `Nebula_External_Id__c` (External ID, unique) — or reuse `sfleadcaphfprod__External_Lead_ID__c` | text | yes (proposed) | stored as-is; used for idempotency/duplicates | **PENDING BUSINESS DECISION** (whether Nebüla can send it; which field) |
| `first_name` | `FirstName` | text | yes | trim; flow upper-cases | Confirmed required by `FirstNameRequired` |
| `last_name` | `LastName` | text | yes | trim | Confirmed system-required |
| `phone` | `MobilePhone` | phone | yes/no | normalise to `595XXXXXXXXX`; raw copy in a new field or `Tel_fono_Meta__c`-style field | **PENDING BUSINESS DECISION** (phone vs email mandatory) |
| `email` | `Email` | email | yes/no | lower-case, RFC check | **PENDING BUSINESS DECISION** |
| `document_number` | `CI__c` (Fisica) / `RUC__c` (Juridica) | text | no | RUC must be `ci-dv`; CI digits | **PENDING BUSINESS DECISION** (is it sent; person vs company) |
| `campaign_code` | `Campana__c` | lookup | ? | resolve via Campaign external code / name / auto-create | **PENDING BUSINESS DECISION** (§7) |
| `dealer_code` | `Nearest_Branch__c` + `Sucursal_Seleccionada_Meta__c` | picklist + text | ? | resolve via custom metadata mapping | **PENDING BUSINESS DECISION** (§6) |
| `brand` / `model` / `version` / `year` | `Family__c`/`Brand__c`/`Segmento__c`/`interest_model__c` (validated) or `Brand1__c`/`Model__c`/`VehicleOfInterestOfTheWeb__c` (free text) | picklists / text | ? | catalog mapping (custom metadata) or free text | **PENDING BUSINESS DECISION** (Nebüla catalog IDs are unknown; do not invent) |
| — (constant) | `LeadSource` | picklist | yes | fixed value for Nebüla | **PENDING BUSINESS DECISION** |
| — (constant) | `Status` | picklist | yes | fixed initial status | **PENDING BUSINESS DECISION** |
| — (constant) | `RecordTypeId` | lookup | yes | resolved by developer name (no hard-coded ID) | **PENDING BUSINESS DECISION** |
| — (constant) | `Family__c` | picklist | yes | probably `AUTOMÓVILES MG` | **PENDING BUSINESS DECISION** |
| `comments` | `Description` or `Comments__c` | text | no | truncate to field length | PROPOSED |
| `contact_preference` | `Preferencia_de_contacto__c` | picklist | no | map to Correo Electrónico / WhatsApp / Teléfono | PROPOSED |
| `test_drive` | `TestDriveRequested__c` | boolean | no | | PROPOSED |
| — (system) | new `Nebula_Is_Duplicate__c`, `Nebula_Duplicate_Of__c` | boolean / lookup | — | set by application service | rule **PENDING BUSINESS DECISION** |
| — (system) | `OwnerId` | lookup | — | integration user, or queue for assignment | **PENDING BUSINESS DECISION** (§5.5) |

---

## 11. Risks and open questions

1. **`CodigoVendedorAsignacion` blocks inserts** by a non-admin user with `Status <> Nuevo` (an inactive value) and empty `VendorCode2__c`. Options: (a) integration user owns `ProductSeller__c` rows per family so the trigger auto-fills; (b) add a bypass condition (custom permission) to the rule; (c) API resolves a `ProductSeller__c` explicitly. Needs Salesforce admin decision.
2. **`FirstNameRequired`** — Nebüla must always send a first name, or rule adjusted with a custom permission bypass.
3. **`Segmento_y_o_Modelo_vacio_o_otros`** fires when `Status = Prospecto` (the default). The defaults `Segmento__c = HS PHEV`, `interest_model__c = MG RX9 LUX` mask the problem by silently storing a wrong vehicle. Initial status and vehicle mapping must be decided together.
4. **Assignment pipeline is Meta-shaped**: assignment rule excludes `AUTOMÓVILES MG`; distribution flow relies on `Sucursal_Seleccionada_Meta__c`, `Family__c`, `Status = Formulario Meta` and the `Reglas Meta` queue. Reusing it for Nebüla requires business confirmation; otherwise Nebüla leads stay owned by the integration user.
5. **Duplicate rule is Allow/Report** — creation is never blocked, consistent with the create-and-flag requirement; but no duplicate flag field exists. Salesforce's own report (both `MobilePhone` AND `Email` exact, excluding `Perdido`) is stricter than what the business may want.
6. **No Campaign external code field**; Meta precedent auto-creates campaigns by name.
7. **No dealer object**; "dealer/concessionaire" semantics (Cóndor branch vs third-party dealer) unresolved.
8. Flows `DatosInicialesProspecto` and `CONTROL_CUENTA_EXISTENTE` mutate incoming data (upper-case names, phone normalisation, `Company` cleared, account linkage by CI/RUC). The API response must not echo values that automation may later change, or must read back after insert.
9. Hard-coded record IDs inside flows (queues, users, campaign parent, record type) will differ between `condor-qas` and production; the API must resolve everything by developer name/code.
10. Legacy workflow rules (12) not analysed in detail; several fire on create for pre-qualification users.
11. `MobileFormat` rule will reject later user edits if the API stores phones outside the `595` + 9-digit format.
12. `Conf_Parameters__c` holds credentials for other integrations; the Nebüla permission set must not grant access to it.

Open questions for the business are all tagged **PENDING BUSINESS DECISION** above: external lead id, campaign identification, dealer semantics, vehicle catalog mapping, initial `Status`/`LeadSource`/record type/`Family__c`, mandatory contact field, duplicate rule, ownership/assignment, status query endpoint.
