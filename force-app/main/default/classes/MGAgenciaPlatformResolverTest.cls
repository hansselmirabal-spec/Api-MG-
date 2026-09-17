/**
 * @description Pure unit tests for MGAgenciaPlatformResolver's catalog mapping. Deliberately
 *              no DML/Lead insert here — 'tiktok' resolves to LeadSource value 'Tiktok', which
 *              is active in mi-org but NOT in condor-qas as of 2026-09-15 (see class doc on
 *              MGAgenciaPlatformResolver). A live Lead insert with LeadSource='Tiktok' would
 *              fail in this sandbox for that reason, not a code defect — so tiktok's mapping is
 *              verified here at the resolver level only. fb/ig/web are additionally covered
 *              end-to-end via MGAgenciaLeadRestResourceTest, since those values are active in
 *              condor-qas today. fb/ig confirmed 2026-09-17 against a real MGAgencia historical
 *              lead export (see MGAgenciaPlatformResolver's class doc) — the originally assumed
 *              facebook/instagram spelling never appears in real traffic.
 */
@IsTest
private class MGAgenciaPlatformResolverTest {
    @IsTest
    static void knownPlatformsResolveToExpectedLeadSource() {
        System.assertEquals('Redes Sociales Empresa', MGAgenciaPlatformResolver.resolve('fb'),
            'fb resolves to Redes Sociales Empresa');
        System.assertEquals('Redes Sociales Empresa', MGAgenciaPlatformResolver.resolve('ig'),
            'ig resolves to Redes Sociales Empresa');
        System.assertEquals('Web', MGAgenciaPlatformResolver.resolve('web'), 'web resolves to Web');
        System.assertEquals('Tiktok', MGAgenciaPlatformResolver.resolve('tiktok'),
            'tiktok resolves to Tiktok (exact casing confirmed active in mi-org)');
    }

    @IsTest
    static void isKnownValueMatchesOnlyTheApprovedCatalog() {
        System.assertEquals(true, MGAgenciaPlatformResolver.isKnownValue('fb'));
        System.assertEquals(true, MGAgenciaPlatformResolver.isKnownValue('tiktok'));
        System.assertEquals(false, MGAgenciaPlatformResolver.isKnownValue('linkedin'), 'Unknown platform');
        System.assertEquals(false, MGAgenciaPlatformResolver.isKnownValue('facebook'),
            'The originally assumed spelling is not the real value MGAgencia sends');
        System.assertEquals(false, MGAgenciaPlatformResolver.isKnownValue('FB'), 'Case-sensitive match only');
        System.assertEquals(false, MGAgenciaPlatformResolver.isKnownValue(null), 'Null is not a known value');
        System.assertEquals(false, MGAgenciaPlatformResolver.isKnownValue(''), 'Blank is not a known value');
    }

    @IsTest
    static void resolveReturnsNullForBlankOrUnknownInput() {
        System.assertEquals(null, MGAgenciaPlatformResolver.resolve(null), 'Null input resolves to null');
        System.assertEquals(null, MGAgenciaPlatformResolver.resolve(''), 'Blank input resolves to null');
        System.assertEquals(null, MGAgenciaPlatformResolver.resolve('linkedin'), 'Unknown platform resolves to null');
    }

    @IsTest
    static void resolveTrimsSurroundingWhitespace() {
        System.assertEquals('Web', MGAgenciaPlatformResolver.resolve('  web  '), 'Surrounding whitespace is trimmed');
    }
}
