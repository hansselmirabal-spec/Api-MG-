# TEST_PLAN

Status: **EXECUTED — Phases 6 and 7** (2026-08-31 / 2026-09-01). Target org: sandbox `condor-qas`.
Test classes: `NebulaLeadRestResourceTest`, `NebulaLeadServiceTest`
(`force-app/main/default/classes/`). Behavior-first: every scenario asserts
contract outcomes (status code, response schema, Lead/log persistence), not
coverage alone. No `SeeAllData`; test data is isolated per method.

Run command:

```
sf apex run test --tests NebulaLeadRestResourceTest --tests NebulaLeadServiceTest \
  -o condor-qas --result-format human --code-coverage --wait 20
```

## 1. Executed scenario matrix (run 707TH0000263hCu — 15/15 PASS)

| # | Scenario | Test method | Expected | Result |
|---|---|---|---|---|
| 1 | Successful creation: 201, response schema, UUID `integration_id`, Lead with configured values (record type `Fisica`, `Family__c` AUTOMÓVILES MG, `Brand__c` MG, Status `Formulario Nebüla`, LeadSource `Nebüla`, branch resolved), log `CREATED` linked to Lead | `createsLeadWithConfiguredValuesAndLogsIt` | 201 | PASS |
| 2 | Missing `first_name` AND `phone`: all problems aggregated in one 422 (`REQUIRED` × 2), no Lead, log `VALIDATION_FAILED` | `missingRequiredFieldsReturnsAllErrorsAggregated` | 422 | PASS |
| 3 | Invalid email format → `INVALID_FORMAT` | `invalidEmailFormatReturns422` | 422 | PASS |
| 4 | Unknown `branch_code` → `UNKNOWN_VALUE`, no Lead | `unknownBranchCodeReturns422UnknownValue` | 422 | PASS |
| 5 | Valid `branch_code` CIUDAD_DEL_ESTE → `Nearest_Branch__c` "CIUDAD DEL ESTE" | `validBranchCodeMapsToPicklistValue` | 201 | PASS |
| 6 | Malformed JSON body → `MALFORMED_REQUEST`, no `integration_id`, no Lead, log `ERROR`/400 | `malformedJsonReturns400` | 400 | PASS |
| 7 | Missing/empty body → `MALFORMED_REQUEST` | `emptyBodyReturns400` | 400 | PASS |
| 8 | Unknown JSON properties (`campaign_code`, `interest_model`, arbitrary) are ignored, not rejected | `unknownJsonPropertiesAreIgnored` | 201 | PASS |
| 9 | Duplicate by phone: created + `Duplicated_Lead__c` true + reason `MOBILE_PHONE_MATCH` + response `duplicated: true` + log flag | `duplicateByPhoneIsCreatedAndFlagged` | 201 | PASS |
| 10 | Duplicate by email (case-insensitive) → `EMAIL_MATCH` | `duplicateByEmailIsCreatedAndFlagged` | 201 | PASS |
| 11 | Duplicate by `external_lead_id` → `EXTERNAL_LEAD_ID_MATCH` | `duplicateByExternalLeadIdIsCreatedAndFlagged` | 201 | PASS |
| 12 | Different phone/email/external id → not flagged, no reason stored | `differentContactDataIsNotFlaggedAsDuplicate` | 201 | PASS |
| 13 | DML failure (test seam): generic 500, no Lead, log `ERROR` with internal detail; response leaks no exception text | `dmlFailureReturns500AndLogsError` | 500 | PASS |
| 14 | Missing/inactive CMDT configuration (test seam): generic 500, log `ERROR` keeps exception type internally | `missingConfigurationReturns500WithGenericMessage` | 500 | PASS |
| 15 | Success response contains only contract fields and never a Salesforce Record ID | `successResponseNeverExposesSalesforceIds` | 201 | PASS |

Not covered by Apex tests (platform-level, by design): 401/403 — handled by
OAuth/permission set before Apex runs. GET status endpoint, `campaign_code`,
`interest_model`: NOT implemented (PENDING BUSINESS DECISION).

## 2. Code coverage (integration classes)

| Class | Coverage |
|---|---|
| `NebulaLeadRestResource` | 100% |
| `NebulaLeadService` | 97% |
| `NebulaLeadValidator` | 93% |
| `NebulaLeadRequest` | 90% |
| `NebulaLeadResponse` | 100% |
| `NebulaBranchResolver` | 100% |
| `NebulaDuplicateEvaluator` | 94% |
| `NebulaIntegrationLogger` | 100% |
| Exception classes (empty bodies) | 0% — no executable lines |

## 3. Org-automation interference found (and how it was handled)

Tests run against real org automation (no mocking of flows/triggers). Findings:

1. **FLS after Metadata API deploy**: deployed fields carry no field-level
   security for any profile — even the admin gets none. All USER_MODE DML
   failed until the `Nebula_Integration` permission set (which carries the
   FLS) was assigned to the running user. Any user calling the API (or
   running these tests) needs that permission set.
2. **VR `ValidarTareaEstadoContactado`** exempts `Formulario Meta` /
   `Prospecto` but not the new `Formulario Nebüla` status, blocking every
   API insert. Handled in Apex by setting `Estatus__c = 'No contactado'`
   (factually correct for a fresh advertising lead, and the state the rule
   itself treats as pre-contact). **Follow-up for the Salesforce admin**:
   add `NOT(ISPICKVAL(Status, 'Formulario Nebüla'))` to the rule, mirroring
   the Meta exemption — otherwise later manual edits of an uncontacted
   Nebüla lead may still trip the rule once `Estatus__c` changes.
