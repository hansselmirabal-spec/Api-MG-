# Instructivo de ejecución UAT — MGAgencia Leads API

**Fecha:** 2026-09-01 · **Elaborado por:** Grupo Cóndor · Complemento de la *Especificación Funcional v1.0*

---

## 1. Archivos necesarios

| Archivo | Uso |
|---|---|
| `MGAGENCIA_UAT.postman_collection.json` | Colección con los 6 escenarios UAT (UAT-1 a UAT-6) |
| `MGAGENCIA_UAT_SANDBOX.postman_environment.json` | Variables del entorno sandbox (`base_url`, `token_url`, `client_id`, `client_secret`) |

**Importante:** utilizar los archivos exactamente como fueron entregados. La colección **no** contiene ningún request de token separado: el token OAuth se obtiene automáticamente mediante un *pre-request script* a nivel de colección. Si aparece un request adicional (por ejemplo "00 — Get access token"), la colección fue modificada y debe re-importarse desde el archivo original.

## 2. Instalación paso a paso

1. En Postman: **Import** → seleccionar los dos archivos JSON.
2. Arriba a la derecha, seleccionar el environment **"MGAgencia UAT — Sandbox"** (si queda en "No environment", ninguna variable se resuelve y la autenticación falla).
3. Abrir el environment y completar **únicamente** `client_secret` con el valor entregado por canal seguro. El `client_id` ya viene precargado. No renombrar, borrar ni agregar variables.
4. Ejecutar con **Collection Runner**: seleccionar la colección completa y correr los 6 requests **en orden** (UAT-2 depende de datos generados por UAT-1).

## 3. Resultado esperado

| Escenario | HTTP esperado | Verificación automática |
|---|---|---|
| UAT-1 · Lead válido | 201 | `integration_id` UUID, `duplicated: false` |
| UAT-2 · Teléfono duplicado (formato 595) | 201 | `duplicated: true` |
| UAT-3 · Faltan `first_name` y `phone` | 422 | Ambos errores reportados juntos |
| UAT-4 · `branch_code` desconocido | 422 | Código `UNKNOWN_VALUE` |
| UAT-5 · JSON malformado | 400 | Código `MALFORMED_REQUEST` |
| UAT-6 · Sin token | 401 | Rechazo de la plataforma |

Total: 6 requests. Todos los tests en verde.

## 4. Resolución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| `invalid_client_id` al obtener token | Variables renombradas, environment no seleccionado, o `client_id` alterado — Postman envía el texto literal `{{client_id}}` | Re-importar los archivos originales; verificar environment seleccionado; abrir la consola (Ctrl+Alt+C / Cmd+Alt+C) y revisar el body real del request de token |
| `invalid_grant: request not supported on this domain` | Se cambió `token_url` | Debe ser `https://condorsaci--qas.sandbox.my.salesforce.com/services/oauth2/token` (no `test.salesforce.com`) |
| `invalid_grant: authentication failure` | `client_secret` incorrecto o con espacios | Volver a pegar el valor sin espacios ni saltos de línea |
| Todos los requests dan 401 en cascada | El token nunca se obtuvo (ver primer síntoma) | Resolver la autenticación primero; los demás fallos son consecuencia |
| UAT-2 no marca duplicado | Se ejecutó de forma aislada | Correr la colección completa en orden con el Runner |

## 5. Reglas

- **No modificar los tests ni las aserciones** para que "pasen". Si un test falla, el resultado es información valiosa: reportarlo a Grupo Cóndor con el output del Runner y el contenido de la consola.
- Se recomienda **desactivar el asistente de IA de Postman** para esta colección: sus modificaciones automáticas (renombrar variables, reescribir aserciones) invalidan la ejecución.
- Las credenciales son **exclusivas del sandbox** y no deben compartirse ni versionarse. Ante cualquier exposición accidental, avisar a Grupo Cóndor para rotarlas.

## 6. Soporte

Ante fallas no cubiertas por la tabla anterior, enviar a Grupo Cóndor: (1) export del resultado del Runner, (2) captura de la consola de Postman del request fallido (sin incluir el `client_secret`), (3) fecha y hora de la ejecución. El `integration_id` de cada respuesta permite rastrear la solicitud en nuestros registros.
