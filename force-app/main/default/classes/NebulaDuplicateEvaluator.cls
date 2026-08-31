/**
 * @description Duplicate detection for API-created Leads (docs/DECISIONS.md, Decision 4).
 *              A Lead is a duplicate when an existing, non-converted, non-lost Lead matches
 *              on MobilePhone OR Email OR External_Lead_Id__c (only non-blank inputs are
 *              considered). Duplicates are never rejected — the caller creates the Lead and
 *              flags it. Single selective SOQL with bind variables, LIMIT 1, user mode.
 */
public with sharing class NebulaDuplicateEvaluator {
    /** @description Lead.Status value that marks a lost Lead in this org (see FIELD_MAPPING §9). */
    private static final String LOST_STATUS = 'Perdido';

    /** @description Evaluation outcome: duplicate flag plus the matched signal(s). */
    public class Result {
        public Boolean isDuplicate = false;
        public String reason;
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

        String soql = 'SELECT MobilePhone, Email, External_Lead_Id__c FROM Lead'
            + ' WHERE IsConverted = false AND Status != :lostStatus'
            + ' AND (' + String.join(conditions, ' OR ') + ') LIMIT 1';
        List<Lead> matches = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
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
