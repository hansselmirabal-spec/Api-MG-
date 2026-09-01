# Nebüla → Salesforce Leads API — Especificación Funcional v1.0 (borrador para revisión del proveedor)

**Fecha:** 2026-09-01
**Elaborado por:** Grupo Cóndor

---

## 1. Descripción general

**Propósito.** Nebüla recopila leads publicitarios desde plataformas de marketing y los envía al CRM de Grupo Cóndor (Salesforce) para que sean trabajados por el equipo comercial, sin carga manual de datos.

**Flujo**

```
Nebüla  --HTTPS POST-->  API de Salesforce
                              |
                              v
                        Validación de campos
                              |
                              v
                        Creación del Lead (+ marca de duplicado si corresponde)
                              |
                              v
                        Respuesta JSON  -->  Nebüla
```

**Política de versionado.** El contrato actual es **v1**. Cualquier cambio disruptivo (campos eliminados o renombrados, cambios en los códigos de estado, cambios de semántica) se publicará como una nueva versión (por ejemplo, `v2`) con su propia ruta de endpoint. Las adiciones no disruptivas (nuevos campos opcionales, nuevos valores de catálogo) podrán incorporarse dentro de v1.

---

## 2. Entornos

| Entorno | URL base | Notas |
|---|---|---|
| Sandbox (UAT) | `https://condorsaci--qas.sandbox.my.salesforce.com` | Para pruebas de integración antes del pase a producción. |
| Producción | *A confirmar en el momento del go-live* | Se compartirá una vez aprobado el UAT. |

| Elemento | Valor |
|---|---|
| Ruta del endpoint | `/services/apexrest/nebula/v1/leads` |
| Método HTTP | `POST` |
| Content-Type | `application/json; charset=UTF-8` |
| Transporte | Solo HTTPS |

---

## 3. Autenticación

**Tipo de concesión:** OAuth 2.0 **Client Credentials**.

| Entorno | Endpoint de token |
|---|---|
| Sandbox | `https://test.salesforce.com/services/oauth2/token` |
| Producción | `https://login.salesforce.com/services/oauth2/token` |

Parámetros de la solicitud (`application/x-www-form-urlencoded`):

| Parámetro | Valor |
|---|---|
| `grant_type` | `client_credentials` |
| `client_id` | Provisto por Grupo Cóndor |
| `client_secret` | Provisto por Grupo Cóndor |

Las credenciales (`client_id` / `client_secret`) serán entregadas por Grupo Cóndor a través de un canal seguro (por ejemplo, un gestor de contraseñas compartido). **Nunca se enviarán por correo electrónico ni chat en texto plano.** La entrega está pendiente de completar el aprovisionamiento del Connected App de nuestro lado.

Toda solicitud a la API debe incluir el token de acceso:

```
Authorization: Bearer <access_token>
```

**Expiración y renovación del token.** Los tokens expiran según la política de sesión de la organización. Nebüla debe solicitar un nuevo token cuando una solicitud falle con `401 Unauthorized`, en lugar de almacenar el token indefinidamente o asumir una vigencia fija.

**Ejemplo**

```bash
# 1. Obtener un token de acceso
curl -s -X POST "https://test.salesforce.com/services/oauth2/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=<CLIENT_ID>" \
  -d "client_secret=<CLIENT_SECRET>"

# 2. Enviar un lead
curl -s -X POST "https://condorsaci--qas.sandbox.my.salesforce.com/services/apexrest/nebula/v1/leads" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "Maria",
    "last_name": "Gonzalez",
    "phone": "0981123456",
    "email": "maria.gonzalez@example.com",
    "branch_code": "ASUNCION"
  }'
```

> Las credenciales están **pendientes de entrega** hasta completar el aprovisionamiento del Connected App. Esta sección describe el mecanismo objetivo ya confirmado; el `client_id`/`client_secret` de sandbox se entregará a continuación.

---

## 4. Especificación de la solicitud

Un objeto JSON por solicitud. Sin agrupación por lote/arreglo. Las propiedades desconocidas enviadas por Nebüla son ignoradas (no rechazadas).

