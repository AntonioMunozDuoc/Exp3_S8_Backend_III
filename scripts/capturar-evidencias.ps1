# Genera las evidencias de ejecucion de la Semana 8 (Windows PowerShell).
# Con la plataforma levantada (docker compose up -d --build):
#     .\scripts\capturar-evidencias.ps1
# Deja un .txt por punto en "evidencias\Evidencias S8\"
$ErrorActionPreference = "Continue"
Set-Location (Join-Path $PSScriptRoot "..")
$Out = "evidencias\Evidencias S8"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Auth = "http://localhost:9000"; $Atm = "http://localhost:8083"; $Core = "http://localhost:8080"

function Save($file, $title, [scriptblock]$block) {
    $header = "### $title`r`n### Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n### Comando: $block`r`n"
    $body = & $block 2>&1 | Out-String
    Set-Content -Path (Join-Path $Out $file) -Value ($header + "`r`n" + $body) -Encoding UTF8
    Write-Host "  -> $Out\$file"
}
function Http($method, $url, $headers = @{}, $body = $null) {
    try {
        $p = @{ Uri = $url; Method = $method; Headers = $headers; UseBasicParsing = $true }
        if ($body) { $p.Body = $body; $p.ContentType = "application/json" }
        $r = Invoke-WebRequest @p
        return "HTTP $([int]$r.StatusCode)  $($r.Content)"
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        return "HTTP $code  $($_.ErrorDetails.Message)"
    }
}
function Token($id, $secret, $scope) {
    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${id}:${secret}"))
    (Invoke-RestMethod -Method Post -Uri "$Auth/oauth2/token" -Headers @{ Authorization = "Basic $basic" } `
        -Body @{ grant_type = "client_credentials"; scope = $scope }).access_token
}

Write-Host "== Evidencias Semana 8 =="
Save "01-imagenes-docker.txt" "Imagenes Docker" { docker images | Select-String "REPOSITORY|bancoxyz" }
Save "02-compose-ps.txt" "Contenedores orquestados" { docker compose ps }
Save "03-eureka.txt" "Eureka" { (Invoke-WebRequest -UseBasicParsing -Headers @{Accept="application/json"} http://localhost:8761/eureka/apps).Content.Substring(0,1500) }
Save "04-config-server.txt" "Config Server" { (Invoke-WebRequest -UseBasicParsing http://localhost:8888/bank-core-api/default).Content }
Save "05-oauth-metadata.txt" "Metadata y JWKS" {
    (Invoke-WebRequest -UseBasicParsing "$Auth/.well-known/oauth-authorization-server").Content
    (Invoke-WebRequest -UseBasicParsing "$Auth/oauth2/jwks").Content }

$tAtm = Token "atm-app" "atm-secret-dev" "atm.access"
Save "06-token-client-credentials.txt" "Token client_credentials" {
    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("atm-app:atm-secret-dev"))
    Invoke-RestMethod -Method Post -Uri "$Auth/oauth2/token" -Headers @{ Authorization = "Basic $basic" } -Body @{ grant_type="client_credentials"; scope="atm.access" } | ConvertTo-Json }
Save "07-jwt-payload.txt" "Payload del JWT" {
    $p = $tAtm.Split(".")[1].Replace("-","+").Replace("_","/"); while ($p.Length % 4) { $p += "=" }
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) }

Write-Host "  (smoke test)"
& "$PSScriptRoot\smoke-test.ps1" *> (Join-Path $Out "08-smoke-test-oauth2.txt")
Start-Sleep 2
Save "09-auditoria-eventos.txt" "Eventos procesados por auditoria" {
    docker logs banco-audit-1 2>&1 | Select-String "evento procesado" | Select-Object -Last 5
    docker logs banco-audit-2 2>&1 | Select-String "evento procesado" | Select-Object -Last 5 }
Save "10-particiones-consumer-group.txt" "Particiones por instancia" {
    docker logs banco-audit-1 2>&1 | Select-String "partitions assigned"
    docker logs banco-audit-2 2>&1 | Select-String "partitions assigned"
    docker exec banco-kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group banco-auditoria }
Save "11-salud-bff-atm.txt" "Salud del BFF ATM" { (Invoke-WebRequest -UseBasicParsing "$Atm/actuator/health").Content }

Save "12-resiliencia-core-caido.txt" "Core caido: Retry + Circuit Breaker" {
    docker compose stop bank-core-api
    1..4 | ForEach-Object { "--- consulta $_"; Http "GET" "$Atm/api/atm/saldo/101" @{ Authorization = "Bearer $tAtm" } }
    "--- Salud BFF"; try { (Invoke-WebRequest -UseBasicParsing "$Atm/actuator/health").Content } catch { $_.ErrorDetails.Message }
    "--- Logs"; docker logs banco-bff-atm 2>&1 | Select-String "Retry \[|Circuit Breaker" | Select-Object -Last 6 }

Save "13-resiliencia-recuperacion.txt" "Recuperacion automatica" {
    docker compose start bank-core-api
    for ($i = 0; $i -lt 40; $i++) { if ((Http "GET" "$Core/actuator/health") -like "HTTP 200*") { break }; Start-Sleep 3 }
    Start-Sleep 10
    1..3 | ForEach-Object { "--- consulta $_"; Http "GET" "$Atm/api/atm/saldo/101" @{ Authorization = "Bearer $tAtm" }; Start-Sleep 2 }
    (Invoke-WebRequest -UseBasicParsing "$Atm/actuator/health").Content }

Save "14-kafka-caido.txt" "Kafka caido: la operacion sigue respondiendo" {
    docker compose stop kafka
    Http "POST" "$Atm/api/atm/retiros" @{ Authorization = "Bearer $tAtm" } '{"cuentaId":101,"monto":10}'
    Start-Sleep 4
    docker logs banco-core-api 2>&1 | Select-String "Kafka no disponible|Error publicando" | Select-Object -Last 3
    docker compose start kafka }

Write-Host "Listo. Adjunta los archivos de '$Out' como evidencia."
