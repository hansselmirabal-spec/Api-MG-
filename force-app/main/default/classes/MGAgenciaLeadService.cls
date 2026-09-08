/**
 * @description Application service for the MGAgencia Lead endpoint. Sole orchestrator:
 *              configuration load (CMDT) → validation → duplicate evaluation → Lead build +
 *              insert (default assignment rule applied) → integration logging → response.
 *              No transport concerns here; no business logic in the REST resource.
 *              All DML and SOQL run in user mode (CRUD/FLS enforced).
 */
public with sharing class MGAgenciaLeadService {
    /** @description Test seam: overrides the CMDT lookup (empty list simulates missing config). */
    @TestVisible
    private static List<MGAgencia_Integration_Setting__mdt> configOverride;

    /** @description Test seam: forces the DML step to fail to exercise the 500 path. */
    @TestVisible
    private static Boolean simulateDmlFailure = false;

    /** @description Service outcome: HTTP status code plus the response DTO to serialize. */
    public class Result {
        public Integer statusCode;
        public MGAgenciaLeadResponse response;
    }

    /**
     * @description Processes one parsed Lead creation request end to end. Always writes an
     *              integration log entry, whatever the outcome.
     * @param request parsed request DTO (never null; parsing errors are handled upstream)
     * @return result carrying the HTTP status code and consumer-safe response body
     */
    public static Result process(MGAgenciaLeadRequest request) {
        Long startMs = System.currentTimeMillis();
        Result result = new Result();
        MGAgenciaIntegrationLogger.LogEntry entry = new MGAgenciaIntegrationLogger.LogEntry();
        entry.integrationId = UUID.randomUUID().toString();
        entry.receivedAt = System.now();
        entry.externalLeadId = request.external_lead_id == null ? null : request.external_lead_id.trim();

        try {
            MGAgencia_Integration_Setting__mdt config = loadConfiguration();
            List<MGAgenciaLeadResponse.ErrorDetail> errors = MGAgenciaLeadValidator.validate(request);
            if (!errors.isEmpty()) {
                entry.status = 'VALIDATION_FAILED';
                result.statusCode = 422;
                result.response = MGAgenciaLeadResponse.validationError(errors);
            } else {
                // Normalize the phone to the org convention (flow DatosInicialesProspecto)
                // BEFORE duplicate matching and BEFORE storing MobilePhone, so comparisons
                // and the stored value match already-normalized existing Leads.
                String normalizedPhone = MGAgenciaPhoneNormalizer.normalize(request.phone);
                MGAgenciaDuplicateEvaluator.Result duplicate = MGAgenciaDuplicateEvaluator.evaluate(
                    normalizedPhone, request.email, request.external_lead_id);
                Lead lead = buildLead(request, normalizedPhone, config, duplicate);
                applyOptionalBooleanFields(lead, request);
                insertLead(lead, config.Queue_DeveloperName__c);
                entry.status = 'CREATED';
                entry.leadId = lead.Id;
                entry.duplicated = duplicate.isDuplicate;
                result.statusCode = 201;
                result.response = MGAgenciaLeadResponse.created(entry.integrationId, duplicate.isDuplicate);
            }
        } catch (Exception e) {
            // Internal detail is stored on the log record only; the consumer gets a generic 500.
            entry.status = 'ERROR';
            entry.errorDetail = e.getTypeName() + ': ' + e.getMessage();
            result.statusCode = 500;
            result.response = MGAgenciaLeadResponse.internalError();
        }

        entry.processingTimeMs = System.currentTimeMillis() - startMs;
        entry.responseCode = result.statusCode;
        MGAgenciaIntegrationLogger.log(entry);
        return result;
    }

    /**
     * @description Loads the active integration configuration from Custom Metadata.
     * @return active configuration record
     * @throws MGAgenciaConfigurationException when no active configuration exists
     */
    private static MGAgencia_Integration_Setting__mdt loadConfiguration() {
        List<MGAgencia_Integration_Setting__mdt> settings = configOverride != null
            ? configOverride
            : [SELECT Record_Type_DeveloperName__c, Family__c, Brand__c, Initial_Status__c,
                      Lead_Source__c, Queue_DeveloperName__c, Active__c
               FROM MGAgencia_Integration_Setting__mdt
               WHERE DeveloperName = 'Default' AND Active__c = true
               LIMIT 1];
        if (settings.isEmpty() || settings[0].Active__c != true) {
            throw new MGAgenciaConfigurationException(
                'No active MGAgencia_Integration_Setting__mdt configuration found.');
        }
        return settings[0];
    }

    /**
     * @description Maps the request and fixed configuration values onto a Lead sObject.
     * @param request validated request DTO
     * @param normalizedPhone phone already normalized to the org convention (595…)
     * @param config active integration configuration
     * @param duplicate duplicate evaluation outcome
     * @return unsaved Lead
     * @throws MGAgenciaConfigurationException when the configured record type does not exist
     */
    private static Lead buildLead(MGAgenciaLeadRequest request, String normalizedPhone,
                                  MGAgencia_Integration_Setting__mdt config,
                                  MGAgenciaDuplicateEvaluator.Result duplicate) {
        Schema.RecordTypeInfo recordType = Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName().get(config.Record_Type_DeveloperName__c);
        if (recordType == null) {
            throw new MGAgenciaConfigurationException(
                'Configured Lead record type not found: ' + config.Record_Type_DeveloperName__c);
        }
        return new Lead(
            RecordTypeId = recordType.getRecordTypeId(),
            FirstName = request.first_name.trim(),
            LastName = request.last_name.trim(),
            MobilePhone = normalizedPhone,
            // Decision 9 (2026-09-03): raw phone as received, pre-normalization, stored
            // alongside the normalized MobilePhone used for duplicate matching.
            Tel_fono_Meta__c = request.phone,
            Email = String.isBlank(request.email) ? null : request.email.trim(),
            // Decision 7 amendment (2026-09-03): branch_code now targets the free-text
            // Sucursal_Seleccionada_Meta__c field, not the Nearest_Branch__c picklist.
            Sucursal_Seleccionada_Meta__c = MGAgenciaBranchResolver.resolve(request.branch_code),
            External_Lead_Id__c = String.isBlank(request.external_lead_id)
                ? null : request.external_lead_id.trim(),
            // Added 2026-09-03: MGAgencia UAT follow-up fields, all optional and additive.
            VehicleOfInterestOfTheWeb__c = String.isBlank(request.interest_model)
                ? null : request.interest_model.trim(),
            Preferencia_de_contacto__c = MGAgenciaContactPreferenceResolver.resolve(request.contact_preference),
            Forma_de_Pago__c = String.isBlank(request.payment_method) ? null : request.payment_method.trim(),
            Plazo_de_Compra__c = String.isBlank(request.purchase_timeline) ? null : request.purchase_timeline.trim(),
            Entrega_su_Auto__c = String.isBlank(request.trade_in) ? null : request.trade_in.trim(),
            Status = config.Initial_Status__c,
            // Decision 1 amendment (2026-09-08, confirmed by Salesforce admin): Estatus__c
            // = 'Nuevo' instead of 'No contactado'. 'No contactado' triggers the org flow
            // "Crear Tarea si No Contactado" on Owner change, which fails outright for any
            // queue lacking Task in its supported objects (Reglas_Meta, MQL — see
            // docs/ADMIN_FOLLOWUPS.md #5). 'Nuevo' avoids that flow's trigger condition; a
            // separate org mechanism reassigns Estatus__c = 'Nuevo' Leads to the MQL queue
            // regardless of the assignment rule's target queue.
            Estatus__c = 'Nuevo',
            LeadSource = config.Lead_Source__c,
            Family__c = config.Family__c,
            Brand__c = config.Brand__c,
            Duplicated_Lead__c = duplicate.isDuplicate,
            Duplicate_Reason__c = duplicate.reason
        );
    }

    /**
     * @description Applies test_drive_requested as a simple pass-through when the field is
     *              present in the request. TestDriveRequested__c is nillable=false with a
     *              default of false, so an omitted field is left unset here rather than
     *              explicitly assigned null, letting the platform default apply normally.
     * @param lead unsaved Lead built by buildLead
     * @param request parsed request DTO
     */
    private static void applyOptionalBooleanFields(Lead lead, MGAgenciaLeadRequest request) {
        if (request.test_drive_requested != null) {
            lead.TestDriveRequested__c = request.test_drive_requested;
        }
    }

    /**
     * @description Inserts the Lead with OwnerId resolved directly from
     *              MGAgencia_Integration_Setting__mdt.Queue_DeveloperName__c (Decision 1,
     *              amended 2026-09-08) — NOT via the org's shared assignment-rule engine.
     *              Configured to target Reglas_Meta; combined with Estatus__c = 'Nuevo'
     *              (see buildLead), the org's own automation reassigns the Lead to queue
     *              MQL. Verified via real (non-test) calls in mi-org. User-mode DML:
     *              CRUD/FLS enforced for the running integration user.
     * @param lead unsaved Lead, populated by buildLead
     * @param queueDeveloperName target queue's DeveloperName, from CMDT config
     * @throws MGAgenciaConfigurationException when the configured queue does not exist
     */
    private static void insertLead(Lead lead, String queueDeveloperName) {
        if (simulateDmlFailure) {
            throw new MGAgenciaIntegrationException('Simulated DML failure for tests.');
        }
        List<Group> queues = [SELECT Id FROM Group
                               WHERE DeveloperName = :queueDeveloperName AND Type = 'Queue' LIMIT 1];
        if (queues.isEmpty()) {
            throw new MGAgenciaConfigurationException(
                'Configured queue not found: ' + queueDeveloperName);
        }
        lead.OwnerId = queues[0].Id;
        Database.DMLOptions options = new Database.DMLOptions();
        options.optAllOrNone = true;
        lead.setOptions(options);
        Database.insert(lead, AccessLevel.USER_MODE);
    }
}
