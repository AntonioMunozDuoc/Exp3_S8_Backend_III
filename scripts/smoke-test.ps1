# Prueba de humo OAuth2 + plataforma (Windows PowerShell).
#   .\scripts\smoke-test.ps1 | Tee-Object smoke-test-resultado.txt
$ErrorActionPreference = "Continue"
$Auth = "http://localhost:9000"; $Atm = "http://localhost:8083"; $Web = "http://localhost:8081"
$Mobile = "http://localhost:8082"; $Core = "http://localhost:8080"
$ok = 0; $fail = 0

function Code($method, $url, $headers = @{}, $body = $null) {
    try {
        $p = @{ Uri = $url; Method = $method; Headers = $headers; UseBasicParsing = $true }
        if ($body) { $p.Body = $body; $p.ContentType = "application/json" }
        return [int](Invoke-WebRequest @p).StatusCode
    } catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode } else { return 0 } }
}
function Check($desc, $expected, $got) {
    if ($expected -eq $got) { Write-Host "  [OK]    $desc (HTTP $got)"; $script:ok++ }
    else { Write-Host "  [FALLO] $desc (esperado $expected, obtenido $got)"; $script:fail++ }
}
function Token($id, $secret, $scope) {
    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${id}:${secret}"))
    $r = Invoke-RestMethod -Method Post -Uri "$Auth/oauth2/token" -Headers @{ Authorization = "Basic $basic" } `
         -Body @{ grant_type = "client_credentials"; scope = $scope }
    return $r.access_token
}
function Bearer($t) { return @{ Authorization = "Bearer $t" } }

Write-Host "== 1. Authorization Server"
$tAtm = Token "atm-app" "atm-secret-dev" "atm.access"
$tWeb = Token "web-app" "web-secret-dev" "web.access"
$tMob = Token "mobile-app" "mobile-secret-dev" "mobile.access"
Write-Host "  [OK]    token ATM: $($tAtm.Substring(0,25))..."
Check "JWKS publico" 200 (Code "GET" "$Auth/oauth2/jwks")

Write-Host "== 2. Proteccion de los BFF"
Check "ATM sin token" 401 (Code "GET" "$Atm/api/atm/saldo/101")
Check "ATM con token ATM" 200 (Code "GET" "$Atm/api/atm/saldo/101" (Bearer $tAtm))
Check "ATM con token WEB" 403 (Code "GET" "$Atm/api/atm/saldo/101" (Bearer $tWeb))
Check "ATM con token adulterado" 401 (Code "GET" "$Atm/api/atm/saldo/101" (Bearer ($tAtm + "x")))
Check "Web con token WEB" 200 (Code "GET" "$Web/api/web/cuentas/101" (Bearer $tWeb))
Check "Web con token MOBILE" 403 (Code "GET" "$Web/api/web/cuentas/101" (Bearer $tMob))
Check "Mobile con token MOBILE" 200 (Code "GET" "$Mobile/api/mobile/cuentas/101" (Bearer $tMob))

Write-Host "== 3. Proteccion del Core"
Check "Core sin token" 401 (Code "GET" "$Core/api/core/cuentas/101")
Check "Core con token de canal" 403 (Code "GET" "$Core/api/core/cuentas/101" (Bearer $tAtm))

Write-Host "== 4. Flujo completo con eventos"
Check "Retiro de 100" 200 (Code "POST" "$Atm/api/atm/retiros" (Bearer $tAtm) '{"cuentaId":101,"monto":100}')
Check "Monto negativo" 400 (Code "POST" "$Atm/api/atm/retiros" (Bearer $tAtm) '{"cuentaId":101,"monto":-5}')
Check "Sin saldo (cuenta 104)" 409 (Code "POST" "$Atm/api/atm/retiros" (Bearer $tAtm) '{"cuentaId":104,"monto":100}')
Check "Cuenta inexistente" 404 (Code "GET" "$Atm/api/atm/saldo/999999" (Bearer $tAtm))
Start-Sleep 2
Write-Host "  Eventos procesados por auditoria:"
docker logs banco-audit-1 2>&1 | Select-String "evento procesado" | Select-Object -Last 2
docker logs banco-audit-2 2>&1 | Select-String "evento procesado" | Select-Object -Last 2

Write-Host ""
Write-Host "RESULTADO: $ok OK, $fail con fallo"