3. **Flow "Crear Tarea si No Contactado"** creates a Task owned by the
   Lead's owner. With ownership routed to the `Nebula_Leads` queue, inserts
   failed with `Queue not associated with this SObject type`. Fixed by
   adding `Task` to the queue's supported objects (our Phase 4 component).
4. **Flow `DatosInicialesProspecto`** upper-cases names after insert —
   tests compare `FirstName` case-insensitively. Owner may be re-routed by
   automation, so no test asserts an exact `OwnerId`.

## 4. Environment notes

- Deploys validated with `--dry-run` first; scoped `--source-dir` deploys.
- The org's Lead automation (LeadTrigger, TaskTrigger, several flows) runs
  inside every test transaction; success-path tests take 1–9 s each.
- Phase 7 (sandbox end-to-end over HTTPS) executed 2026-08-31/2026-09-01 —
  see §5.

## 5. Phase 7 — E2E over HTTPS (executed) + phone normalization

### 5.1 Phone normalization (deployed)

`NebulaPhoneNormalizer` replicates the org flow `DatosInicialesProspecto`
("Limpiar Teléfono (Siempre)") exactly: strip `+`, spaces, `-`, `(`, `)`;
leading `0` → `595` + rest; anything else passes through unchanged
(documented — foreign/odd input is never rewritten). Applied in
`NebulaLeadService` BEFORE duplicate matching and BEFORE storing
`MobilePhone`. New tests: `NebulaPhoneNormalizerTest` (5 unit tests) and
`NebulaLeadServiceTest.localFormatPhoneIsNormalizedAndMatchesExistingLead`.
Full suite after deploy: run `707TH0000263Pmg` — **21/21 PASS**, coverage:
`NebulaPhoneNormalizer` 100%, all other integration classes unchanged
(90–100%).

### 5.2 E2E matrix — real REST over HTTPS against `condor-qas`

Executed with curl against
`https://condorsaci--qas.sandbox.my.salesforce.com/services/apexrest/nebula/v1/leads`.
Auth note: the least-privilege integration user could not SOAP-login from the
test IP (`LOGIN_MUST_USE_SECURITY_TOKEN`; adding a trusted IP range / reading
the token email / deploying a temp Connected App all require an admin — see
`docs/ADMIN_FOLLOWUPS.md` §4), so the wire tests ran with an admin API
session. The integration-user permission boundary is verified by
configuration (§5.3) and by the Apex suite running under the permission set.

| # | Scenario | Request | HTTP | Response | Result |
|---|---|---|---|---|---|
| a | Valid lead | full valid body, phone `595…`, `branch_code` ASUNCION | 201 | `LEAD_CREATED`, UUID `integration_id`, `duplicated:false` | PASS |
| b | Same phone in `0971…` local format | same person, phone `0971…` | 201 | `LEAD_CREATED`, `duplicated:true`; Lead stored with `Duplicate_Reason__c = MOBILE_PHONE_MATCH` and normalized `595…` phone | PASS |
| c | Missing `first_name` and `phone` | only `last_name`, `email` | 422 | `VALIDATION_ERROR` with BOTH `REQUIRED` errors aggregated | PASS |
| d | Unknown `branch_code` | `branch_code: LUQUE` | 422 | `VALIDATION_ERROR`, `UNKNOWN_VALUE` on `branch_code` | PASS |
| e | Malformed JSON | `{not-json` | 400 | `MALFORMED_REQUEST` | PASS |
| f | No/invalid token | no `Authorization` header | 401 | platform `INVALID_SESSION_ID` (Apex never runs) | PASS |
| g | Authorized user without `Nebula_Integration` permission set | not executed live | 403 | verified-by-configuration: Apex class access to `NebulaLeadRestResource` is granted ONLY through the `Nebula_Integration` permission set; platform returns 403 for users without it | VERIFIED-BY-CONFIG |

SOQL verification of scenario a/b Leads: record type `Fisica`,
`Family__c = AUTOMÓVILES MG`, `Brand__c = MG`, `Status = Formulario Nebüla`,
`LeadSource = Nebüla`, `Nearest_Branch__c = ASUNCIÓN`, owner = queue
"Nebüla Leads" (assignment rule entry acted as designed; no other automation
re-routed the owner). Integration log records `CREATED`/201 linked to both
Leads; 422/400 attempts logged as `VALIDATION_FAILED`/`ERROR` with no Lead.

Cleanup: PENDING USER APPROVAL — the deletion commands (2 E2E Leads
`00QTH00000Spms52AB`, `00QTH00000Spmth2AB` and 10 E2E
`Nebula_Integration_Log__c` records created 2026-09-01) were blocked by the
local permission policy for destructive org DML. Run when approved:
`sf apex run` with `delete [SELECT Id FROM Nebula_Integration_Log__c WHERE
CreatedDate = 2026-09-01]; delete [SELECT Id FROM Lead WHERE
External_Lead_Id__c LIKE 'e2e-%-1788258717'];` against `condor-qas`.

### 5.3 Integration user (least privilege)

`nebula.integration@condor.com.py.qas.nebula` — profile
"Minimum Access - API Only Integrations" (license "Salesforce Integration" +
PSL "Salesforce API Integration"), permission set `Nebula_Integration`.
Verified by SOQL: `PermissionsModifyAllData = false`,
`PermissionsViewAllData = false`, `PermissionsAuthorApex = false`,
`PermissionsApiEnabled = true`; only assignments are the profile-owned
permission set and `Nebula_Integration`.
