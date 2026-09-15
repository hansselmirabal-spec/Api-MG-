/**
 * @description Writes one MGAgencia_Integration_Log__c record per inbound request, for every
 *              outcome (created, validation failed, error). PII minimization: the raw request
 *              payload is never stored. Error detail (exception type + message) is internal
 *              only and never returned to the consumer. A logging failure never breaks the
 *              API response: insert problems are swallowed and debug-logged.
 *
 *              SHARING MODEL (same failure class as DEF-001, found 2026-09-15): the log
 *              insert — and ONLY the insert — runs in SYSTEM_MODE through a private
 *              without-sharing executor. Lead__c looks up the just-created Lead, which can
 *              be owned by a queue (MQL) the least-privilege integration user is not a
 *              member of; a sharing-enforced insert of that lookup failed silently (caught
 *              below, only debug-logged), leaving zero traceability for every real
 *              production request. Traceability must never silently fail regardless of
 *              which queue ends up owning the Lead.
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
     * @description System-mode executor for the log insert only. without sharing +
     *              SYSTEM_MODE on purpose: the insert must succeed regardless of whether the
     *              running user can see the Lead__c lookup target. It performs no reads and
     *              exposes nothing beyond persisting the already-built log record.
     */
    private without sharing class SystemModeLogWriter {
        /**
         * @description Inserts the log record bypassing sharing and FLS.
         * @param record populated log record
         */
        private void write(MGAgencia_Integration_Log__c record) {
            Database.insert(record, AccessLevel.SYSTEM_MODE);
        }
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
            new SystemModeLogWriter().write(record);
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
