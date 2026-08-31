/**
 * @description Raised by the transport layer when the request body is empty, not valid JSON,
 *              or not a JSON object. Mapped to an HTTP 400 response.
 */
public class NebulaMalformedRequestException extends NebulaIntegrationException {
}
