#!/usr/bin/env bash
#
# MGAgencia -> Grupo Condor Leads API v1 - UAT runner
# Executes the 6 scenarios from section 8 of the functional specification.
#
# Credentials are read interactively and never written to disk, exported,
# or placed in a command line, so they do not reach the shell history or
# the process table.
#
# Usage:  bash uat-run.sh          (sandbox, default)
#         ENV=prod bash uat-run.sh (production, after go-live)

set -uo pipefail

if [ "${ENV:-sandbox}" = "prod" ]; then
  BASE_URL="https://condorsaci.my.salesforce.com"
  TOKEN_URL="https://login.salesforce.com/services/oauth2/token"
else
  BASE_URL="https://condorsaci--qas.sandbox.my.salesforce.com"
  TOKEN_URL="https://test.salesforce.com/services/oauth2/token"
fi

LEADS_URL="${BASE_URL}/services/apexrest/mgagencia/v1/leads"

PASS=0
FAIL=0

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }
dim()   { printf '\033[2m%s\033[0m' "$1"; }

# check <description> <actual> <expected>
check() {
  if [ "$2" = "$3" ]; then
    printf '    %s %s\n' "$(green PASS)" "$1"
    PASS=$((PASS + 1))
  else
    printf '    %s %s\n         esperado: %s\n         obtenido: %s\n' \
      "$(red FAIL)" "$1" "$3" "$2"
    FAIL=$((FAIL + 1))
  fi
}

# post <body> <use_token: yes|no>  -> sets HTTP_CODE and BODY
post() {
  local body="$1" use_token="$2" auth=()
  [ "$use_token" = "yes" ] && auth=(-H "Authorization: Bearer ${ACCESS_TOKEN}")

  local raw
  raw=$(curl -s -S --max-time 30 -w $'\n%{http_code}' -X POST "$LEADS_URL" \
        -H "Content-Type: application/json; charset=UTF-8" \
        "${auth[@]}" -d "$body" 2>&1)

  HTTP_CODE="${raw##*$'\n'}"
  BODY="${raw%$'\n'*}"
}

# field <jq_expr> -> prints value, or the literal string ABSENT
#
# Note: jq's `//` operator is deliberately NOT used here. It treats `false`
# as absent, so `.duplicated // "ABSENT"` would report ABSENT on a valid
# `"duplicated": false` response and fail scenario 01 for the wrong reason.
field() {
  local out
  out=$(printf '%s' "$BODY" | jq -r "$1" 2>/dev/null)
  if [ -z "$out" ] || [ "$out" = "null" ]; then
    printf 'ABSENT'
  else
    printf '%s' "$out"
  fi
}

echo
echo "MGAgencia -> Condor Leads API v1 - UAT"
echo "Entorno : ${ENV:-sandbox}"
echo "Endpoint: ${LEADS_URL}"
echo

# ---------------------------------------------------------------- credentials
printf 'client_id     : '
read -r CLIENT_ID
printf 'client_secret : '
read -rs CLIENT_SECRET
echo
echo

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
  echo "$(red 'Faltan credenciales.') Aborto."
  exit 1
fi

# --------------------------------------------------- 00 - obtain access token
echo "00 - Obtener access token"

TOKEN_RAW=$(curl -s -S --max-time 30 -w $'\n%{http_code}' -X POST "$TOKEN_URL" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}" 2>&1)

unset CLIENT_SECRET

TOKEN_CODE="${TOKEN_RAW##*$'\n'}"
TOKEN_BODY="${TOKEN_RAW%$'\n'*}"

check "HTTP 200" "$TOKEN_CODE" "200"

ACCESS_TOKEN=$(printf '%s' "$TOKEN_BODY" | jq -r '.access_token // empty' 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
  ERR=$(printf '%s' "$TOKEN_BODY" | jq -r '.error // "?"' 2>/dev/null)
  DESC=$(printf '%s' "$TOKEN_BODY" | jq -r '.error_description // "?"' 2>/dev/null)

  echo
  echo "$(red 'No se obtuvo token.')  error=${ERR}"
  echo "  ${DESC}"
  echo
  case "$ERR" in
    unsupported_grant_type)
      echo "  -> Falta tildar 'Enable Client Credentials Flow' en la Connected App." ;;
    invalid_grant)
      echo "  -> Falta designar el 'Run As' user en la Policy de la Connected App." ;;
    invalid_client|invalid_client_id)
      echo "  -> client_id/client_secret incorrectos, o el endpoint no corresponde"
      echo "     al entorno (sandbox usa test.salesforce.com, prod login.salesforce.com)." ;;
  esac
  echo
  exit 1
