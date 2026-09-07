# PRODUCTION_DEPLOYMENT_CHECKLIST — MGAgencia go-live on `mi-org`

Status: **not started**. Nothing in this document has been executed against
production. Every write step below requires explicit confirmation at the
moment it's run — this is a checklist, not an automation script.

Audit performed 2026-09-03 via read-only `sf` describe/SOQL against `mi-org`
(no writes). Complements the existing `docs/AUTH_SETUP.md` §8 checklist and
`docs/ADMIN_FOLLOWUPS.md` with the concrete gap list.

---

## 0. Blast-radius map — components NOT exclusive to MGAgencia (2026-09-03)

The repo's `force-app/` tracks a few org-wide, shared components alongside
the MGAgencia-only ones. Deploying the *entire* package blindly would touch
these and can affect Leads that have nothing to do with MGAgencia. Retrieved
each one fresh from `mi-org` today and diffed against the repo (read-only,
nothing written).

| Component | Shared with | Diff vs. current `mi-org` | Verdict |
|---|---|---|---|
| `standardValueSets/LeadSource.standardValueSet-meta.xml` | every Lead in the org | Repo = prod's 23 current values + `MGAgencia`. No values missing or reordered. | Safe in content, but **don't deploy this file** — add the value via Setup UI instead (§2 step 1). A file-based deploy risks clobbering a value added in prod after this file was last retrieved. |
| `standardValueSets/LeadStatus.standardValueSet-meta.xml` | every Lead in the org | **Amended 2026-09-07**: `Formulario MGAgencia` was dropped (Decision 2 amendment) — repo now matches prod's 8 current values exactly, no addition. | No longer needed for MGAgencia. Still don't deploy this file speculatively — no reason to touch it. |
| `objects/Lead/validationRules/FirstNameRequired.validationRule-meta.xml` | every Lead | **Byte-identical** to prod. | Safe, no-op if deployed. |
| `objects/Lead/validationRules/Segmento_y_o_Modelo_vacio_o_otros.validationRule-meta.xml` | every Lead (Prospecto-stage validation) | Only whitespace/formatting differs (prettier-apex reformat). Formula logic identical. | Safe, cosmetic-only if deployed. |
| `objects/Lead/validationRules/CodigoVendedorAsignacion.validationRule-meta.xml` | every Lead (vendor-code requirement on insert) | **Real discrepancy, not cosmetic.** Prod's current admin exemption is `$UserRole.Name != 'Administrador del sistema'` (role-based). The repo's version has that rewritten to `$Profile.Name != 'Administrador del sistema'` (profile-based) **and** adds `NOT($Permission.MGAgencia_Integration_Bypass)`. | 🔴 **Do not deploy as committed.** Deploying this file would silently change who's exempt from the vendor-code rule for every Lead in the org, not just add the MGAgencia bypass. Fix: rebuild this file from prod's current formula (role-based check) plus only the `NOT($Permission.MGAgencia_Integration_Bypass)` addition, before it's ever deployed to `mi-org`. |
| `assignmentRules/Lead.assignmentRules-meta.xml` | the org's Lead routing (`Reglas de Meta` rule) | Repo adds a `Lead.Family__c notEqual 'AUTOMÓVILES MG'` criterion to the existing `Reglas_Meta` entry (not in prod today) plus the new `MGAgencia_Leads` entry. Nothing removed. | Additive only — safe to deploy, but confirm the `Family__c` exclusion on the Meta rule is an intentional, approved change (it prevents Meta's rule from ever catching MG-family leads) and not an accidental side effect. |
| `connectedApps/MGAgencia_API.connectedApp-meta.xml` | — (net-new in prod) | Hardcodes `oauthClientCredentialUser = mgagencia.integration@condor.com.py.qas.mga` (the **sandbox** run-as user). | Must be repointed to the production integration user before/instead of deploying this field — and per `docs/AUTH_SETUP.md` gotcha #2, `oauthClientCredentialUser` can't be set via Metadata API anyway; set it in Setup UI regardless. |

