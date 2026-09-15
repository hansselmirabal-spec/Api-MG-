/**
 * @description Resolves the MGAgencia platform field (origin of the lead) to Lead.LeadSource
 *              (docs/DECISIONS.md, 2026-09-15, admin/mkt request "Cambios MG Agencia.docx").
 *              PROVISIONAL: this contract addition is pending MGAgencia confirming they can
 *              send `platform`. `platform` is optional; when absent, MGAgenciaLeadService keeps
 *              using the fixed LeadSource from MGAgencia_Integration_Setting__mdt.Lead_Source__c
 *              exactly as before — no change to current production behavior.
 *
 *              Values are matched case-sensitively against the exact lowercase strings agreed
 *              with the business (facebook, instagram, tiktok, web).
 *
 *              'Tiktok' casing note: confirmed active in mi-org's LeadSource picklist (exact
 *              string "Tiktok", capital T only) via `sf sobject describe` on 2026-09-15.
 *              condor-qas does NOT have this value active as of the same date (sandbox is stale
 *              on this specific value, same class of drift as Decision 7's branch-casing bug) —
 *              a live end-to-end sandbox test that inserts a Lead with platform=tiktok will fail
 *              in condor-qas for that reason, not because of a code defect. Add "Tiktok" to
 *              condor-qas's LeadSource picklist before relying on a full live sandbox test.
 */
public with sharing class MGAgenciaPlatformResolver {
    private static final Map<String, String> LEAD_SOURCE_BY_PLATFORM = new Map<String, String>{
        'facebook' => 'Redes Sociales Empresa',
        'instagram' => 'Redes Sociales Empresa',
        'tiktok' => 'Tiktok',
        'web' => 'Web'
    };

    /**
     * @description Whether the given platform value belongs to the approved catalog.
     * @param platform raw platform from the request (may be null/blank)
     * @return true when the trimmed value matches a catalog entry exactly (case-sensitive)
     */
    public static Boolean isKnownValue(String platform) {
        return String.isNotBlank(platform) && LEAD_SOURCE_BY_PLATFORM.containsKey(platform.trim());
    }

    /**
     * @description Resolves a platform value to its Lead.LeadSource value.
     * @param platform raw platform from the request
     * @return LeadSource value, or null when the platform is blank or unknown
     */
    public static String resolve(String platform) {
        if (String.isBlank(platform)) {
            return null;
        }
        return LEAD_SOURCE_BY_PLATFORM.get(platform.trim());
    }
}
