/**
 * @description Duplicate detection for API-created Leads (docs/DECISIONS.md, Decision 4).
 *              A Lead is a duplicate when an existing, non-converted, non-lost Lead matches
 *              on MobilePhone OR Email OR External_Lead_Id__c (only non-blank inputs are
 *              considered). Duplicates are never rejected — the caller creates the Lead and
 *              flags it. Single selective SOQL with bind variables, LIMIT 1.
 *
 *              SHARING MODEL (DEF-001): the duplicate scan — and ONLY the scan — runs in
 *              SYSTEM_MODE through a private without-sharing executor. Duplicate detection
 *              must compare against ALL existing Leads org-wide; the least-privilege
 *              integration user is not a member of the MGAgencia_Leads queue that owns
 *              API-created Leads, so a sharing-enforced query returns nothing and every
 *              duplicate is silently missed (defect DEF-001, found in provider UAT).
 *              Nothing from other records is exposed to the API consumer beyond the
 *              boolean duplicate flag and a generic reason code. Everything else in the
 *              integration (validation, DML, logging) stays in user mode.
 */
public with sharing class MGAgenciaDuplicateEvaluator {
    /** @description Lead.Status value that marks a lost Lead in this org (see FIELD_MAPPING §9). */
    private static final String LOST_STATUS = 'Perdido';

    /** @description Evaluation outcome: duplicate flag plus the matched signal(s). */
    public class Result {
        public Boolean isDuplicate = false;
        public String reason;
    }

    /**
     * @description System-mode executor for the duplicate scan only. without sharing +
     *              SYSTEM_MODE on purpose: the scan must see Leads the integration user
     *              cannot (queue-owned records under a private OWD). It reads only the
     *              fields the match logic needs and leaks nothing to the API response —
     *              the caller reduces the match to a boolean plus generic signal codes.
     */
    private without sharing class SystemModeDuplicateScanner {
        /**
         * @description Runs the duplicate SOQL bypassing sharing and FLS.
         * @param soql duplicate query (built from constant fragments + bind placeholders)
         * @param binds bind variable map
         * @return up to one matching Lead
         */
        private List<Lead> scan(String soql, Map<String, Object> binds) {
            return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * @description Evaluates the incoming contact signals against existing Leads.
     * @param phone incoming phone (compared to MobilePhone), may be blank
     * @param email incoming email, may be blank
     * @param externalLeadId incoming external_lead_id, may be blank
     * @return result with isDuplicate flag and a semicolon-separated reason string
     *         (MOBILE_PHONE_MATCH / EMAIL_MATCH / EXTERNAL_LEAD_ID_MATCH)
     */
    public static Result evaluate(String phone, String email, String externalLeadId) {
        Result result = new Result();
        List<String> conditions = new List<String>();
        Map<String, Object> binds = new Map<String, Object>{ 'lostStatus' => LOST_STATUS };

        if (String.isNotBlank(phone)) {
            conditions.add('MobilePhone = :phoneValue');
            binds.put('phoneValue', phone.trim());
        }
        if (String.isNotBlank(email)) {
            conditions.add('Email = :emailValue');
            binds.put('emailValue', email.trim());
        }
        if (String.isNotBlank(externalLeadId)) {
            conditions.add('External_Lead_Id__c = :externalIdValue');
            binds.put('externalIdValue', externalLeadId.trim());
        }
        if (conditions.isEmpty()) {
            return result;
        }

        String soql = 'SELECT Id, MobilePhone, Email, External_Lead_Id__c, Status, IsConverted FROM Lead'
            + ' WHERE IsConverted = false AND Status != :lostStatus'
            + ' AND (' + String.join(conditions, ' OR ') + ') LIMIT 1';
        List<Lead> matches = new SystemModeDuplicateScanner().scan(soql, binds);
        if (matches.isEmpty()) {
            return result;
        }

        Lead match = matches[0];
        List<String> signals = new List<String>();
        if (String.isNotBlank(phone) && match.MobilePhone == phone.trim()) {
            signals.add('MOBILE_PHONE_MATCH');
        }
        if (String.isNotBlank(email) && match.Email != null && match.Email.equalsIgnoreCase(email.trim())) {
            signals.add('EMAIL_MATCH');
        }
        if (String.isNotBlank(externalLeadId)
            && match.External_Lead_Id__c != null
            && match.External_Lead_Id__c.equalsIgnoreCase(externalLeadId.trim())) {
            signals.add('EXTERNAL_LEAD_ID_MATCH');
        }
        if (signals.isEmpty()) {
            // Defensive: SOQL matched (e.g. case-insensitive DB comparison) but exact re-check did not.
            signals.add('MATCH');
        }
        result.isDuplicate = true;
        result.reason = String.join(signals, ';');
        return result;
    }
}