fi

echo "    $(dim "token obtenido (${#ACCESS_TOKEN} chars)")"
echo

# ------------------------------------- identity shared by scenarios 01 and 02
SUFFIX=$(( RANDOM % 9000 + 1000 ))$(( RANDOM % 9000 + 1000 ))
UAT_PHONE="09${SUFFIX}"
UAT_EMAIL="uat.${SUFFIX}@example.com"
UAT_EXTID="uat-${SUFFIX}"

LEAD_JSON=$(cat <<EOF
{
  "first_name": "Maria",
  "last_name": "Gonzalez",
  "phone": "${UAT_PHONE}",
  "email": "${UAT_EMAIL}",
  "branch_code": "ASUNCION",
  "external_lead_id": "${UAT_EXTID}"
}
EOF
)

# ------------------------------------------------------ 01 - valid lead (new)
echo "01 - Lead valido, todos los campos"
post "$LEAD_JSON" yes
check "HTTP 201"            "$HTTP_CODE"                "201"
check "code = LEAD_CREATED" "$(field '.code')"          "LEAD_CREATED"
check "status = success"    "$(field '.status')"        "success"
check "duplicated = false"  "$(field '.duplicated')"    "false"

INTEGRATION_ID=$(field '.integration_id')
if printf '%s' "$INTEGRATION_ID" | grep -Eiq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
  check "integration_id es UUID" "ok" "ok"
else
  check "integration_id es UUID" "$INTEGRATION_ID" "un UUID"
fi
echo "    $(dim "integration_id: ${INTEGRATION_ID}")"
echo

# ---------------------------------------------------- 02 - duplicate of above
echo "02 - Lead duplicado (mismo phone/email/external_lead_id)"
post "$LEAD_JSON" yes
check "HTTP 201 (nunca se rechaza)" "$HTTP_CODE"             "201"
check "code = LEAD_CREATED"         "$(field '.code')"       "LEAD_CREATED"
check "duplicated = true"           "$(field '.duplicated')" "true"
echo

# --------------------------------------------------- 03 - missing required
echo "03 - Faltan campos requeridos"
post '{"email":"missing.required@example.com"}' yes
check "HTTP 422"              "$HTTP_CODE"         "422"
check "code = VALIDATION_ERROR" "$(field '.code')" "VALIDATION_ERROR"
check "status = error"        "$(field '.status')" "error"

for f in first_name last_name phone; do
  check "errors[] reporta ${f}" "$(field "[.errors[]?.field] | index(\"${f}\") | if . then \"si\" else \"no\" end")" "si"
done

check "todos con sub-code REQUIRED" \
  "$(field '[.errors[]?.code] | unique | join(",")')" "REQUIRED"
check "reporta los 3 en una sola pasada" \
  "$(field 'if (.errors | length) >= 3 then "si" else "no" end')" "si"
echo

# ------------------------------------------------------ 04 - unknown branch
echo "04 - branch_code fuera del catalogo"
post '{"first_name":"Maria","last_name":"Gonzalez","phone":"0981123456","branch_code":"VILLARRICA"}' yes
check "HTTP 422"                "$HTTP_CODE"         "422"
check "code = VALIDATION_ERROR" "$(field '.code')"   "VALIDATION_ERROR"
check "errors[] marca branch_code" \
  "$(field '[.errors[]?.field] | index("branch_code") | if . then "si" else "no" end')" "si"
check "sub-code = UNKNOWN_VALUE" \
  "$(field '.errors[]? | select(.field == "branch_code") | .code')" "UNKNOWN_VALUE"
echo

# -------------------------------------------------------- 05 - malformed JSON
echo "05 - JSON malformado"
post '{"first_name":"Maria","last_name":' yes
check "HTTP 400"                  "$HTTP_CODE"           "400"
check "code = MALFORMED_REQUEST"  "$(field '.code')"     "MALFORMED_REQUEST"
check "status = error"            "$(field '.status')"   "error"
check "sin errors[] (no se valido)" "$(field '.errors')" "ABSENT"
echo

# ------------------------------------------------------------ 06 - no token
echo "06 - Sin access token"
post '{"first_name":"Maria","last_name":"Gonzalez","phone":"0981123456"}' no
check "HTTP 401" "$HTTP_CODE" "401"
echo

# ------------------------------------------------------------------ summary
echo "-------------------------------------------"
printf 'Resultado: %s   %s\n' "$(green "${PASS} PASS")" "$(red "${FAIL} FAIL")"
echo "-------------------------------------------"
echo

[ "$FAIL" -eq 0 ] || exit 1