| Campo | Tipo | Obligatorio | Longitud máxima | Formato | Descripción | Ejemplo |
|---|---|---|---|---|---|---|
| `first_name` | string | Sí | — | No vacío luego de recortar espacios | Nombre del lead. | `"Maria"` |
| `last_name` | string | Sí | — | No vacío luego de recortar espacios | Apellido del lead. | `"Gonzalez"` |
| `phone` | string | Sí | — | Número de celular paraguayo | Se acepta en formato local (`0981123456`) o internacional (`595981123456`). Se normaliza del lado del servidor a un único formato canónico antes de almacenarlo y de evaluar duplicados. | `"0981123456"` |
| `email` | string | No | — | Formato de correo electrónico estándar | Correo de contacto opcional. | `"maria.gonzalez@example.com"` |
| `branch_code` | string | No | — | Uno de los valores de catálogo indicados abajo | Sucursal de Cóndor preferida. Omitir el campo es válido; un valor no reconocido es rechazado. | `"ASUNCION"` |
| `external_lead_id` | string | No *(ver preguntas abiertas)* | — | Texto libre | Identificador único que Nebüla puede asignar a un lead. No es obligatorio hoy; si pasará a ser obligatorio y usarse como clave de idempotencia está abierto — ver §10. | `"neb-2026-0000123"` |

**Catálogo de `branch_code`**

| Valor |
|---|
| `ASUNCION` |
| `CIUDAD_DEL_ESTE` |
| `CORONEL_OVIEDO` |
| `ENCARNACION` |

### 4.1 Ejemplo de solicitud

```json
{
  "first_name": "Maria",
  "last_name": "Gonzalez",
  "phone": "0981123456",
  "email": "maria.gonzalez@example.com",
  "branch_code": "ASUNCION",
  "external_lead_id": "neb-2026-0000123"
}
```

---

## 5. Especificación de la respuesta

### 5.1 Éxito — `201 Created`

| Campo | Tipo | Descripción |
|---|---|---|
| `code` | string | Código de resultado legible por máquina (`LEAD_CREATED`). |
| `status` | string | `success`. |
| `message` | string | Resumen legible por humanos. |
| `integration_id` | string (UUID) | Identificador de referencia de esta solicitud. **Nebüla debe almacenarlo** para solicitudes de soporte. No es un identificador de registro de Salesforce. |
| `duplicated` | boolean | `true` si este lead coincidió con uno existente (ver §7). |

```json
{
  "code": "LEAD_CREATED",
  "status": "success",
  "message": "Lead created successfully.",
  "integration_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "duplicated": false
}
```

### 5.2 Formato de error

Todas las respuestas de error comparten esta estructura. Cuando el fallo es a nivel de campo, `errors[]` reporta **todos** los problemas encontrados en una sola pasada, no solo el primero.

| Campo | Tipo | Descripción |
|---|---|---|
| `code` | string | Código de resultado legible por máquina. |
| `status` | string | `error`. |
| `message` | string | Resumen legible por humanos, seguro para registrar en logs. Nunca un error interno crudo. |
| `errors` | array | Presente cuando el fallo es a nivel de campo. Cada elemento tiene `field`, `code`, `message`. |

```json
{
  "code": "VALIDATION_ERROR",
  "status": "error",
  "message": "One or more fields failed validation.",
  "errors": [
    { "field": "last_name", "code": "REQUIRED", "message": "last_name is required." },
    { "field": "phone", "code": "REQUIRED", "message": "phone is required." }
  ]
}
```

### 5.3 Catálogo de errores

| Estado HTTP | `code` | Significado |
|---|---|---|
| `400` | `MALFORMED_REQUEST` | Cuerpo ausente, no es JSON válido, o no es un objeto JSON. No se intenta validación de campos. |
| `401` | *(error de autenticación)* | Token de acceso ausente o inválido. |
| `403` | *(error de autenticación)* | Token válido, pero sin autorización para esta operación. |
| `422` | `VALIDATION_ERROR` con subcódigo `REQUIRED` | Un campo obligatorio está ausente o vacío. |
| `422` | `VALIDATION_ERROR` con subcódigo `INVALID_FORMAT` | Un campo no coincide con el formato esperado (por ejemplo, `email`). |
| `422` | `VALIDATION_ERROR` con subcódigo `UNKNOWN_VALUE` | El valor de un campo no está en su catálogo (por ejemplo, un `branch_code` no reconocido). |
| `500` | `INTERNAL_ERROR` | Fallo de procesamiento inesperado de nuestro lado. Nunca incluye trazas de pila ni texto de error interno. |

**Ejemplo — `400` JSON malformado**

```json
{
  "code": "MALFORMED_REQUEST",
  "status": "error",
  "message": "Request body is not valid JSON."
}
```

**Ejemplo — `422` código de sucursal desconocido**

```json
{
  "code": "VALIDATION_ERROR",
  "status": "error",
  "message": "One or more fields failed validation.",
  "errors": [
    { "field": "branch_code", "code": "UNKNOWN_VALUE", "message": "branch_code does not match a known branch." }
  ]
}
```

