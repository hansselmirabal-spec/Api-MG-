/**
 * @description Behavior-first tests for the MGAgencia Lead endpoint transport + contract:
 *              status codes, response schema, validation aggregation, branch catalog and
 *              Lead/log persistence. Runs against real org automation (flows, triggers),
 *              so assertions target integration-owned behavior and tolerate automation
 *              side effects (owner reassignment, phone normalization, upper-cased names).
 */
@IsTest
private class MGAgenciaLeadRestResourceTest {
    private static final String ENDPOINT = '/services/apexrest/mgagencia/v1/leads';

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
        MGAgenciaLeadRestResource.createLead();
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
                                   Sucursal_Seleccionada_Meta__c, Nearest_Branch__c, External_Lead_Id__c,
                                   Duplicated_Lead__c, Tel_fono_Meta__c, RecordType.DeveloperName
                            FROM Lead WHERE External_Lead_Id__c = 'neb-rest-001'];
        System.assertEquals(1, leads.size(), 'Exactly one Lead created');
        Lead created = leads[0];
        System.assertEquals('Fisica', created.RecordType.DeveloperName, 'Configured record type');
        System.assertEquals('AUTOMÓVILES MG', created.Family__c, 'Configured family');
        System.assertEquals('MG', created.Brand__c, 'Configured brand');
        System.assertEquals('MGAgencia', created.LeadSource, 'Configured lead source');
        System.assertEquals('Formulario Meta', created.Status, 'Configured initial status');
        System.assertEquals('asunción', created.Sucursal_Seleccionada_Meta__c,
            'branch_code resolved to Sucursal_Seleccionada_Meta__c label (Decision 7 amendment)');
        System.assertEquals(null, created.Nearest_Branch__c,
            'Nearest_Branch__c is no longer set by this integration');
        System.assertEquals('595981111001', created.Tel_fono_Meta__c,
            'Raw phone stored verbatim (Decision 9)');
        System.assertEquals(false, created.Duplicated_Lead__c, 'Not flagged as duplicate');
        // Org flow DatosInicialesProspecto upper-cases names: compare case-insensitively.
        System.assertEquals('maria', created.FirstName.toLowerCase(), 'First name persisted');

        List<MGAgencia_Integration_Log__c> logs = [SELECT Status__c, Lead__c, Duplicated__c,
                                                       External_Lead_Id__c, Response_Code__c,
                                                       Request_Received_At__c, Processing_Time_Ms__c
                                                FROM MGAgencia_Integration_Log__c
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
        MGAgenciaLeadRestResource.createLead();
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
        System.assertEquals(1, [SELECT COUNT() FROM MGAgencia_Integration_Log__c
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
        MGAgenciaLeadRestResource.createLead();
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
        MGAgenciaLeadRestResource.createLead();
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
        MGAgenciaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode, 'Created');
        Lead created = [SELECT Sucursal_Seleccionada_Meta__c, Nearest_Branch__c
                         FROM Lead WHERE External_Lead_Id__c = 'neb-rest-branch'];
        System.assertEquals('ciudad_del_este', created.Sucursal_Seleccionada_Meta__c,
            'Catalog code mapped to the Sucursal_Seleccionada_Meta__c label (Decision 7 amendment)');
        System.assertEquals(null, created.Nearest_Branch__c, 'Nearest_Branch__c is not set anymore');
    }

    @IsTest
    static void malformedJsonReturns400() {
        arrangeRequest('{"first_name": "Maria", not-json');

        Test.startTest();
        MGAgenciaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode, 'Malformed JSON returns 400');
        Map<String, Object> body = responseBody();
        System.assertEquals('MALFORMED_REQUEST', body.get('code'), 'Response code');
        System.assertEquals('error', body.get('status'), 'Response status');
        System.assertEquals(false, body.containsKey('integration_id'), 'No integration_id on 400');
        System.assertEquals(0, [SELECT COUNT() FROM Lead], 'No Lead created');
        System.assertEquals(1, [SELECT COUNT() FROM MGAgencia_Integration_Log__c
                                WHERE Status__c = 'ERROR' AND Response_Code__c = 400],
            'Malformed request is logged');
    }

    @IsTest
    static void emptyBodyReturns400() {
        arrangeRequest(null);

        Test.startTest();
        MGAgenciaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode, 'Missing body returns 400');
        System.assertEquals('MALFORMED_REQUEST', responseBody().get('code'), 'Response code');
    }

    @IsTest
    static void unknownJsonPropertiesAreIgnored() {
        // campaign_code is PENDING BUSINESS DECISION: ignored, not rejected (interest_model is
        // now an implemented field, see optionalFieldsPopulateCorrectlyEndToEnd below).
        arrangeRequest(JSON.serialize(new Map<String, Object>{
            'first_name' => 'Ana', 'last_name' => 'Diaz', 'phone' => '595981111005',
            'campaign_code' => 'CAMP-01', 'anything_else' => 42
        }));

        Test.startTest();
        MGAgenciaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode, 'Unknown properties are ignored');
    }

    // ---- 2026-09-03 MGAgencia UAT follow-up fields ------------------------------------------

    @IsTest
    static void validContactPreferenceMapsToPicklistValue() {
        arrangeRequest(JSON.serialize(new Map<String, Object>{
            'first_name' => 'Ana', 'last_name' => 'Diaz', 'phone' => '595981111006',
            'contact_preference' => 'WhatsApp', 'external_lead_id' => 'neb-rest-cp-ok'
        }));

        Test.startTest();
        MGAgenciaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode, 'Created');
        Lead created = [SELECT Preferencia_de_contacto__c FROM Lead
                         WHERE External_Lead_Id__c = 'neb-rest-cp-ok'];
        System.assertEquals('WhatsApp', created.Preferencia_de_contacto__c, 'Exact picklist value stored');
    }

    @IsTest
    static void unknownContactPreferenceReturns422UnknownValue() {
        arrangeRequest(JSON.serialize(new Map<String, Object>{
            'first_name' => 'Ana', 'last_name' => 'Diaz', 'phone' => '595981111007',
            'contact_preference' => 'SMS'
        }));

        Test.startTest();
        MGAgenciaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(422, RestContext.response.statusCode, 'Unknown contact_preference returns 422');
        Map<String, Object> error = (Map<String, Object>) ((List<Object>) responseBody().get('errors'))[0];
        System.assertEquals('contact_preference', error.get('field'), 'contact_preference field reported');
        System.assertEquals('UNKNOWN_VALUE', error.get('code'), 'Unknown-value error code');
        System.assertEquals(0, [SELECT COUNT() FROM Lead], 'No Lead created');
    }

    @IsTest
    static void freeTextFieldExceedingMaxLengthReturns422InvalidFormat() {
        arrangeRequest(JSON.serialize(new Map<String, Object>{
            'first_name' => 'Ana', 'last_name' => 'Diaz', 'phone' => '595981111008',
            'payment_method' => 'x'.repeat(51)
        }));

        Test.startTest();
        MGAgenciaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(422, RestContext.response.statusCode, 'Over-length free text returns 422');
        Map<String, Object> error = (Map<String, Object>) ((List<Object>) responseBody().get('errors'))[0];
        System.assertEquals('payment_method', error.get('field'), 'payment_method field reported');
        System.assertEquals('INVALID_FORMAT', error.get('code'), 'Invalid-format error code');
        System.assertEquals(0, [SELECT COUNT() FROM Lead], 'No Lead created');
    }

    @IsTest
    static void optionalFieldsPopulateCorrectlyEndToEnd() {
        arrangeRequest(JSON.serialize(new Map<String, Object>{
            'first_name' => 'Sofia', 'last_name' => 'Ramirez', 'phone' => '0981222333',
            'external_lead_id' => 'neb-rest-optfields',
            'interest_model' => 'MG ZS 2026',
            'contact_preference' => 'Teléfono',
            'payment_method' => 'Financiación bancaria',
            'purchase_timeline' => 'En los próximos 90 días',
            'trade_in' => 'Sí, quiero tasar',
            'test_drive_requested' => true
        }));

        Test.startTest();
        MGAgenciaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode, 'Created');
        Lead created = [SELECT VehicleOfInterestOfTheWeb__c, Preferencia_de_contacto__c,
                                Forma_de_Pago__c, Plazo_de_Compra__c, Entrega_su_Auto__c,
                                TestDriveRequested__c, MobilePhone, Tel_fono_Meta__c
                         FROM Lead WHERE External_Lead_Id__c = 'neb-rest-optfields'];
        System.assertEquals('MG ZS 2026', created.VehicleOfInterestOfTheWeb__c, 'interest_model stored');
        System.assertEquals('Teléfono', created.Preferencia_de_contacto__c, 'contact_preference stored');
        System.assertEquals('Financiación bancaria', created.Forma_de_Pago__c, 'payment_method stored');
        System.assertEquals('En los próximos 90 días', created.Plazo_de_Compra__c, 'purchase_timeline stored');
        System.assertEquals('Sí, quiero tasar', created.Entrega_su_Auto__c, 'trade_in stored');
        System.assertEquals(true, created.TestDriveRequested__c, 'test_drive_requested stored');
        System.assertEquals('595981222333', created.MobilePhone, 'MobilePhone normalized for matching');
        System.assertEquals('0981222333', created.Tel_fono_Meta__c,
            'Tel_fono_Meta__c stores the raw pre-normalization phone (Decision 9)');
    }

    @IsTest
    static void newFieldsAreOptionalAndOmittedWhenAbsent() {
        arrangeRequest(JSON.serialize(new Map<String, Object>{
            'first_name' => 'Luis', 'last_name' => 'Torres', 'phone' => '595981111009',
            'external_lead_id' => 'neb-rest-optabsent'
        }));

        Test.startTest();
        MGAgenciaLeadRestResource.createLead();
        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode, 'Omitting all new fields is valid');
        Lead created = [SELECT VehicleOfInterestOfTheWeb__c, Preferencia_de_contacto__c,
                                Forma_de_Pago__c, Plazo_de_Compra__c, Entrega_su_Auto__c,
                                TestDriveRequested__c
                         FROM Lead WHERE External_Lead_Id__c = 'neb-rest-optabsent'];
        System.assertEquals(null, created.VehicleOfInterestOfTheWeb__c, 'interest_model left blank');
        System.assertEquals(null, created.Preferencia_de_contacto__c, 'contact_preference left blank');
        System.assertEquals(null, created.Forma_de_Pago__c, 'payment_method left blank');
        System.assertEquals(null, created.Plazo_de_Compra__c, 'purchase_timeline left blank');
        System.assertEquals(null, created.Entrega_su_Auto__c, 'trade_in left blank');
        System.assertEquals(false, created.TestDriveRequested__c, 'TestDriveRequested__c keeps its org default');
    }
}
