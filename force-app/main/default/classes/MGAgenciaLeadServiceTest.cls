/**
 * @description Behavior-first tests for MGAgenciaLeadService orchestration: duplicate
 *              create-and-flag rule (Decision 4), configuration failure path, DML failure
 *              path, and the guarantee that responses never leak Salesforce IDs or raw
 *              exception text. Uses the service test seams (configOverride,
 *              simulateDmlFailure) for the 500 paths.
 */
@IsTest
private class MGAgenciaLeadServiceTest {
    private static MGAgenciaLeadRequest buildRequest(String phone, String email, String externalId) {
        MGAgenciaLeadRequest request = new MGAgenciaLeadRequest();
        request.first_name = 'Carlos';
        request.last_name = 'Benitez';
        request.phone = phone;
        request.email = email;
        request.external_lead_id = externalId;
        return request;
    }

    @IsTest
    static void duplicateByPhoneIsCreatedAndFlagged() {
        MGAgenciaLeadService.process(buildRequest('595982222001', 'seed.phone@example.com', 'neb-svc-p1'));

        Test.startTest();
        MGAgenciaLeadService.Result result = MGAgenciaLeadService.process(
            buildRequest('595982222001', 'other.phone@example.com', 'neb-svc-p2'));
        Test.stopTest();

        System.assertEquals(201, result.statusCode, 'Duplicates are still created (201)');
        System.assertEquals(true, result.response.duplicated, 'Response reports duplicated=true');
        Lead duplicate = [SELECT Duplicated_Lead__c, Duplicate_Reason__c FROM Lead
                          WHERE External_Lead_Id__c = 'neb-svc-p2'];
        System.assertEquals(true, duplicate.Duplicated_Lead__c, 'Lead flagged as duplicate');
        System.assert(duplicate.Duplicate_Reason__c.contains('MOBILE_PHONE_MATCH'),
            'Reason records the phone signal, got: ' + duplicate.Duplicate_Reason__c);
        System.assertEquals(1, [SELECT COUNT() FROM MGAgencia_Integration_Log__c
                                WHERE Duplicated__c = true AND Status__c = 'CREATED'],
            'Duplicate creation logged with duplicate flag');
    }

    @IsTest
    static void duplicateByEmailIsCreatedAndFlagged() {
        MGAgenciaLeadService.process(buildRequest('595982222002', 'same.email@example.com', 'neb-svc-e1'));

        Test.startTest();
        MGAgenciaLeadService.Result result = MGAgenciaLeadService.process(
            buildRequest('595982222003', 'SAME.EMAIL@EXAMPLE.COM', 'neb-svc-e2'));
        Test.stopTest();

        System.assertEquals(201, result.statusCode, 'Created');
        System.assertEquals(true, result.response.duplicated, 'duplicated=true');
        Lead duplicate = [SELECT Duplicate_Reason__c FROM Lead WHERE External_Lead_Id__c = 'neb-svc-e2'];
        System.assert(duplicate.Duplicate_Reason__c.contains('EMAIL_MATCH'),
            'Reason records the email signal, got: ' + duplicate.Duplicate_Reason__c);
    }

    @IsTest
    static void duplicateByExternalLeadIdIsCreatedAndFlagged() {
        MGAgenciaLeadService.process(buildRequest('595982222004', 'first.ext@example.com', 'neb-svc-x1'));

        Test.startTest();
        MGAgenciaLeadService.Result result = MGAgenciaLeadService.process(
            buildRequest('595982222005', 'second.ext@example.com', 'neb-svc-x1'));
        Test.stopTest();

        System.assertEquals(201, result.statusCode, 'Created');
        System.assertEquals(true, result.response.duplicated, 'duplicated=true');
        List<Lead> flagged = [SELECT Duplicate_Reason__c FROM Lead
                              WHERE External_Lead_Id__c = 'neb-svc-x1' AND Duplicated_Lead__c = true];
        System.assertEquals(1, flagged.size(), 'Second submission flagged');
        System.assert(flagged[0].Duplicate_Reason__c.contains('EXTERNAL_LEAD_ID_MATCH'),
            'Reason records the external id signal, got: ' + flagged[0].Duplicate_Reason__c);
    }

