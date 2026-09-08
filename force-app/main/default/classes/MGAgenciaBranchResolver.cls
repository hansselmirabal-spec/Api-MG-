/**
 * @description Resolves the MGAgencia branch_code catalog to a text label written to
 *              Lead.Sucursal_Seleccionada_Meta__c (docs/DECISIONS.md, Decision 7, amended
 *              2026-09-08). The external contract/catalog is unchanged: 4 Cóndor branches,
 *              same codes. Third-party dealers are out of scope for v1.
 *
 *              Label casing (2026-09-08): lowercase_with_underscores, matching the exact
 *              format real Meta-sourced Leads already write to this field and, critically,
 *              the format `Calendario_de_Asignaciones__c.Sucursal__c` uses. Confirmed by
 *              inspecting real Meta Leads in mi-org: they carry Sucursal_Seleccionada_Meta__c
 *              values like "asunción" / "ciudad_del_este", never title case — the earlier
 *              title-case choice (see git history) was our own styling decision, not
 *              something MGAgencia or the org required, and it caused
 *              Asignacion_Lead_a_Vendedor's "Asignación Lead a Vendedor según Calendario"
 *              sub-flow to never find an active shift (exact-text-match lookup), crashing
 *              any Lead that ever reached queue "Reglas Meta" (docs/ADMIN_FOLLOWUPS.md #5).
 *              Real Meta Leads never hit this because their casing already matches.
 */
public with sharing class MGAgenciaBranchResolver {
    private static final Map<String, String> BRANCH_BY_CODE = new Map<String, String>{
        'ASUNCION' => 'asunción',
        'CIUDAD_DEL_ESTE' => 'ciudad_del_este',
        'CORONEL_OVIEDO' => 'coronel_oviedo',
        'ENCARNACION' => 'encarnación'
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
