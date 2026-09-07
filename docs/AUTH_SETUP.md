# AUTH_SETUP — Admin runbook: OAuth 2.0 Client Credentials for MGAgencia

Status: **Decision 8 approved (2026-08-31)** — see `docs/DECISIONS.md`.
Audience: Salesforce administrator. These steps require UI access and handling
of a consumer secret, which must never pass through automation, logs, or files
in this repository.

## 1. Target architecture

- Grant type: **OAuth 2.0 Client Credentials** on a dedicated Connected App.
- The app executes **run-as** the least-privilege integration user
  (sandbox: `mgagencia.integration@condor.com.py.qas.mga`, profile
  "Minimum Access - API Only Integrations", permission set
  `MGAgencia_Integration`, permission set license "Salesforce API Integration").
- MGAgencia receives only `client_id` + `client_secret`; no Salesforce password,
  no security token, no session reuse.
- Sandbox E2E (Phase 7) used SOAP username/password session auth as an
  interim, because the consumer secret can only be revealed/handled by a
  human admin in the UI. **Production integration REQUIRES this Connected
  App — SOAP session auth is not the production mechanism.**

## 2. Create the Connected App (UI)

1. Setup → App Manager → **New Connected App**.
2. Name: `MGAgencia Lead Integration`. Contact email: the admin's.
3. Enable **OAuth Settings**:
   - Callback URL: `https://login.salesforce.com/services/oauth2/callback`
     (required by the form; unused by client credentials).
   - Scopes: **Perform requests at any time (refresh_token, offline_access)**
     is NOT needed; select only **Access the Salesforce API Platform (sfap_api)**
     is NOT needed either — select **Manage user data via APIs (api)**.
4. Check **Enable Client Credentials Flow**.
5. Save. Wait ~10 minutes for propagation.

## 3. Set the run-as user

1. App Manager → the app → **Manage** → **Edit Policies**.
2. Permitted Users: *Admin approved users are pre-authorized* is not required
   for client credentials; under **Client Credentials Flow**, set
   **Run As**: the integration user
   (`mgagencia.integration@condor.com.py.qas.mga` in sandbox; the equivalent
   production integration user, to be created with the same profile +
   permission set, in production).
3. The run-as user must have **API Enabled** (the chosen profile has it) and
   must hold the `MGAgencia_Integration` permission set and the
   "Salesforce API Integration" permission set license.

## 4. IP restrictions — choose one

- **Recommended**: IP Relaxation = *Enforce IP restrictions*, and register
  MGAgencia's egress IPs as profile login IP ranges on the integration user's
  profile (do NOT widen org-wide Trusted IP Ranges for this).
- Pragmatic fallback while MGAgencia cannot provide stable IPs:
  IP Relaxation = *Relax IP restrictions* on this Connected App only.
- Record the choice in `docs/DECISIONS.md` when made.

## 5. Secret handling rules

- The consumer key/secret are read from App Manager → the app → **Manage
  Consumer Details** (identity verification required).
- Deliver to MGAgencia over an approved secret channel (password manager share
  or equivalent). **Never** email, chat, commit, log, or paste into tickets.
- Rotate: App Manager → Manage Consumer Details → rotate secret; coordinate
  a cutover window with MGAgencia.
- Revoke: disable the Connected App or rotate the secret; sessions die with
  token expiry.

## 6. Token endpoint

| Environment | Token URL |
|---|---|
| Sandbox (`condor-qas`) | `https://test.salesforce.com/services/oauth2/token` (or the sandbox My Domain: `https://<MyDomain>--qas.sandbox.my.salesforce.com/services/oauth2/token`) |
| Production | `https://<MyDomain>.my.salesforce.com/services/oauth2/token` (prefer My Domain over `login.salesforce.com`) |

## 7. curl example for MGAgencia

```bash
# 1. Get a token (client credentials)
curl -s -X POST "https://<MyDomain>.my.salesforce.com/services/oauth2/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=<CONSUMER_KEY>" \
  -d "client_secret=<CONSUMER_SECRET>"
# → { "access_token": "...", "instance_url": "https://<MyDomain>.my.salesforce.com", ... }

# 2. Create a Lead
curl -s -X POST "<instance_url>/services/apexrest/mgagencia/v1/leads" \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "external_lead_id": "neb-2026-0000123",
    "first_name": "Maria",
    "last_name": "Gonzalez",
    "phone": "0981123456",
    "email": "maria.gonzalez@example.com",
    "branch_code": "ASUNCION"
  }'
```

Tokens expire per the org session policy; MGAgencia must request a new token on
`401` and retry, not cache indefinitely.

## 8. Production checklist

- [x] Create the production integration user (2026-09-07) —
      `mgagencia.integration@condor.com.py`, same profile/PSL as sandbox.
- [x] Deploy the MGAgencia metadata package to production (2026-09-07,
      two-wave deploy — see `docs/PRODUCTION_DEPLOYMENT_CHECKLIST.md` §2
      steps 4-5).
- [x] Create the Connected App per §2–§4 in production (2026-09-07) — with
      one platform change: `mi-org` no longer has the classic "New
      Connected App" button; use **App Manager → Nueva aplicación
      cliente externa** instead. See gotcha #5 below.
- [ ] Hand over credentials per §5.
- [ ] Complete the admin follow-ups in `docs/ADMIN_FOLLOWUPS.md`.

## 9. Gotcha #5 (production, 2026-09-07) — External Client App replaces classic Connected App creation

`mi-org`'s App Manager only offers "Nueva aplicación Lightning" and "Nueva
aplicación cliente externa" — no plain "New Connected App" button. Salesforce
has moved new-app creation to the External Client App Manager
(`ManageExternalClientApplication`). It still supports Client Credentials
Flow, but with a UI quirk: the "Activar flujo de credenciales de cliente"
checkbox on the **creation** form is separate from the one under the app's
**Políticas → Modificar** tab. Checking it at creation time is not enough —
go back into Políticas → Modificar and check it there too; only then does
the **"Ejecutar como" (Run As)** field appear to set the run-as user.
Existing Connected Apps (pre-dating this change) remain manageable under
Setup → App Manager → Gestionar aplicaciones conectadas, but that page has
no "New" option — it's read/manage-only for already-existing apps.

## Sandbox provisioning status (2026-09-01)

- Connected App `MGAgencia API` is LIVE in `condor-qas`: client credentials flow enabled, run-as user `mgagencia.integration@condor.com.py.qas.mga`, permitted users = admin pre-authorized via permission set "Integración MGAgencia".
- End-to-end verified: token from `https://condorsaci--qas.sandbox.my.salesforce.com/services/oauth2/token` (grant_type=client_credentials) → POST lead → 201.
- Gotchas learned (apply to production provisioning):
  1. The client-credentials TOKEN endpoint must be the org's My Domain URL — `test.salesforce.com` returns `invalid_grant: request not supported on this domain`.
  2. The client-credentials run-as user CANNOT be set via Metadata API — set it in Setup UI (Connected App → Edit Policies → Client Credentials Flow → Run As).
  3. `ConnectedApp.permissionSetName` in metadata expects the permission set LABEL ("Integración MGAgencia"), not the API name.
  4. With "admin approved users are pre-authorized", the run-as user must hold a permission set/profile associated to the app, or the token call fails with `invalid_app_access`.
- The consumer secret was delivered out-of-band; it is NOT stored in this repository (the committed ConnectedApp XML is sanitized).
