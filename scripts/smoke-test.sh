#!/usr/bin/env bash
# Prueba de humo OAuth2 + plataforma. Uso:  ./scripts/smoke-test.sh | tee evidencia-smoke-test.txt
# Requiere: docker compose up -d --build (esperar a que todo este "healthy").
set -u

AUTH=http://localhost:9000
ATM=http://localhost:8083
WEB=http://localhost:8081
MOBILE=http://localhost:8082
CORE=http://localhost:8080

ok=0; fail=0
check() { # descripcion esperado obtenido
  if [ "$2" = "$3" ]; then echo "  [OK]   $1 (HTTP $3)"; ok=$((ok+1));
  else echo "  [FALLO] $1 (esperado $2, obtenido $3)"; fail=$((fail+1)); fi
}
code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }
token() { # client_id secret scope
  curl -s -u "$1:$2" -d grant_type=client_credentials -d "scope=$3" "$AUTH/oauth2/token" \
    | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

echo "== 1. Authorization Server: emision de tokens (client_credentials)"
T_ATM=$(token atm-app atm-secret-dev atm.access)
T_WEB=$(token web-app web-secret-dev web.access)
T_MOB=$(token mobile-app mobile-secret-dev mobile.access)
[ -n "$T_ATM" ] && echo "  [OK]   token ATM obtenido: ${T_ATM:0:25}..." || { echo "  [FALLO] sin token ATM"; fail=$((fail+1)); }
check "secreto incorrecto es rechazado" 401 "$(code -u atm-app:mala -d grant_type=client_credentials -d scope=atm.access $AUTH/oauth2/token)"
check "scope no registrado es rechazado" 400 "$(code -u atm-app:atm-secret-dev -d grant_type=client_credentials -d scope=core.access $AUTH/oauth2/token)"
check "JWKS publico disponible" 200 "$(code $AUTH/oauth2/jwks)"

echo "== 2. Proteccion de los BFF (Resource Servers)"
check "ATM sin token" 401 "$(code $ATM/api/atm/saldo/101)"
check "ATM con token ATM" 200 "$(code -H "Authorization: Bearer $T_ATM" $ATM/api/atm/saldo/101)"
check "ATM con token WEB (scope equivocado)" 403 "$(code -H "Authorization: Bearer $T_WEB" $ATM/api/atm/saldo/101)"
check "ATM con token adulterado" 401 "$(code -H "Authorization: Bearer ${T_ATM}x" $ATM/api/atm/saldo/101)"
check "Web con token WEB" 200 "$(code -H "Authorization: Bearer $T_WEB" $WEB/api/web/cuentas/101)"
check "Web con token MOBILE" 403 "$(code -H "Authorization: Bearer $T_MOB" $WEB/api/web/cuentas/101)"
check "Mobile con token MOBILE" 200 "$(code -H "Authorization: Bearer $T_MOB" $MOBILE/api/mobile/cuentas/101)"

echo "== 3. Proteccion del Core API (solo scope core.access)"
check "Core sin token" 401 "$(code $CORE/api/core/cuentas/101)"
check "Core con token de canal (sin core.access)" 403 "$(code -H "Authorization: Bearer $T_ATM" $CORE/api/core/cuentas/101)"

echo "== 4. Flujo completo con eventos (retiro -> Core -> Kafka -> auditoria)"
check "Retiro de 100 desde el ATM" 200 "$(code -H "Authorization: Bearer $T_ATM" -H 'Content-Type: application/json' -d '{"cuentaId":101,"monto":100}' $ATM/api/atm/retiros)"
check "Retiro con monto negativo (validacion)" 400 "$(code -H "Authorization: Bearer $T_ATM" -H 'Content-Type: application/json' -d '{"cuentaId":101,"monto":-5}' $ATM/api/atm/retiros)"
check "Retiro sin saldo (cuenta 104)" 409 "$(code -H "Authorization: Bearer $T_ATM" -H 'Content-Type: application/json' -d '{"cuentaId":104,"monto":100}' $ATM/api/atm/retiros)"
check "Cuenta inexistente" 404 "$(code -H "Authorization: Bearer $T_ATM" $ATM/api/atm/saldo/999999)"
sleep 2
echo "  Ultimos eventos procesados por auditoria:"
docker logs banco-audit-1 2>&1 | grep -E "evento procesado" | tail -2 | sed 's/^/    /'
docker logs banco-audit-2 2>&1 | grep -E "evento procesado" | tail -2 | sed 's/^/    /'

echo
echo "RESULTADO: $ok OK, $fail con fallo"
[ "$fail" -eq 0 ]
