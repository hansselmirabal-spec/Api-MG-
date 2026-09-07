/**
 * @description Resolves/validates the MGAgencia contact_preference field against the actual
 *              Salesforce picklist values on Lead.Preferencia_de_contacto__c (3 active values,
 *              confirmed via `sf sobject describe -s Lead` on 2026-09-03). Unlike branch_code,
 *              MGAgencia's external value already matches the internal picklist label exactly
 *              (case-sensitive, with accents) — no code-to-label translation is needed, only
 *              validation. Kept as a dedicated resolver (rather than inline in the validator)
 *              to centralize the catalog per docs/CLAUDE.md mapping guidance.
 */
public with sharing class MGAgenciaContactPreferenceResolver {
    private static final Set<String> KNOWN_VALUES = new Set<String>{
        'Correo Electrónico',
        'WhatsApp',
        'Teléfono'
    };

    /**
     * @description Whether the given value is one of the 3 known picklist values.
     * @param contactPreference raw contact_preference from the request (may be null/blank)
     * @return true when the trimmed value matches a catalog entry exactly
     */
    public static Boolean isKnownValue(String contactPreference) {
        return String.isNotBlank(contactPreference) && KNOWN_VALUES.contains(contactPreference.trim());
    }

    /**
     * @description Resolves a contact_preference value to the Lead picklist value.
     * @param contactPreference raw contact_preference from the request
     * @return the trimmed value when known, or null when blank/unknown
     */
    public static String resolve(String contactPreference) {
        if (!isKnownValue(contactPreference)) {
            return null;
        }
        return contactPreference.trim();
    }
}
