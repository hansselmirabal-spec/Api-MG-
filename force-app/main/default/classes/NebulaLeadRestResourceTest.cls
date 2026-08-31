/**
 * @description Behavior-first tests for the Nebüla Lead endpoint transport + contract:
 *              status codes, response schema, validation aggregation, branch catalog and
 *              Lead/log persistence. Runs against real org automation (flows, triggers),
 *              so assertions target integration-owned behavior and tolerate automation
 *              side effects (owner reassignment, phone normalization, upper-cased names).
 */
@IsTest
private class NebulaLeadRestResourceTest {
    private static final String ENDPOINT = '/services/apexrest/nebula/v1/leads';

    private static void arrangeRequest(String body) {
        RestRequest request = new RestRequest();
        request.requestURI = ENDPOINT;
        request.httpMethod = 'POST';
        if (body != null) {
            request.requestBody = Blob.valueOf(body);
        }
        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    private static Map<String, Object> responseBody() {
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    @IsTest
    static void createsLeadWithConfiguredValuesAndLogsIt() {
        arrangeRequest(JSON.serialize(new Map<String, Object>{
            'first_name' => 'Maria',
            'last_name' => 'Gonzalez',
            'phone' => '595981111001',
            'email' => 'maria.rest.test@example.com',
            'branch_code' => 'ASUNCION',
            'external_lead_id' => 'neb-rest-001'
        }));

        Test.startTest();
        NebulaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode, 'Successful creation must return 201');
        Map<String, Object> body = responseBody();
        System.assertEquals('LEAD_CREATED', body.get('code'), 'Response code');
        System.assertEquals('success', body.get('status'), 'Response status');
        System.assertEquals(false, body.get('duplicated'), 'First submission is not a duplicate');
        String integrationId = (String) body.get('integration_id');
        System.assert(Pattern.matches('[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
            integrationId), 'integration_id must be a UUID, got: ' + integrationId);

        List<Lead> leads = [SELECT Id, FirstName, LastName, Status, LeadSource, Family__c, Brand__c,
                                   Nearest_Branch__c, External_Lead_Id__c, Duplicated_Lead__c,
                                   RecordType.DeveloperName
                            FROM Lead WHERE External_Lead_Id__c = 'neb-rest-001'];
        System.assertEquals(1, leads.size(), 'Exactly one Lead created');
        Lead created = leads[0];
        System.assertEquals('Fisica', created.RecordType.DeveloperName, 'Configured record type');
        System.assertEquals('AUTOMÓVILES MG', created.Family__c, 'Configured family');
        System.assertEquals('MG', created.Brand__c, 'Configured brand');
        System.assertEquals('Nebüla', created.LeadSource, 'Configured lead source');
        System.assertEquals('Formulario Nebüla', created.Status, 'Configured initial status');
        System.assertEquals('ASUNCIÓN', created.Nearest_Branch__c, 'branch_code resolved to picklist value');
        System.assertEquals(false, created.Duplicated_Lead__c, 'Not flagged as duplicate');
        // Org flow DatosInicialesProspecto upper-cases names: compare case-insensitively.
        System.assertEquals('maria', created.FirstName.toLowerCase(), 'First name persisted');

        List<Nebula_Integration_Log__c> logs = [SELECT Status__c, Lead__c, Duplicated__c,
                                                       External_Lead_Id__c, Response_Code__c,
                                                       Request_Received_At__c, Processing_Time_Ms__c
                                                FROM Nebula_Integration_Log__c
                                                WHERE Integration_Id__c = :integrationId];
        System.assertEquals(1, logs.size(), 'One log record per request');
        System.assertEquals('CREATED', logs[0].Status__c, 'Log status');
        System.assertEquals(created.Id, logs[0].Lead__c, 'Log references the created Lead');
        System.assertEquals(false, logs[0].Duplicated__c, 'Log duplicate flag');
        System.assertEquals('neb-rest-001', logs[0].External_Lead_Id__c, 'Log external id');
        System.assertEquals(201, logs[0].Response_Code__c.intValue(), 'Log response code');
        System.assertNotEquals(null, logs[0].Request_Received_At__c, 'Log received timestamp');
    }

    @IsTest
    static void missingRequiredFieldsReturnsAllErrorsAggregated() {
        // first_name AND phone missing: both problems must be reported in one response.
        arrangeRequest('{"last_name":"Gonzalez"}');

        Test.startTest();
        NebulaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(422, RestContext.response.statusCode, 'Validation failure returns 422');
        Map<String, Object> body = responseBody();
        System.assertEquals('VALIDATION_ERROR', body.get('code'), 'Response code');
        Set<String> failedFields = new Set<String>();
        for (Object item : (List<Object>) body.get('errors')) {
            Map<String, Object> error = (Map<String, Object>) item;
            failedFields.add((String) error.get('field'));
            System.assertEquals('REQUIRED', error.get('code'), 'Missing-field error code');
        }
        System.assert(failedFields.contains('first_name'), 'first_name error reported');
        System.assert(failedFields.contains('phone'), 'phone error reported');
        System.assertEquals(2, failedFields.size(), 'Exactly the two missing fields reported');
        System.assertEquals(0, [SELECT COUNT() FROM Lead], 'No Lead created on validation failure');
        System.assertEquals(1, [SELECT COUNT() FROM Nebula_Integration_Log__c
                                WHERE Status__c = 'VALIDATION_FAILED' AND Response_Code__c = 422],
            'Validation failure is logged');
    }

    @IsTest
    static void invalidEmailFormatReturns422() {
        arrangeRequest(JSON.serialize(new Map<String, Object>{
            'first_name' => 'Ana', 'last_name' => 'Diaz',
            'phone' => '595981111002', 'email' => 'not-an-email'
        }));

        Test.startTest();
        NebulaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(422, RestContext.response.statusCode, 'Invalid email returns 422');
        Map<String, Object> error = (Map<String, Object>) ((List<Object>) responseBody().get('errors'))[0];
        System.assertEquals('email', error.get('field'), 'email field reported');
        System.assertEquals('INVALID_FORMAT', error.get('code'), 'Format error code');
    }

    @IsTest
    static void unknownBranchCodeReturns422UnknownValue() {
        arrangeRequest(JSON.serialize(new Map<String, Object>{
            'first_name' => 'Ana', 'last_name' => 'Diaz',
            'phone' => '595981111003', 'branch_code' => 'LUQUE'
        }));

        Test.startTest();
        NebulaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(422, RestContext.response.statusCode, 'Unknown branch returns 422');
        Map<String, Object> error = (Map<String, Object>) ((List<Object>) responseBody().get('errors'))[0];
        System.assertEquals('branch_code', error.get('field'), 'branch_code field reported');
        System.assertEquals('UNKNOWN_VALUE', error.get('code'), 'Unknown-value error code');
        System.assertEquals(0, [SELECT COUNT() FROM Lead], 'No Lead created');
    }

    @IsTest
    static void validBranchCodeMapsToPicklistValue() {
        arrangeRequest(JSON.serialize(new Map<String, Object>{
            'first_name' => 'Ana', 'last_name' => 'Diaz',
            'phone' => '595981111004', 'branch_code' => 'CIUDAD_DEL_ESTE',
            'external_lead_id' => 'neb-rest-branch'
        }));

        Test.startTest();
        NebulaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode, 'Created');
        Lead created = [SELECT Nearest_Branch__c FROM Lead WHERE External_Lead_Id__c = 'neb-rest-branch'];
        System.assertEquals('CIUDAD DEL ESTE', created.Nearest_Branch__c, 'Catalog code mapped to label');
    }