---

## 6. Manejo de duplicados

Los leads duplicados **nunca son rechazados**. Si un lead entrante coincide con uno existente, igualmente se crea, y la respuesta devuelve `"duplicated": true`.

**Señales de coincidencia:** `phone` normalizado, o `email`, o `external_lead_id` cuando se provee.

Nebüla no necesita tomar ninguna acción correctiva ante una respuesta de duplicado; queda marcado internamente para reportes. Aun así, Nebüla debe evitar reintentar una solicitud ya exitosa sin control, ya que actualmente toda solicitud aceptada crea un nuevo registro de lead (ver la nota de idempotencia en §10, punto 1).

---

## 7. Comportamiento operativo

| Tema | Recomendación |
|---|---|
| Timeout | Configurar un timeout razonable del lado del cliente (por ejemplo, 30 segundos) por solicitud. |
| Reintentos | Reintentar únicamente ante respuestas `5xx`, con espera incremental entre intentos. **No** reintentar respuestas `4xx`: indican que la solicitud misma debe corregirse, no reenviarse tal cual. |
| Límites de tasa | Aún no definidos — ver pregunta abierta en §10. |
| Trazabilidad para soporte | Registrar siempre el `integration_id` devuelto en caso de éxito. Es necesario para localizar una solicitud al contactar a Grupo Cóndor por soporte. |

---

## 8. Plan de UAT para Nebüla

Ejecutar los siguientes escenarios contra el entorno sandbox antes del pase a producción:

| # | Escenario | Resultado esperado |
|---|---|---|
| 1 | Lead válido con todos los campos | `201`, `code: LEAD_CREATED`, `duplicated: false`. |
| 2 | Lead duplicado (mismo teléfono/email/`external_lead_id` que uno anterior) | `201`, `code: LEAD_CREATED`, `duplicated: true`. |
| 3 | Falta uno o más campos obligatorios (`first_name`, `last_name` o `phone`) | `422`, `code: VALIDATION_ERROR`, `errors[]` lista todos los campos faltantes. |
| 4 | `branch_code` inválido (fuera de catálogo) | `422`, `code: VALIDATION_ERROR`, `errors[].code: UNKNOWN_VALUE`. |
| 5 | Cuerpo JSON malformado | `400`, `code: MALFORMED_REQUEST`. |
| 6 | Solicitud sin token de acceso válido | `401`. |

---

## 9. Preguntas abiertas para Nebüla

| # | Pregunta | Por qué importa | Respuesta propuesta |
|---|---|---|---|
| 1 | ¿Pueden enviar un `external_lead_id` único por lead? | Si se confirma, pasará a ser un campo **obligatorio** y la clave de idempotencia para reintentos seguros (evitando la creación duplicada al reenviar). | Sí — Nebüla asigna y envía un `external_lead_id` estable y único por lead. |
| 2 | ¿Cómo identifican las campañas publicitarias? | Necesario para atribuir leads a campañas en los reportes. | Nebüla envía un `campaign_code` de un catálogo acordado con Grupo Cóndor; nosotros lo resolvemos internamente. |
| 3 | ¿Necesitan enviar el modelo de vehículo de interés? | Necesario para enrutar y reportar leads según el interés de producto. | Nebüla envía un valor `interest_model` de un catálogo que provee Grupo Cóndor. |
| 4 | ¿Necesitan consultar el estado del lead luego de creado, o la respuesta de creación es suficiente? | Determina si se necesita un endpoint `GET` de estado en una fase futura. | La respuesta síncrona de creación (`integration_id`, `duplicated`) es suficiente para v1; no se planea un endpoint `GET` salvo que se confirme lo contrario. |
| 5 | ¿Qué volumen de solicitudes esperan (leads/día, pico)? | Necesario para dimensionar el endpoint y definir límites de tasa. | Por favor compartir los volúmenes promedio y pico esperados. |

---

## 10. Soporte y gestión de cambios

| Elemento | Detalle |
|---|---|
| Contacto | *[Contacto de integración de Grupo Cóndor — a confirmar]* |
| Comunicación de cambios | Todo cambio a este contrato (campos nuevos o modificados, códigos de estado o comportamiento) se comunicará a Nebüla por escrito antes de su despliegue. Los cambios disruptivos se publican bajo una nueva versión de la API (§1); los cambios no disruptivos se documentan como una actualización de esta especificación. |

---

*Fin del documento.*
