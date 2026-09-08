# ADMIN_FOLLOWUPS — Salesforce admin actions pending for MGAgencia

Actions that require a human Salesforce administrator (UI access, org-wide
security, or secret handling). None are blockers for the Apex layer, which is
deployed and green in `condor-qas`; they are required for a clean production
cutover and for hardening the sandbox.

**Status (2026-09-07):** items #1–#3 closed as part of the `mi-org`
production cutover (`docs/PRODUCTION_DEPLOYMENT_CHECKLIST.md` §2). The one
open sub-task is the manual credential handover under #2 — secret handling
is intentionally never automated. Item #4 is sandbox-only hardening, not
required for production go-live, and remains open at low priority.

## 1. Validation rule `ValidarTareaEstadoContactado` exemption (carried from Phase 6)

- **Status: MOOT (2026-09-07)** — Decision 2 was amended to reuse the
  existing `Formulario Meta` status instead of adding a new
  `Formulario MGAgencia` value (see `docs/DECISIONS.md`). The VR's existing
  `NOT(ISPICKVAL(Status, 'Formulario Meta'))` exemption already covers
  MGAgencia Leads directly — no rule edit needed. `mi-org`'s deployed copy of
  the rule (2026-09-07, checklist §2 step 2) still carries a dead
  `NOT(ISPICKVAL(Status, 'Formulario MGAgencia'))` clause referencing a value
  that will now never exist; harmless (evaluates to a no-op), optional
  cleanup only.
- **What (original, now superseded)**: the VR exempts `Formulario Meta` /
  `Prospecto` but not the new `Formulario MGAgencia` status, so it blocks API
  inserts. The API works around it today by setting
  `Estatus__c = 'No contactado'` (the factual pre-contact state), which the
  rule treats as valid.

## 2. OAuth 2.0 Client Credentials Connected App (Decision 8)

- **Status: DONE (2026-09-07)**, except the secret handover — Connected
  App `MGAgencia API` created in `mi-org` (via the External Client App
  Manager — see `docs/AUTH_SETUP.md` §9 gotcha #5), client credentials
  enabled, `Run As` set to `mgagencia.integration@condor.com.py`, IP
  Relaxation set to "Rebajar restricciones de IP" (MGAgencia hasn't
  shared egress IPs yet — revisit once they do). **Remaining**: pull the
  Consumer Key/Secret from Manage Consumer Details and hand it over
  through the approved secure channel — this step is manual by design
  and was not done in this session.
- **What (original)**: production authentication (see `docs/AUTH_SETUP.md`).
- **Priority**: high — required before MGAgencia integrates against production.

## 3. Production integration user

- **Status: DONE (2026-09-07)** — `mgagencia.integration@condor.com.py`
  (`005TS00000B2PwrYAF`), profile "Minimum Access - API Only
  Integrations", PSL `SalesforceAPIIntegrationPSL` and permission set
  `MGAgencia_Integration` assigned (PSL first — required for the
  permission set's `Campaign` read grant to apply). No admin
  permissions. See `docs/PRODUCTION_DEPLOYMENT_CHECKLIST.md` §2 step 6.
- **What (original)**: the sandbox user
  `mgagencia.integration@condor.com.py.qas.mga` exists; production
  needs its equivalent.

## 4. Sandbox E2E network access (temporary, Phase 7)

- **What**: API-only users logging in over SOAP from an untrusted IP hit
  `LOGIN_MUST_USE_SECURITY_TOKEN`. The over-the-wire E2E needs either a temp
  org Trusted IP Range for the test IP, or the JWT/Connected App path.
- **Action**: if the E2E is re-run by hand, add the tester's IP to Trusted IP
  Ranges (Setup → Network Access) temporarily and remove it afterward, OR
  deploy the dedicated Connected App from `docs/AUTH_SETUP.md`.
- **Priority**: low — sandbox-only test enablement, not a product requirement.

## 5. `Asignacion_Lead_a_Vendedor` flow breaks on MGAgencia Lead data (found + reverted, 2026-09-07)

- **What**: attempted routing MGAgencia Leads to the `Reglas_Meta` queue
  (to reuse the existing `Asignacion_Lead_a_Vendedor` distribution flow
  instead of leaving them in their own queue — see `docs/DECISIONS.md`
  Decision 1). Verified with a real (non-test) call in `condor-qas`: the
  flow's "Asignación Lead a Vendedor según Calendario" sub-flow throws
  `INVALID_CROSS_REFERENCE_KEY` / `CANNOT_EXECUTE_FLOW_TRIGGER` on an
  MGAgencia-created Lead — the insert fails outright (500). **Reverted**
  in `condor-qas` and in the repo; MGAgencia Leads still route to
  `MGAgencia_Leads` as originally designed. Never attempted in `mi-org`.
- **Root cause narrowed down (2026-09-07)**: the flow's "Calendario
  Asignaciones" step (`Calendario_de_Asignaciones__c` lookup) filters on
  `Sucursal__c = $Record.Sucursal_Seleccionada_Meta__c` (exact text match
  against the Lead's branch label) restricted to shifts currently active
  (`Fecha_Inicio_Guardia__c`/`Fecha_Fin_Guardia__c` bracket `now()`).
  Checked live in `condor-qas`: the only 2 active shifts at the time of
  testing had `Sucursal__c = "pre-calificacion"` — none for a real branch
  (`Asunción`, `Ciudad del Este`, etc.). With no matching calendar row,
  the lookup comes back empty (`assignNullValuesIfNoRecordsFound = false`,
  so the flow variable stays unset rather than explicitly null), which
  cascades into the next lookup (`Vendedor_Producto`, filtered on
  `ProductSeller__c.OwnerId = Calendario_Asignaciones.Vendedor__c`) also
  coming back empty, and ultimately an invalid Owner reference on the
  Lead update. **This isn't MGAgencia-specific** — any Lead assigned to a
  real branch outside an active branch-level shift window would hit the
  same wall; the flow's "Feriado"/"Fuera de Horario" branches apparently
  don't cover "no active shift configured for this Sucursal at all."
- **Action**: a Salesforce admin/flow owner needs to open
  `Asignacion_Lead_a_Vendedor` in Flow Builder, confirm branch-level shift
  coverage (calendar rows with `Sucursal__c` = a real branch name,
  matching `Sucursal_Seleccionada_Meta__c`'s exact label casing) exists at
  all times shifts should be covered, and add a safe fallback path (e.g.
  leave the Lead owned by the queue) when `Calendario_Asignaciones` finds
  nothing — before this routing change can be retried. Out of scope for
  MGAgencia's own Apex layer — this is a bug/gap in shared org automation.
- **Priority**: medium — only matters if/when Decision 1's queue routing
  is revisited; the current `MGAgencia_Leads` queue works correctly today.
