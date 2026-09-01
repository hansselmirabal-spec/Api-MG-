/**
 * @description Raised when the MGAgencia_Integration_Setting__mdt configuration is missing,
 *              inactive, or references metadata that cannot be resolved (e.g. record type).
 *              Surfaces to the consumer as a generic 500 response.
 */
public class MGAgenciaConfigurationException extends MGAgenciaIntegrationException {
}
