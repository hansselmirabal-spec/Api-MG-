# ADMIN_FOLLOWUPS — Salesforce admin actions pending for Nebüla

Actions that require a human Salesforce administrator (UI access, org-wide
security, or secret handling). None are blockers for the Apex layer, which is
deployed and green in `condor-qas`; they are required for a clean production
cutover and for hardening the sandbox.

## 1. Validation rule `ValidarTareaEstadoContactado` exemption (carried from Phase 6)

- **What**: the VR exempts `Formulario Meta` / `Prospecto` but not the new
  `Formulario Nebüla` status, so it blocks API inserts. The API works around
  it today by setting `Estatus__c = 'No contactado'` (the factual pre-contact
  state), which the rule treats as valid.
- **Action**: add `NOT(ISPICKVAL(Status, 'Formulario Nebüla'))` to the rule,
  mirroring the Meta exemption. Otherwise a later manual edit of an
  uncontacted Nebüla lead may trip the rule once `Estatus__c` changes.
- **Priority**: medium (workaround holds for creation; risk is later edits).

## 2. OAuth 2.0 Client Credentials Connected App (Decision 8)

- **What**: production authentication (see `docs/AUTH_SETUP.md`).
- **Action**: create the Connected App, enable client credentials, set the
  run-as integration user, decide IP policy, and hand over the consumer
  secret over an approved channel. Automation must never touch the secret.
- **Priority**: high — required before Nebüla integrates against production.

## 3. Production integration user

- **What**: the sandbox user `nebula.integration@condor.com.py.qas.nebula`
  exists; production needs its equivalent.
- **Action**: create a production user with profile
  "Minimum Access - API Only Integrations", permission set
  `Nebula_Integration`, and permission set license "Salesforce API
  Integration". No admin permissions.
- **Priority**: high — required for production cutover.

## 4. Sandbox E2E network access (temporary, Phase 7)

- **What**: API-only users logging in over SOAP from an untrusted IP hit
  `LOGIN_MUST_USE_SECURITY_TOKEN`. The over-the-wire E2E needs either a temp
  org Trusted IP Range for the test IP, or the JWT/Connected App path.
- **Action**: if the E2E is re-run by hand, add the tester's IP to Trusted IP
  Ranges (Setup → Network Access) temporarily and remove it afterward, OR
  deploy the dedicated Connected App from `docs/AUTH_SETUP.md`.
- **Priority**: low — sandbox-only test enablement, not a product requirement.
