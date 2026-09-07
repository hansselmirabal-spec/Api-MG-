/**
 * @description Resolves the MGAgencia branch_code catalog to a text label written to
 *              Lead.Sucursal_Seleccionada_Meta__c (docs/DECISIONS.md, Decision 7, amended
 *              2026-09-03). The external contract/catalog is unchanged: 4 Cóndor branches,
 *              same codes. Only the internal target field and label casing changed — labels
 *              now match the MGAgencia form methodology (title case) rather than the
 *              Nearest_Branch__c picklist's all-caps values. Third-party dealers are out of
 *              scope for v1.
 *
 *              Verified safe: flow Asignacion_Lead_a_Vendedor reads Sucursal_Seleccionada_Meta__c
 *              but only fires when Lead OwnerId = queue "Reglas Meta"; MGAgencia Leads are
 *              always owned by queue "MGAgencia Leads", so this write is inert beyond storage.
 */
public with sharing class MGAgenciaBranchResolver {
    private static final Map<String, String> BRANCH_BY_CODE = new Map<String, String>{
        'ASUNCION' => 'Asunción',
        'CIUDAD_DEL_ESTE' => 'Ciudad del Este',
        'CORONEL_OVIEDO' => 'Coronel Oviedo',
        'ENCARNACION' => 'Encarnación'
    };

    /**
     * @description Whether the given code belongs to the approved branch catalog.
     * @param branchCode raw branch_code from the request (may be null/blank)
     * @return true when the trimmed code matches a catalog entry
     */
    public static Boolean isKnownCode(String branchCode) {
        return String.isNotBlank(branchCode) && BRANCH_BY_CODE.containsKey(branchCode.trim());
    }

    /**
     * @description Resolves a branch code to its Sucursal_Seleccionada_Meta__c text label.
     * @param branchCode raw branch_code from the request
     * @return text label, or null when the code is blank or unknown
     */
    public static String resolve(String branchCode) {
        if (String.isBlank(branchCode)) {
            return null;
        }
        return BRANCH_BY_CODE.get(branchCode.trim());
    }
}
