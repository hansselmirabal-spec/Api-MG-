/**
 * @description Application service for the Nebüla Lead endpoint. Sole orchestrator:
 *              configuration load (CMDT) → validation → duplicate evaluation → Lead build +
 *              insert (default assignment rule applied) → integration logging → response.
 *              No transport concerns here; no business logic in the REST resource.
 *              All DML and SOQL run in user mode (CRUD/FLS enforced).
 */
public with sharing class NebulaLeadService {
    /** @description Test seam: overrides the CMDT lookup (empty list simulates missing config). */
    @TestVisible
    private static List<Nebula_Integration_Setting__mdt> configOverride;

    /** @description Test seam: forces the DML step to fail to exercise the 500 path. */
    @TestVisible
    private static Boolean simulateDmlFailure = false;

    /** @description Service outcome: HTTP status code plus the response DTO to serialize. */
    public class Result {
        public Integer statusCode;
        public NebulaLeadResponse response;
    }

    /**
     * @description Processes one parsed Lead creation request end to end. Always writes an
     *              integration log entry, whatever the outcome.
     * @param request parsed request DTO (never null; parsing errors are handled upstream)
     * @return result carrying the HTTP status code and consumer-safe response body
     */
    public static Result process(NebulaLeadRequest request) {
        Long startMs = System.currentTimeMillis();
        Result result = new Result();
        NebulaIntegrationLogger.LogEntry entry = new NebulaIntegrationLogger.LogEntry();
        entry.integrationId = UUID.randomUUID().toString();
        entry.receivedAt = System.now();
        entry.externalLeadId = request.external_lead_id == null ? null : request.external_lead_id.trim();

        try {
            Nebula_Integration_Setting__mdt config = loadConfiguration();
            List<NebulaLeadResponse.ErrorDetail> errors = NebulaLeadValidator.validate(request);
            if (!errors.isEmpty()) {
                entry.status = 'VALIDATION_FAILED';
                result.statusCode = 422;
                result.response = NebulaLeadResponse.validationError(errors);
            } else {
                NebulaDuplicateEvaluator.Result duplicate = NebulaDuplicateEvaluator.evaluate(
                    request.phone, request.email, request.external_lead_id);
                Lead lead = buildLead(request, config, duplicate);
                insertLead(lead);
                entry.status = 'CREATED';
                entry.leadId = lead.Id;
                entry.duplicated = duplicate.isDuplicate;
                result.statusCode = 201;
                result.response = NebulaLeadResponse.created(entry.integrationId, duplicate.isDuplicate);
            }
        } catch (Exception e) {
            // Internal detail is stored on the log record only; the consumer gets a generic 500.
            entry.status = 'ERROR';
            entry.errorDetail = e.getTypeName() + ': ' + e.getMessage();
            result.statusCode = 500;
            result.response = NebulaLeadResponse.internalError();
        }

        entry.processingTimeMs = System.currentTimeMillis() - startMs;
        entry.responseCode = result.statusCode;
        NebulaIntegrationLogger.log(entry);
        return result;
    }

    /**
     * @description Loads the active integration configuration from Custom Metadata.
     * @return active configuration record
     * @throws NebulaConfigurationException when no active configuration exists
     */
    private static Nebula_Integration_Setting__mdt loadConfiguration() {
        List<Nebula_Integration_Setting__mdt> settings = configOverride != null
            ? configOverride
            : [SELECT Record_Type_DeveloperName__c, Family__c, Brand__c, Initial_Status__c,
                      Lead_Source__c, Queue_DeveloperName__c, Active__c
               FROM Nebula_Integration_Setting__mdt
               WHERE DeveloperName = 'Default' AND Active__c = true
               LIMIT 1];
        if (settings.isEmpty() || settings[0].Active__c != true) {
            throw new NebulaConfigurationException(
                'No active Nebula_Integration_Setting__mdt configuration found.');
        }
        return settings[0];
    }

    /**
     * @description Maps the request and fixed configuration values onto a Lead sObject.
     * @param request validated request DTO
     * @param config active integration configuration
     * @param duplicate duplicate evaluation outcome
     * @return unsaved Lead
     * @throws NebulaConfigurationException when the configured record type does not exist
     */
    private static Lead buildLead(NebulaLeadRequest request, Nebula_Integration_Setting__mdt config,
                                  NebulaDuplicateEvaluator.Result duplicate) {
        Schema.RecordTypeInfo recordType = Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName().get(config.Record_Type_DeveloperName__c);
        if (recordType == null) {
            throw new NebulaConfigurationException(
                'Configured Lead record type not found: ' + config.Record_Type_DeveloperName__c);
        }
        return new Lead(
            RecordTypeId = recordType.getRecordTypeId(),
            FirstName = request.first_name.trim(),
            LastName = request.last_name.trim(),
            MobilePhone = request.phone.trim(),
            Email = String.isBlank(request.email) ? null : request.email.trim(),
            Nearest_Branch__c = NebulaBranchResolver.resolve(request.branch_code),
            External_Lead_Id__c = String.isBlank(request.external_lead_id)
                ? null : request.external_lead_id.trim(),
            Status = config.Initial_Status__c,
            // Org VR ValidarTareaEstadoContactado exempts 'Formulario Meta'/'Prospecto' but not
            // the new initial status; it passes when Estatus__c = 'No contactado', which is the
            // factual state of a freshly received advertising lead. Follow-up: add the status
            // exemption to the VR itself (Salesforce admin change).
            Estatus__c = 'No contactado',
            LeadSource = config.Lead_Source__c,
            Family__c = config.Family__c,
            Brand__c = config.Brand__c,
            Duplicated_Lead__c = duplicate.isDuplicate,
            Duplicate_Reason__c = duplicate.reason
        );
    }

    /**
     * @description Inserts the Lead applying the org's active assignment rule (routes
     *              LeadSource = Nebüla to the Nebula_Leads queue — Decision 1, amended).
     *              User-mode DML: CRUD/FLS enforced for the running integration user.
     * @param lead unsaved Lead, populated by buildLead
     */
    private static void insertLead(Lead lead) {
        if (simulateDmlFailure) {
            throw new NebulaIntegrationException('Simulated DML failure for tests.');
        }
        Database.DMLOptions options = new Database.DMLOptions();
        options.assignmentRuleHeader.useDefaultRule = true;
        options.optAllOrNone = true;
        lead.setOptions(options);
        Database.insert(lead, AccessLevel.USER_MODE);
    }
}
