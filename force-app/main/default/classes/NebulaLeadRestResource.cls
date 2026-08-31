/**
 * @description Apex REST endpoint for Nebüla Lead creation:
 *              POST /services/apexrest/nebula/v1/leads (docs/API_SPEC.md).
 *              Transport only — parses the body, delegates to NebulaLeadService, sets the
 *              HTTP status code and serializes the response DTO. No business logic here.
 *              Authentication (401/403) is handled by the platform (OAuth), not this class.
 */
@RestResource(urlMapping='/nebula/v1/leads')
global with sharing class NebulaLeadRestResource {
    /**
     * @description Handles the POST request. Malformed/unreadable bodies short-circuit to 400
     *              before the service runs; every other outcome comes from the service.
     */
    @HttpPost
    global static void createLead() {
        Long startMs = System.currentTimeMillis();
        Datetime receivedAt = System.now();
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        NebulaLeadRequest requestDto;
        try {
            String body = RestContext.request.requestBody == null
                ? null
                : RestContext.request.requestBody.toString();
            requestDto = NebulaLeadRequest.parse(body);
        } catch (NebulaMalformedRequestException e) {
            NebulaIntegrationLogger.logMalformedRequest(receivedAt, startMs);
            write(response, 400, NebulaLeadResponse.malformedRequest());
            return;
        }

        NebulaLeadService.Result result = NebulaLeadService.process(requestDto);
        write(response, result.statusCode, result.response);
    }

    /**
     * @description Serializes the response DTO, suppressing null properties per contract.
     * @param response RestContext response to write to
     * @param statusCode HTTP status code
     * @param payload consumer-safe response DTO
     */
    private static void write(RestResponse response, Integer statusCode, NebulaLeadResponse payload) {
        response.statusCode = statusCode;
        response.responseBody = Blob.valueOf(JSON.serialize(payload, true));
    }
}
