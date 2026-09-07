# ADMIN_FOLLOWUPS — Salesforce admin actions pending for MGAgencia

Actions that require a human Salesforce administrator (UI access, org-wide
security, or secret handling). None are blockers for the Apex layer, which is
deployed and green in `condor-qas`; they are required for a clean production
cutover and for hardening the sandbox.

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

- **What**: production authentication (see `docs/AUTH_SETUP.md`).
- **Action**: create the Connected App, enable client credentials, set the
  run-as integration user, decide IP policy, and hand over the consumer
  secret over an approved channel. Automation must never touch the secret.
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
