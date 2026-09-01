/**
 * @description Phone normalization for the MGAgencia Lead endpoint. Replicates, faithfully, the
 *              rule the org flow `DatosInicialesProspecto` ("Limpiar Teléfono (Siempre)")
 *              applies to Lead.MobilePhone after insert:
 *              1. Strip "+", spaces, "-", "(" and ")".
 *              2. If the result starts with "0" (Paraguayan local format), replace that
 *                 leading "0" with the country code: "595" + rest.
 *              3. Any other input (already-normalized 595…, foreign numbers, odd values)
 *                 passes through unchanged after step 1 — same as the flow.
 *              Applying it BEFORE duplicate matching and BEFORE storing MobilePhone keeps
 *              our comparison and stored value aligned with the org convention immediately,
 *              instead of only after the flow rewrites the record.
 */
public with sharing class MGAgenciaPhoneNormalizer {
    /**
     * @description Normalizes a phone number using the org flow's exact rule.
     * @param phone raw incoming phone; may be null or blank
     * @return normalized phone; null/blank input is returned as-is (validation handles it)
     */
    public static String normalize(String phone) {
        if (String.isBlank(phone)) {
            return phone;
        }
        String cleaned = phone.trim()
            .replace('+', '')
            .replace(' ', '')
            .replace('-', '')
            .replace('(', '')
            .replace(')', '');
        if (cleaned.startsWith('0')) {
            return '595' + cleaned.substring(1);
        }
        return cleaned;
    }
}