    @IsTest
    static void malformedJsonReturns400() {
        arrangeRequest('{"first_name": "Maria", not-json');

        Test.startTest();
        NebulaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode, 'Malformed JSON returns 400');
        Map<String, Object> body = responseBody();
        System.assertEquals('MALFORMED_REQUEST', body.get('code'), 'Response code');
        System.assertEquals('error', body.get('status'), 'Response status');
        System.assertEquals(false, body.containsKey('integration_id'), 'No integration_id on 400');
        System.assertEquals(0, [SELECT COUNT() FROM Lead], 'No Lead created');
        System.assertEquals(1, [SELECT COUNT() FROM Nebula_Integration_Log__c
                                WHERE Status__c = 'ERROR' AND Response_Code__c = 400],
            'Malformed request is logged');
    }

    @IsTest
    static void emptyBodyReturns400() {
        arrangeRequest(null);

        Test.startTest();
        NebulaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode, 'Missing body returns 400');
        System.assertEquals('MALFORMED_REQUEST', responseBody().get('code'), 'Response code');
    }

    @IsTest
    static void unknownJsonPropertiesAreIgnored() {
        // campaign_code / interest_model are PENDING BUSINESS DECISION: ignored, not rejected.
        arrangeRequest(JSON.serialize(new Map<String, Object>{
            'first_name' => 'Ana', 'last_name' => 'Diaz', 'phone' => '595981111005',
            'campaign_code' => 'CAMP-01', 'interest_model' => 'MG ZS', 'anything_else' => 42
        }));

        Test.startTest();
        NebulaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode, 'Unknown properties are ignored');
    }
}
