# TEST_PLAN

Status: **EXECUTED — Phase 6** (2026-08-31). Target org: sandbox `condor-qas`.
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
- Phase 7 (sandbox end-to-end over HTTPS with a real integration user) is
  still pending; these results cover Apex-level behavior.
