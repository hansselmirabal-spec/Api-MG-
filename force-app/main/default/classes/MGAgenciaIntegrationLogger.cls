/**
 * @description Writes one MGAgencia_Integration_Log__c record per inbound request, for every
 *              outcome (created, validation failed, error). PII minimization: the raw request
 *              payload is never stored. Error detail (exception type + message) is internal
 *              only and never returned to the consumer. A logging failure never breaks the
 *              API response: insert problems are swallowed and debug-logged.
 */
public with sharing class MGAgenciaIntegrationLogger {
    private static final Integer ERROR_DETAIL_MAX_LENGTH = 32768;

    /** @description Data carrier for one log record. */
    public class LogEntry {
        public String integrationId;
        public String externalLeadId;
        public Id leadId;
        public String status;
        public String errorDetail;
        public Boolean duplicated = false;
        public Datetime receivedAt;
        public Long processingTimeMs;
        public Integer responseCode;
    }

    /**
     * @description Persists the log entry. Never throws.
     * @param entry populated log entry
     */
    public static void log(LogEntry entry) {
        try {
            MGAgencia_Integration_Log__c record = new MGAgencia_Integration_Log__c(
                Integration_Id__c = entry.integrationId,
                External_Lead_Id__c = entry.externalLeadId,
                Lead__c = entry.leadId,
                Status__c = entry.status,
                Error_Detail__c = entry.errorDetail == null
                    ? null
                    : entry.errorDetail.abbreviate(ERROR_DETAIL_MAX_LENGTH),
                Duplicated__c = entry.duplicated == true,
                Request_Received_At__c = entry.receivedAt,
                Processing_Time_Ms__c = entry.processingTimeMs,
                Response_Code__c = entry.responseCode
            );
            Database.insert(record, AccessLevel.USER_MODE);
        } catch (Exception e) {
            // A traceability failure must never turn into an API failure.
            System.debug(LoggingLevel.ERROR, 'MGAgencia integration log insert failed: ' + e.getTypeName());
        }
    }

    /**
     * @description Logs a request rejected at the transport layer as malformed (HTTP 400).
     *              Called by the REST resource; no payload content is stored.
     * @param receivedAt when the request was received
     * @param startMs System.currentTimeMillis() captured at request start
     */
    public static void logMalformedRequest(Datetime receivedAt, Long startMs) {
        LogEntry entry = new LogEntry();
        entry.integrationId = UUID.randomUUID().toString();
        entry.status = 'ERROR';
        entry.errorDetail = 'MALFORMED_REQUEST: request body was empty, not valid JSON, or not a JSON object.';
        entry.receivedAt = receivedAt;
        entry.processingTimeMs = System.currentTimeMillis() - startMs;
        entry.responseCode = 400;
        log(entry);
    }
}