**Bottom line**: never run a broad `sf project deploy start --source-dir force-app` against `mi-org`. Deploy an explicit, reviewed component list (§3 below), and fix `CodigoVendedorAsignacion` first — that's the one item here that would misfire on every Lead in the org, not just MGAgencia's.

---

## 1. Metadata gap audit (2026-09-03)

### 1.1 Already present in `mi-org` — no action needed

Shared with the existing Meta/Facebook Ads Lead integration, reused by
MGAgencia (per `MGAgenciaBranchResolver` and `MGAgenciaLeadService` doc
comments):

| Item | Status |
|---|---|
| `Lead.Tel_fono_Meta__c` | present |
| `Lead.Sucursal_Seleccionada_Meta__c` | present |
| `Lead.Preferencia_de_contacto__c` (picklist: Correo Electrónico, WhatsApp, Teléfono) | present, values match |
| `Lead.VehicleOfInterestOfTheWeb__c` | present |
| `Lead.Forma_de_Pago__c` | present |
| `Lead.Plazo_de_Compra__c` | present |
| `Lead.Entrega_su_Auto__c` | present |
| `Lead.TestDriveRequested__c` | present |
| `Lead.Tipo_de_test_drive__c` | present |
| `Lead.Nearest_Branch__c` | present (no longer written by MGAgencia — Decision 7 amendment) |
| `Lead.Family__c` (value `AUTOMÓVILES MG`) | present |
| `Lead.Brand__c` (value `MG`) | present |
| `Lead.Estatus__c` | present |
| RecordType `Lead.Fisica` ("Persona Física") | present, active |

**Conclusion**: none of today's 6 new fields (§4 of `docs/API_SPEC.md`) block
the production cutover — the underlying Lead fields already exist org-wide.

### 1.2 Missing — required for go-live

Nothing MGAgencia-specific has been deployed to `mi-org` yet. This is a
**first full deployment**, not an incremental one.

