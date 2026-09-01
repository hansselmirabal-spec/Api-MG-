/**
 * @description Resolves the MGAgencia branch_code catalog to Lead.Nearest_Branch__c picklist
 *              values (docs/DECISIONS.md, Decision 7). The catalog is fixed by the approved
 *              contract: 4 Cóndor branches. Third-party dealers are out of scope for v1.
 */
public with sharing class MGAgenciaBranchResolver {
    private static final Map<String, String> BRANCH_BY_CODE = new Map<String, String>{
        'ASUNCION' => 'ASUNCIÓN',
        'CIUDAD_DEL_ESTE' => 'CIUDAD DEL ESTE',
        'CORONEL_OVIEDO' => 'CORONEL OVIEDO',
        'ENCARNACION' => 'ENCARNACIÓN'
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
     * @description Resolves a branch code to its Nearest_Branch__c picklist value.
     * @param branchCode raw branch_code from the request
     * @return picklist value, or null when the code is blank or unknown
     */
    public static String resolve(String branchCode) {
        if (String.isBlank(branchCode)) {
            return null;
        }
        return BRANCH_BY_CODE.get(branchCode.trim());
    }
}
