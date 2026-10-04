#!/usr/bin/env bash
# =============================================================================
# Genera las EVIDENCIAS DE EJECUCION (salidas de consola) de la Semana 8.
# Ejecutar con toda la plataforma levantada:   docker compose up -d --build
#
#     ./scripts/capturar-evidencias.sh
#
# Deja un archivo .txt por cada punto en  evidencias/Evidencias S8/
# (cada archivo incluye fecha, comando ejecutado y salida real).
# =============================================================================
set -u
cd "$(dirname "$0")/.."
OUT="evidencias/Evidencias S8"
mkdir -p "$OUT"

AUTH=http://localhost:9000; ATM=http://localhost:8083; CORE=http://localhost:8080

run() { # archivo "titulo" comando...
  local f="$OUT/$1"; local t="$2"; shift 2
  { echo "### $t"; echo "### Fecha: $(date '+%Y-%m-%d %H:%M:%S')"; echo "### Comando: $*"; echo; eval "$*" 2>&1; } > "$f"
  echo "  -> $f"
}
token() { curl -s -u "$1:$2" -d grant_type=client_credentials -d "scope=$3" "$AUTH/oauth2/token" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'; }

echo "== Evidencias Semana 8 =="

run 01-imagenes-docker.txt "Imagenes Docker de los microservicios" "docker images | grep -E 'REPOSITORY|bancoxyz'"
run 02-compose-ps.txt "Contenedores orquestados por docker-compose" "docker compose ps"
run 03-eureka.txt "Servicios registrados en Eureka" "curl -s -H 'Accept: application/json' http://localhost:8761/eureka/apps | head -c 1500"
run 04-config-server.txt "Config Server sirviendo bank-core-api" "curl -s http://localhost:8888/bank-core-api/default | head -c 2500"
run 05-oauth-metadata.txt "Metadata y JWKS del Authorization Server" "curl -s $AUTH/.well-known/oauth-authorization-server; echo; echo; curl -s $AUTH/oauth2/jwks"

T_ATM=$(token atm-app atm-secret-dev atm.access)
run 06-token-client-credentials.txt "Emision de access token (client_credentials)" \
  "curl -s -u atm-app:atm-secret-dev -d grant_type=client_credentials -d scope=atm.access $AUTH/oauth2/token"

{ echo "### Contenido (payload) del JWT del ATM"; echo "### Fecha: $(date '+%Y-%m-%d %H:%M:%S')"; echo
  python3 - "$T_ATM" <<'PY' 2>&1 || echo "(python3 no disponible: decodifica el token en https://jwt.io)"
import sys,base64,json
p=sys.argv[1].split('.')[1]; p+='='*(-len(p)%4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(p)),indent=2))
PY
} > "$OUT/07-jwt-payload.txt"; echo "  -> $OUT/07-jwt-payload.txt"

./scripts/smoke-test.sh > "$OUT/08-smoke-test-oauth2.txt" 2>&1; echo "  -> $OUT/08-smoke-test-oauth2.txt"

sleep 2
run 09-auditoria-eventos.txt "Eventos procesados por audit-service (Kafka)" \
  "docker logs banco-audit-1 2>&1 | grep -E 'evento procesado' | tail -5; docker logs banco-audit-2 2>&1 | grep -E 'evento procesado' | tail -5"
run 10-particiones-consumer-group.txt "Particiones asignadas a cada instancia del grupo banco-auditoria" \
  "docker logs banco-audit-1 2>&1 | grep -i 'partitions assigned'; docker logs banco-audit-2 2>&1 | grep -i 'partitions assigned'; docker exec banco-kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group banco-auditoria"
run 11-retry-bulkhead-config.txt "Salud del BFF ATM (Circuit Breaker coreApi)" "curl -s $ATM/actuator/health"

# ---------------- Resiliencia: Core caido ----------------
{
  echo "### Resiliencia: Core API caido (Retry + Circuit Breaker)"; echo "### Fecha: $(date '+%Y-%m-%d %H:%M:%S')"; echo
  echo "--- docker compose stop bank-core-api"; docker compose stop bank-core-api 2>&1 | tail -1
  for i in 1 2 3 4; do
    echo "--- consulta $i al BFF ATM:"; curl -s -w "\nHTTP %{http_code}\n" -H "Authorization: Bearer $T_ATM" $ATM/api/atm/saldo/101
  done
  echo "--- Estado del Circuit Breaker coreApi:"; curl -s $ATM/actuator/health | grep -o '"coreApi":{[^}]*}[^}]*}'
  echo "--- Logs del BFF (Retry y Circuit Breaker):"
  docker logs banco-bff-atm 2>&1 | grep -E "Retry \[|Circuit Breaker" | tail -6 | cut -c1-220
} > "$OUT/12-resiliencia-core-caido.txt" 2>&1; echo "  -> $OUT/12-resiliencia-core-caido.txt"

{
  echo "### Recuperacion automatica del Core (OPEN -> HALF_OPEN -> CLOSED)"; echo "### Fecha: $(date '+%Y-%m-%d %H:%M:%S')"; echo
  docker compose start bank-core-api 2>&1 | tail -1
  echo "Esperando a que el Core vuelva a estar healthy..."
  for i in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' $CORE/actuator/health)" = "200" ] && break; sleep 3
  done
  sleep 10
  for i in 1 2 3; do
    echo "--- consulta $i:"; curl -s -w "\nHTTP %{http_code}\n" -H "Authorization: Bearer $T_ATM" $ATM/api/atm/saldo/101; sleep 2
  done
  echo "--- Estado del Circuit Breaker:"; curl -s $ATM/actuator/health | grep -o '"coreApi":{[^}]*}[^}]*}'
} > "$OUT/13-resiliencia-recuperacion.txt" 2>&1; echo "  -> $OUT/13-resiliencia-recuperacion.txt"

# ---------------- Resiliencia: Kafka caido ----------------
{
  echo "### Kafka caido: la operacion bancaria sigue respondiendo"; echo "### Fecha: $(date '+%Y-%m-%d %H:%M:%S')"; echo
  docker compose stop kafka 2>&1 | tail -1
  echo "--- Retiro de 10 con Kafka caido:"
  curl -s -w "\nHTTP %{http_code}\n" -H "Authorization: Bearer $T_ATM" -H 'Content-Type: application/json' -d '{"cuentaId":101,"monto":10}' $ATM/api/atm/retiros
  sleep 4
  echo "--- Log del Core:"; docker logs banco-core-api 2>&1 | grep -E "Kafka no disponible|Error publicando" | tail -3 | cut -c1-220
  docker compose start kafka 2>&1 | tail -1
} > "$OUT/14-kafka-caido.txt" 2>&1; echo "  -> $OUT/14-kafka-caido.txt"

echo
echo "Listo. Revisa la carpeta '$OUT' y adjunta esos archivos como evidencia."