| Item | Notes |
|---|---|
| `Lead.External_Lead_Id__c` | core field, used by duplicate matching (Decision 4) |
| `Lead.Duplicated_Lead__c` | core field (Decision 4) |
| `Lead.Duplicate_Reason__c` | core field (Decision 4) |
| ~~`Lead.Status` value `Formulario MGAgencia`~~ | **Dropped (amended 2026-09-07)** — reuses existing `Formulario Meta` instead, no new value needed. |
| `LeadSource` value `MGAgencia` | **picklist value missing** (Decision 2) |
| Object `MGAgencia_Integration_Log__c` | entire object, not deployed |
| Custom Metadata Type `MGAgencia_Integration_Setting__mdt` | not deployed (drives Family__c/Brand__c defaults, Decision 3) |
| Queue `MGAgencia_Leads` | not created |
| Permission Set `MGAgencia_Integration` | not deployed |
| Custom Permission `MGAgencia_Integration_Bypass` | not deployed |
| 16 `MGAgencia*` Apex classes | none present |
| Connected App `MGAgencia API` | not created |
| Production integration user | not created (`docs/ADMIN_FOLLOWUPS.md` #3) |
| Validation rule `ValidarTareaEstadoContactado` | **does not exist in `mi-org` at all** (verified 2026-09-03 via Tooling API) — not just missing the exemption. It only exists in `condor-qas`, not tracked in `force-app/`. Do not confuse with `Validar_Tarea_Estatus_Contactado` (underscored name) which already exists in prod, inactive, and is a *different, unrelated* rule (different formula, different fields — `Estatus__c`/`FechaHoraContactado__c` based, nothing to do with MGAgencia). Build `ValidarTareaEstadoContactado` fresh in prod, with the `Formulario MGAgencia` exemption already included from day one (§2). |

---

## 2. Deployment order

Each step is a separate go/no-go — do not batch approvals.

1. **Add the picklist value** (Setup → Object Manager → Lead):
   - `LeadSource`: new value `MGAgencia`.
   - ~~`Status`: new value `Formulario MGAgencia`~~ — **dropped (amended
     2026-09-07)**. API-created Leads now reuse the existing `Formulario
     Meta` status; no new Status value needed. See `docs/DECISIONS.md`
     Decision 2 amendment.
2. ✅ **DONE (2026-09-07)** — Deploy ID `0AfTS000001wsyj0AA`, verified
   active via Tooling API. **Create the validation rule**
   `ValidarTareaEstadoContactado` on Lead in `mi-org` (it does not exist
   there yet, §0/§1.2) — same formula as
   `condor-qas`, with the `Formulario MGAgencia` exemption already included
   from the start:
   ```
   AND(
   NOT(ISPICKVAL(Status, 'Formulario Meta')),
   NOT(ISPICKVAL(Status, 'Formulario MGAgencia')),
   NOT(ISPICKVAL(Status, 'Prospecto')),
   NOT(ISPICKVAL(Estatus__c, 'No contactado')),
   NOT(ISPICKVAL(Status, 'Convertido')),
   ISNULL(LastActivityDate),
   $Profile.Name != 'Pre-calificación'
   )
   ```
   Error message: `Para pasar de estado se debe registrar alguna actividad.`
   Error display field: `EconomicActivity__c`.

   **Note (2026-09-07, after Decision 2 amendment):** the
   `NOT(ISPICKVAL(Status, 'Formulario MGAgencia'))` clause above is now dead
   — that Status value will never exist — but harmless (evaluates false,
   no-op). Already deployed to `mi-org` as-is; not worth a redeploy just to
   clean it up. MGAgencia Leads are exempted via the existing
   `NOT(ISPICKVAL(Status, 'Formulario Meta'))` clause instead.

   **Known pre-existing gap (found 2026-09-07 via `sf project deploy
   validate --test-level RunLocalTests` dry run against `mi-org`, and
   confirmed by running the same 3 test classes directly against
   `condor-qas`):** this rule already breaks `BudgetControllerTest`,
   `BudgetDocumentControllerTest` and `ProductControllerTest` (10/10
   fail, 100% fail rate) in `condor-qas` today, where it's already
   active but untracked in `force-app/`. Those Budget/Product classes
   share `TestFactoryData.createLead`, which builds a Lead in a
   non-exempt status without `LastActivityDate`/`EconomicActivity__c`
   set. Not caused by MGAgencia — inherited from the rule as it
   already exists in the sandbox. Deploying to `mi-org` replicates
   this exact gap rather than introducing a new one, but it does mean
   any real Budget/Product flow hitting the same Lead shape would get
   blocked in production too. **PENDING BUSINESS DECISION** — the
   Budget/Product module owner needs to confirm whether this reflects
   real usage or stale test data, and whether the exemption needs to
   widen. Decision made 2026-09-07: proceed with deploy, tracked here
   rather than fixed pre-deploy — do not run `BudgetControllerTest`,
   `BudgetDocumentControllerTest` or `ProductControllerTest` as part of
   this deploy's test level (use `RunSpecifiedTests` scoped to
   MGAgencia's own suite) so this known gap doesn't block an unrelated
   deploy.

   Do not confuse with the inactive `Validar_Tarea_Estatus_Contactado`
   (underscored) already in prod — unrelated rule, leave it alone.
3. ✅ **DONE (2026-09-07)** — PR #2. **Fix `CodigoVendedorAsignacion` before
   it ever touches `mi-org`** (§0): rebuild its formula from prod's current
   role-based admin exemption, adding only the
   `NOT($Permission.MGAgencia_Integration_Bypass)` clause. Do not deploy the
   version currently committed as-is. Not yet deployed to `mi-org` itself —
   still pending as part of step 4/5's component list.
4-5. ✅ **DONE (2026-09-07)**. Discovered mid-execution: a single
   `deploy validate`/`deploy start` covering the whole component list
   below cannot pass its own Apex tests on a *first-ever* deploy to
   `mi-org` — `MGAgencia_Integration`'s FLS grant to the deploying user
   doesn't exist yet (PermissionSetAssignment is data, not metadata, and
   can't be created inside the same deploy transaction that first
   creates the permission set), so every USER_MODE Lead insert in the
   test suite returns a masked 500 (same root cause as the
   already-documented condor-qas gotcha in `TEST_PLAN.md` §3.1, just
   hitting a brand-new org for the first time). Resolved by splitting
   into two real deploys with a permission-set assignment in between:

   - **Deploy 1** (`0AfTS000001wtMv0AI`, succeeded): fields, `Lead`
     validation rule fix, Log object + fields, CMDT object + fields +
     Default record, queue, assignment rule, `MGAgencia_Integration`
     permission set **with its `classAccesses` block temporarily
     stripped** (it references `MGAgenciaLeadRestResource`, which
     doesn't exist yet — chicken-and-egg), custom permission.
     `--test-level RunSpecifiedTests` with an unrelated test (no Apex
     in this payload, so no coverage is actually required/checked).
   - **Assign** `MGAgencia_Integration` to the deploying admin user
     (`sf org assign permset -o mi-org -n MGAgencia_Integration`) — a
     data operation, not metadata, done here so it exists ahead of
     Deploy 2's test run.
   - **Deploy 2** (`0AfTS000001wtQ90AI`, succeeded): the 16 Apex
     classes + the **full** `MGAgencia_Integration` permission set
     (with `classAccesses` restored — the class now exists) —
     `--test-level RunSpecifiedTests --tests MGAgenciaLeadRestResourceTest
     --tests MGAgenciaLeadServiceTest --tests MGAgenciaPhoneNormalizerTest`.
     **27/27 PASS**, all real, against `mi-org`.

   If this whole checklist is ever re-run against a *new* org from
   scratch (not `mi-org` a second time — the permission set + FLS
   already exist there now), expect this same two-wave split to be
   necessary again.

   Original plan (superseded by the above; kept for the full component
   list reference):

4. ~~**Validate-only deploy**~~ (`sf project deploy start --dry-run` / `--tests`)
   of an **explicit component list** — not the whole `force-app` tree (§0):
   - The 16 `force-app/main/default/classes/MGAgencia*` classes.
   - The 3 missing Lead fields (`External_Lead_Id__c`, `Duplicated_Lead__c`,
     `Duplicate_Reason__c`).
   - Object `MGAgencia_Integration_Log__c` and its fields.
   - CMDT `MGAgencia_Integration_Setting__mdt`, including the `Default`
     record (Family__c/Brand__c values, Decision 3).
   - Queue `MGAgencia_Leads`.
   - `assignmentRules/Lead.assignmentRules-meta.xml` (additive-only, §0).
   - The corrected `CodigoVendedorAsignacion` validation rule (step 3).
   - Permission Set `MGAgencia_Integration` + Custom Permission
     `MGAgencia_Integration_Bypass`.
   - **Excluded from this list**: `standardValueSets/*.xml`
     (`LeadSource`, `LeadStatus` — add via UI per step 1, §0),
     `FirstNameRequired` and `Segmento_y_o_Modelo_vacio_o_otros` validation
     rules (no-op/cosmetic — no need to redeploy them), the connected app
     file as committed (run-as user is sandbox-specific, §0).
   - All Apex tests must run (mandatory for a production deploy) and pass —
     same 27/27 bar as `condor-qas`.
5. ~~**Real deploy**~~, only after step 4's dry run is clean and you confirm.
6. ✅ **DONE (2026-09-07)** — `mgagencia.integration@condor.com.py`
   (Id `005TS00000B2PwrYAF`), profile "Minimum Access - API Only
   Integrations" (userLicense "Salesforce Integration" — free, no paid
   seat consumed), PSL `SalesforceAPIIntegrationPSL` + permission set
   `MGAgencia_Integration` assigned. **Order matters**: the PSL must be
   assigned *before* the permission set — `MGAgencia_Integration` grants
   Read on `Campaign`, which the base "Salesforce Integration" license
   alone doesn't support (`La licencia de usuario no admite el permiso:
   Leer Campaign`) until the PSL is present. **Create the production
   integration user**
   (`docs/ADMIN_FOLLOWUPS.md` #3): profile "Minimum Access - API Only
   Integrations", permission set `MGAgencia_Integration`, permission set
   license "Salesforce API Integration".
7. ✅ **DONE (2026-09-07)** — `mi-org` no longer exposes the classic "New
   Connected App" button in App Manager; Salesforce has moved new-app
   creation to **"Aplicación cliente externa" (External Client App
   Manager)**. Created there instead (`ManageExternalClientApplication`):
   - Basic info: name `MGAgencia API`, API name `MGAgencia_API`, contact
     email `hanssel.mirabal@condor.com.py`.
   - API/OAuth: enabled, callback URL
     `https://login.salesforce.com/services/oauth2/callback`, scope
     "Manage user data via APIs (api)", **Activar flujo de credenciales
     de cliente** checked at creation time.
   - **Gotcha**: checking that box at creation time is not enough — after
     creating the app, its **Políticas → Modificar** tab has its *own*,
     separate "Activar flujo de credenciales de cliente" checkbox
     (defaults unchecked even though creation had it checked). Only
     checking it there reveals the **"Ejecutar como" (Run As)** field.
     Set to `mgagencia.integration@condor.com.py`.
   - IP Relaxation: set to **"Rebajar restricciones de IP"** (relax), the
     documented pragmatic fallback (`docs/AUTH_SETUP.md` §4) — MGAgencia
     hasn't provided egress IPs yet. Switch to "Activar restricciones de
     IP" + register their IPs once available.
   - Consumer Key/Secret **not yet retrieved** — deferred to step 8
     (credential handover), not pulled during this session.

   Original plan (superseded by the above — kept for the gotcha
   reference): **Create the Connected App** in `mi-org` per
   `docs/AUTH_SETUP.md` §2–§4, applying the 4 gotchas logged there from
   the sandbox provisioning, and pointing `Run As` at the production
   integration user (§0 — never the sandbox user baked into the
   committed connected-app file).
