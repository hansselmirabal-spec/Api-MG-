/**
 * @description Unit tests for NebulaPhoneNormalizer. Pure function, no DML — asserts the
 *              exact rule of the org flow `DatosInicialesProspecto` (see class docs).
 */
@IsTest
private class NebulaPhoneNormalizerTest {
    @IsTest
    static void localFormatLeadingZeroBecomes595() {
        System.assertEquals('595981123456', NebulaPhoneNormalizer.normalize('0981123456'),
            'Leading 0 is replaced by country code 595');
    }

    @IsTest
    static void alreadyNormalizedInputIsUnchanged() {
        System.assertEquals('595981123456', NebulaPhoneNormalizer.normalize('595981123456'),
            'Already-normalized input passes through unchanged');
    }

    @IsTest
    static void formattingCharactersAreStripped() {
        System.assertEquals('595981123456', NebulaPhoneNormalizer.normalize('+595 (981) 123-456'),
            'Plus, spaces, dashes and parentheses are stripped');
        System.assertEquals('595981123456', NebulaPhoneNormalizer.normalize('0981 123 456'),
            'Local format with spaces is cleaned then prefixed');
    }

    @IsTest
    static void nonParaguayanInputPassesThroughAfterCleaning() {
        // Documented behavior: the flow does not validate country codes. Foreign or odd
        // input is only stripped of formatting characters and passed through as-is.
        System.assertEquals('12025550147', NebulaPhoneNormalizer.normalize('+1 (202) 555-0147'),
            'Foreign number is cleaned but not rewritten');
        System.assertEquals('abc', NebulaPhoneNormalizer.normalize('abc'),
            'Non-numeric input passes through');
    }

    @IsTest
    static void blankInputIsReturnedAsIs() {
        System.assertEquals(null, NebulaPhoneNormalizer.normalize(null), 'Null passes through');
        System.assertEquals('', NebulaPhoneNormalizer.normalize(''), 'Empty passes through');
    }
}