    @IsTest
    static void differentContactDataIsNotFlaggedAsDuplicate() {
        MGAgenciaLeadService.process(buildRequest('595982222006', 'one.person@example.com', 'neb-svc-n1'));

        Test.startTest();
        MGAgenciaLeadService.Result result = MGAgenciaLeadService.process(
            buildRequest('595982222007', 'another.person@example.com', 'neb-svc-n2'));
        Test.stopTest();

        System.assertEquals(201, result.statusCode, 'Created');
        System.assertEquals(false, result.response.duplicated, 'duplicated=false');
        Lead created = [SELECT Duplicated_Lead__c, Duplicate_Reason__c FROM Lead
                        WHERE External_Lead_Id__c = 'neb-svc-n2'];
        System.assertEquals(false, created.Duplicated_Lead__c, 'Not flagged');
        System.assertEquals(null, created.Duplicate_Reason__c, 'No duplicate reason stored');
    }

    @IsTest
    static void missingConfigurationReturns500WithGenericMessage() {
        MGAgenciaLeadService.configOverride = new List<MGAgencia_Integration_Setting__mdt>();

        Test.startTest();
        MGAgenciaLeadService.Result result = MGAgenciaLeadService.process(
            buildRequest('595982222008', null, 'neb-svc-cfg'));
        Test.stopTest();

        System.assertEquals(500, result.statusCode, 'Missing configuration returns 500');
        System.assertEquals('INTERNAL_ERROR', result.response.code, 'Generic error code');
        String serialized = JSON.serialize(result.response, true);
        System.assert(!serialized.contains('MGAgenciaConfigurationException'),
            'Response must not leak exception type');
        System.assert(!serialized.containsIgnoreCase('metadata'),
            'Response must not leak configuration detail');
        System.assertEquals(0, [SELECT COUNT() FROM Lead], 'No Lead created');
        List<MGAgencia_Integration_Log__c> logs = [SELECT Error_Detail__c FROM MGAgencia_Integration_Log__c
                                                WHERE Status__c = 'ERROR' AND Response_Code__c = 500];
        System.assertEquals(1, logs.size(), 'Configuration failure logged as ERROR');
        System.assert(logs[0].Error_Detail__c.contains('MGAgenciaConfigurationException'),
            'Internal log keeps the exception type for diagnosis');
    }

    @IsTest
    static void dmlFailureReturns500AndLogsError() {
        MGAgenciaLeadService.simulateDmlFailure = true;

        Test.startTest();
        MGAgenciaLeadService.Result result = MGAgenciaLeadService.process(
            buildRequest('595982222009', 'dml.failure@example.com', 'neb-svc-dml'));
        Test.stopTest();

        System.assertEquals(500, result.statusCode, 'DML failure returns 500');
        System.assertEquals('INTERNAL_ERROR', result.response.code, 'Generic error code');
        String serialized = JSON.serialize(result.response, true);
        System.assert(!serialized.contains('Simulated'), 'Response must not leak exception message');
        System.assertEquals(0, [SELECT COUNT() FROM Lead], 'No Lead persisted');
        List<MGAgencia_Integration_Log__c> logs = [SELECT Error_Detail__c, Lead__c
                                                FROM MGAgencia_Integration_Log__c
                                                WHERE Status__c = 'ERROR' AND Response_Code__c = 500];
        System.assertEquals(1, logs.size(), 'DML failure logged as ERROR');
        System.assertEquals(null, logs[0].Lead__c, 'No Lead reference on failed request');
        System.assert(logs[0].Error_Detail__c.contains('Simulated DML failure'),
            'Internal log keeps the sanitized detail (type + message)');
    }

    @IsTest
    static void successResponseNeverExposesSalesforceIds() {
        Test.startTest();
        MGAgenciaLeadService.Result result = MGAgenciaLeadService.process(
            buildRequest('595982222010', 'safe.response@example.com', 'neb-svc-safe'));
        Test.stopTest();

        System.assertEquals(201, result.statusCode, 'Created');
        Lead created = [SELECT Id FROM Lead WHERE External_Lead_Id__c = 'neb-svc-safe'];
        String serialized = JSON.serialize(result.response, true);
        System.assert(!serialized.contains(created.Id), 'Response must not contain the Lead Id');
        System.assert(!serialized.contains(String.valueOf(created.Id).substring(0, 15)),
            'Response must not contain the 15-char Lead Id either');
        Set<String> allowedKeys = new Set<String>{ 'code', 'status', 'message', 'integration_id', 'duplicated' };
        Map<String, Object> asMap = (Map<String, Object>) JSON.deserializeUntyped(serialized);
        System.assert(allowedKeys.containsAll(asMap.keySet()),
            'Success response only carries contract fields, got: ' + asMap.keySet());
    }
    @IsTest
    static void localFormatPhoneIsNormalizedAndMatchesExistingLead() {
        // Same person: first submission already in org format, resubmission in local 0-format.
        MGAgenciaLeadService.process(buildRequest('595981123456', 'norm.person@example.com', 'neb-svc-norm1'));

        Test.startTest();
        MGAgenciaLeadService.Result result = MGAgenciaLeadService.process(
            buildRequest('0981123456', 'other.norm@example.com', 'neb-svc-norm2'));
        Test.stopTest();

        System.assertEquals(201, result.statusCode, 'Created');
        System.assertEquals(true, result.response.duplicated,
            '0981123456 must match stored 595981123456 after normalization');
        Lead duplicate = [SELECT MobilePhone, Duplicate_Reason__c FROM Lead
                          WHERE External_Lead_Id__c = 'neb-svc-norm2'];
        System.assertEquals('595981123456', duplicate.MobilePhone,
            'Stored MobilePhone is normalized to the org convention before insert');
        System.assert(duplicate.Duplicate_Reason__c.contains('MOBILE_PHONE_MATCH'),
            'Reason records the phone signal, got: ' + duplicate.Duplicate_Reason__c);
    }