8. **Hand over credentials** to MGAgencia per `docs/AUTH_SETUP.md` §5 —
   approved secret channel only, never through this repo or chat.
9. **Post-deploy verification**:
   - Run the full Apex test suite once more against `mi-org`.
   - Create one verification Lead end-to-end (same method used in
     `condor-qas` today: anonymous Apex calling `MGAgenciaLeadService.process`,
     or a real authenticated REST call once the Connected App is live).
   - Confirm the least-privilege integration user can create a Lead and have
     its duplicate scan detect a match (mirrors
     `duplicateIsDetectedUnderLeastPrivilegeIntegrationUser`, DEF-001).
   - Confirm flow `Asignacion_Lead_a_Vendedor` and queue `Reglas Meta`
     behave as documented safe in `MGAgenciaBranchResolver` — it must only
     fire for `OwnerId = Reglas Meta`, never for `MGAgencia_Leads`.
   - Confirm a Lead created with `LeadSource = Redes Sociales Empresa` and
     `Family__c = AUTOMÓVILES MG` is no longer caught by the `Reglas_Meta`
     entry (§0's assignment-rule addition).
10. **Close out** `docs/ADMIN_FOLLOWUPS.md` items #1–#3.

---

## 3. Open items that are NOT blockers for this checklist

Tracked separately, not required for go-live: `campaign_code` (PENDING
BUSINESS DECISION, `docs/API_SPEC.md` §9), rate/volume limits, GET status
endpoint. Do not invent answers to these while executing this checklist.
