/**
 * @description Behavior-first tests for NebulaLeadService orchestration: duplicate
 *              create-and-flag rule (Decision 4), configuration failure path, DML failure
 *              path, and the guarantee that responses never leak Salesforce IDs or raw
 *              exception text. Uses the service test seams (configOverride,
 *              simulateDmlFailure) for the 500 paths.
 */
@IsTest
private class NebulaLeadServiceTest {
    private static NebulaLeadRequest buildRequest(String phone, String email, String externalId) {
        NebulaLeadRequest request = new NebulaLeadRequest();
        request.first_name = 'Carlos';
        request.last_name = 'Benitez';
        request.phone = phone;
        request.email = email;
        request.external_lead_id = externalId;
        return request;
    }

    @IsTest
    static void duplicateByPhoneIsCreatedAndFlagged() {
        NebulaLeadService.process(buildRequest('595982222001', 'seed.phone@example.com', 'neb-svc-p1'));

        Test.startTest();
        NebulaLeadService.Result result = NebulaLeadService.process(
            buildRequest('595982222001', 'other.phone@example.com', 'neb-svc-p2'));
        Test.stopTest();

        System.assertEquals(201, result.statusCode, 'Duplicates are still created (201)');
        System.assertEquals(true, result.response.duplicated, 'Response reports duplicated=true');
        Lead duplicate = [SELECT Duplicated_Lead__c, Duplicate_Reason__c FROM Lead
                          WHERE External_Lead_Id__c = 'neb-svc-p2'];
        System.assertEquals(true, duplicate.Duplicated_Lead__c, 'Lead flagged as duplicate');
        System.assert(duplicate.Duplicate_Reason__c.contains('MOBILE_PHONE_MATCH'),
            'Reason records the phone signal, got: ' + duplicate.Duplicate_Reason__c);
        System.assertEquals(1, [SELECT COUNT() FROM Nebula_Integration_Log__c
                                WHERE Duplicated__c = true AND Status__c = 'CREATED'],
            'Duplicate creation logged with duplicate flag');
    }

    @IsTest
    static void duplicateByEmailIsCreatedAndFlagged() {
        NebulaLeadService.process(buildRequest('595982222002', 'same.email@example.com', 'neb-svc-e1'));

        Test.startTest();
        NebulaLeadService.Result result = NebulaLeadService.process(
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
        NebulaLeadService.process(buildRequest('595982222004', 'first.ext@example.com', 'neb-svc-x1'));

        Test.startTest();
        NebulaLeadService.Result result = NebulaLeadService.process(
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
        NebulaLeadService.process(buildRequest('595982222006', 'one.person@example.com', 'neb-svc-n1'));

        Test.startTest();
        NebulaLeadService.Result result = NebulaLeadService.process(
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
        NebulaLeadService.configOverride = new List<Nebula_Integration_Setting__mdt>();

        Test.startTest();
        NebulaLeadService.Result result = NebulaLeadService.process(
            buildRequest('595982222008', null, 'neb-svc-cfg'));
        Test.stopTest();

        System.assertEquals(500, result.statusCode, 'Missing configuration returns 500');
        System.assertEquals('INTERNAL_ERROR', result.response.code, 'Generic error code');
        String serialized = JSON.serialize(result.response, true);
        System.assert(!serialized.contains('NebulaConfigurationException'),
            'Response must not leak exception type');
        System.assert(!serialized.containsIgnoreCase('metadata'),
            'Response must not leak configuration detail');
        System.assertEquals(0, [SELECT COUNT() FROM Lead], 'No Lead created');
        List<Nebula_Integration_Log__c> logs = [SELECT Error_Detail__c FROM Nebula_Integration_Log__c
                                                WHERE Status__c = 'ERROR' AND Response_Code__c = 500];
        System.assertEquals(1, logs.size(), 'Configuration failure logged as ERROR');
        System.assert(logs[0].Error_Detail__c.contains('NebulaConfigurationException'),
            'Internal log keeps the exception type for diagnosis');
    }

    @IsTest
    static void dmlFailureReturns500AndLogsError() {
        NebulaLeadService.simulateDmlFailure = true;

        Test.startTest();
        NebulaLeadService.Result result = NebulaLeadService.process(
            buildRequest('595982222009', 'dml.failure@example.com', 'neb-svc-dml'));
        Test.stopTest();

        System.assertEquals(500, result.statusCode, 'DML failure returns 500');
        System.assertEquals('INTERNAL_ERROR', result.response.code, 'Generic error code');
        String serialized = JSON.serialize(result.response, true);
        System.assert(!serialized.contains('Simulated'), 'Response must not leak exception message');
        System.assertEquals(0, [SELECT COUNT() FROM Lead], 'No Lead persisted');
        List<Nebula_Integration_Log__c> logs = [SELECT Error_Detail__c, Lead__c
                                                FROM Nebula_Integration_Log__c
                                                WHERE Status__c = 'ERROR' AND Response_Code__c = 500];
        System.assertEquals(1, logs.size(), 'DML failure logged as ERROR');
        System.assertEquals(null, logs[0].Lead__c, 'No Lead reference on failed request');
        System.assert(logs[0].Error_Detail__c.contains('Simulated DML failure'),
            'Internal log keeps the sanitized detail (type + message)');
    }

    @IsTest
    static void successResponseNeverExposesSalesforceIds() {
        Test.startTest();
        NebulaLeadService.Result result = NebulaLeadService.process(
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
}