    /**
     * DEF-001 regression: under the real least-privilege integration profile
     * ("Minimum Access - API Only Integrations" + MGAgencia_Integration permission set),
     * created Leads end up owned by the MQL queue (Decision 1, amended 2026-09-08 —
     * insertLead targets Reglas_Meta directly, then the org's own Estatus__c = 'Nuevo'
     * handling reassigns to MQL), which the integration user is NOT a member of. A
     * sharing-enforced duplicate scan therefore sees no prior Leads and silently reports
     * duplicated=false. The scan must run in system mode so duplicates are detected
     * org-wide regardless of record visibility — independent of which queue owns the Lead.
     */
    @IsTest
    static void duplicateIsDetectedUnderLeastPrivilegeIntegrationUser() {
        // Same API-only profile as the real integration user; fall back to any
        // API-only (Salesforce Integration license) profile if the exact name changes.
        List<Profile> profiles = [SELECT Id FROM Profile
                                  WHERE Name = 'Minimum Access - API Only Integrations' LIMIT 1];
        if (profiles.isEmpty()) {
            profiles = [SELECT Id FROM Profile
                        WHERE UserLicense.Name = 'Salesforce Integration' LIMIT 1];
        }
        System.assertEquals(1, profiles.size(),
            'An API-only integration profile must exist in the org for this regression test');

        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '') + Datetime.now().getTime();
        User restricted = new User(
            ProfileId = profiles[0].Id,
            Username = 'mga.def001.' + unique + '@condor.com.py.qas.test',
            Email = 'mga.def001@example.com',
            LastName = 'Integration',
            Alias = 'mgadef',
            TimeZoneSidKey = 'America/Asuncion',
            LocaleSidKey = 'es_PY',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'es'
        );
        PermissionSet permissionSet = [SELECT Id FROM PermissionSet
                                       WHERE Name = 'MGAgencia_Integration' LIMIT 1];
        // The Salesforce Integration license supports Campaign read (granted by the
        // permission set) only through the "Salesforce API Integration" permission set
        // license, exactly as the real integration user is provisioned.
        PermissionSetLicense psl = [SELECT Id FROM PermissionSetLicense
                                    WHERE DeveloperName = 'SalesforceAPIIntegrationPsl' LIMIT 1];
        // Setup DML as the running user to avoid MIXED_DML with the later Lead inserts.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert restricted;
            insert new PermissionSetLicenseAssign(
                AssigneeId = restricted.Id, PermissionSetLicenseId = psl.Id);
            insert new PermissionSetAssignment(
                AssigneeId = restricted.Id, PermissionSetId = permissionSet.Id);
        }

        MGAgenciaLeadService.Result second;
        System.runAs(restricted) {
            Test.startTest();
            MGAgenciaLeadService.process(
                buildRequest('595981697111', 'restricted.dup@example.com', 'neb-svc-def001-a'));
            second = MGAgenciaLeadService.process(
                buildRequest('595981697111', 'restricted.other@example.com', 'neb-svc-def001-b'));
            Test.stopTest();
        }

        System.assertEquals(201, second.statusCode, 'Duplicate is still created (201)');
        System.assertEquals(true, second.response.duplicated,
            'DEF-001: the restricted integration user must detect the phone duplicate even though '
            + 'the first Lead is owned by a queue it cannot see');
        Lead flagged = [SELECT Duplicated_Lead__c, Duplicate_Reason__c FROM Lead
                        WHERE External_Lead_Id__c = 'neb-svc-def001-b'];
        System.assertEquals(true, flagged.Duplicated_Lead__c, 'Second Lead flagged as duplicate');
        System.assert(flagged.Duplicate_Reason__c.contains('MOBILE_PHONE_MATCH'),
            'Reason records the phone signal, got: ' + flagged.Duplicate_Reason__c);
    }
}
