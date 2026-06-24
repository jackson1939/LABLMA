<#
.SYNOPSIS
  Inicia todos los servicios SGC como procesos independientes (no jobs).
  Cierra VS Code / terminal sin problema, los servicios siguen corriendo.
  Logs en backend/logs/ y frontend/logs/
#>

param(
    [switch]$NoBuild,
    [switch]$NoSeed,
    [switch]$NoTunnel
)

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$beDir = "$root\backend"
$feDir = "$root\frontend"
$logDir = "$root\logs"
$venv = "$beDir\venv\Scripts\python.exe"
$domain = "lablma.com"

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Write-Log($msg) {
    $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$t] $msg"
    "[$t] $msg" | Out-File -FilePath "$logDir\server.log" -Append -Encoding UTF8
}

# ─── Matar procesos previos ───
Write-Log "Limpiando procesos anteriores..."
Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "uvicorn" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "next" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | Stop-Process -Force

# ─── Backend ───
Write-Log "Iniciando backend (puerto 8000)..."
$beLog = "$logDir\backend.log"
$beErr = "$logDir\backend-err.log"
Start-Process -PassThru -FilePath $venv -ArgumentList "-m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload" -WorkingDirectory $beDir -RedirectStandardOutput $beLog -RedirectStandardError $beErr -WindowStyle Hidden
Start-Sleep -Seconds 3
Write-Log "Backend iniciado"

# ─── Frontend ───
Write-Log "Iniciando frontend (puerto 3000)..."
$feLog = "$logDir\frontend.log"
$feErr = "$logDir\frontend-err.log"
Start-Process -PassThru -FilePath "$feDir\node_modules\.bin\next.cmd" -ArgumentList "dev -H 0.0.0.0 -p 3000" -WorkingDirectory $feDir -RedirectStandardOutput $feLog -RedirectStandardError $feErr -WindowStyle Hidden
Start-Sleep -Seconds 3
Write-Log "Frontend iniciado"

# ─── Cloudflare Tunnel ───
$cfPath = "$env:USERPROFILE\cloudflared.exe"
$tunnelExists = $false
if (Test-Path $cfPath) {
    try { $list = & $cfPath tunnel list 2>&1; if ($list -match "sgc") { $tunnelExists = $true } } catch {}
}
if ($tunnelExists -and -not $NoTunnel -and (Test-Path "$env:USERPROFILE\.cloudflared\cert.pem")) {
    Write-Log "Iniciando Cloudflare Tunnel (${domain})..."
    $cfLog = "$logDir\tunnel.log"
    Start-Process -PassThru -FilePath $cfPath -ArgumentList "tunnel run sgc" -RedirectStandardOutput $cfLog -RedirectStandardError "${cfLog}.err" -WindowStyle Hidden
    Start-Sleep -Seconds 2
    Write-Log "Tunnel iniciado: https://${domain}"
} elseif ($tunnelExists) {
    Write-Log "Tunnel configurado pero sin login. Salta 'npm run infra:tunnel:login' para activar"
}

# ─── LocalTunnel (invisible, sin ventanas) ───
if (-not ($tunnelExists -and (Test-Path "$env:USERPROFILE\.cloudflared\cert.pem"))) {
    Write-Log "Cloudflare Tunnel no disponible. Iniciando LocalTunnel (invisible)..."
    $ltUrlFile = "$logDir\tunnel-url.txt"
    $ltOutFile = "$logDir\localtunnel-raw.log"
    $ltScript = @"
`$npx = "C:\Program Files\nodejs\npx.cmd"
`$outFile = "$ltOutFile"
`$urlFile = "$ltUrlFile"
`$logDir = "$logDir"
while (`$true) {
    `$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "`$ts - Iniciando LocalTunnel..." | Out-File `$outFile -Append -Encoding UTF8
    try {
        `$output = & `$npx localtunnel --port 3000 2>&1
        `$output | Out-File `$outFile -Append -Encoding UTF8
        `$url = (`$output | Select-String "your url is:" -ErrorAction SilentlyContinue).ToString()
        if (`$url) {
            `$url = `$url -replace "your url is: ", ""
            `$url = `$url.Trim()
            "`$ts - TUNNEL URL: `$url" | Out-File `$urlFile -Encoding UTF8
            "`$ts - TUNNEL URL: `$url" | Out-File `$outFile -Append -Encoding UTF8
        }
    } catch {
        "`$ts - ERROR: `$_" | Out-File `$outFile -Append -Encoding UTF8
    }
    Start-Sleep -Seconds 15
}
"@
    $ltScriptFile = "$logDir\localtunnel-run.ps1"
    $ltScript | Set-Content -Path $ltScriptFile -Encoding UTF8
    Start-Process -PassThru -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ltScriptFile`"" -WindowStyle Hidden
    Start-Sleep -Seconds 5
    if (Test-Path $ltUrlFile) {
        $savedUrl = Get-Content $ltUrlFile -Raw -ErrorAction SilentlyContinue
        if ($savedUrl) { Write-Log "TUNNEL PUBLICO: $savedUrl" }
    }
    Write-Log "LocalTunnel: ejecutandose en segundo plano (sin ventanas)"
}

# ─── Auto-sync GitHub bidireccional ───
Write-Log "Iniciando auto-sync GitHub..."
$autoSyncScript = "$root\scripts\auto-sync.ps1"
if (Test-Path $autoSyncScript) {
    $syncLog = "$logDir\auto-sync.log"
    Start-Process -PassThru -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$autoSyncScript`" -Interval 60" -WindowStyle Hidden
    Start-Sleep -Seconds 2
    Write-Log "Auto-sync GitHub iniciado"
} else {
    Write-Log "auto-sync.ps1 no encontrado, se omite"
}

# ─── Auto-deploy monitor ───
Write-Log "Iniciando auto-deploy monitor..."
$monitorLog = "$logDir\monitor.log"
$monitorScript = @"
`$root = "$root"
`$beDir = "$beDir"
`$feDir = "$feDir"
`$venv = "$venv"
`$logDir = "$logDir"
`$interval = 60
`$lastCheck = 0

while (`$true) {
    Start-Sleep -Seconds 10
    `$now = [int](Get-Date -UFormat %s)
    if (`$now -lt (`$lastCheck + `$interval)) { continue }
    `$lastCheck = `$now
    try {
        & git -C `$root fetch origin 2>&1 | Out-Null
        `$local = & git -C `$root rev-parse HEAD 2>`$null
        `$remote = & git -C `$root rev-parse origin/main 2>`$null
        if (`$local -and `$remote -and `$local -ne `$remote) {
            "[`$(Get-Date -Format 'HH:mm:ss')] Nuevos cambios remotos. Actualizando..." | Out-File -FilePath "$logDir\server.log" -Append
            & git -C `$root pull origin main 2>&1 | Out-Null
            & git -C `$root diff HEAD@{1} HEAD --name-only 2>`$null | Select-String "requirements.txt" | Out-Null
            if (`$?) { & `$venv -m pip install -r "$beDir\requirements.txt" -q 2>&1 | Out-Null }
            & `$venv -m alembic upgrade head 2>&1 | Out-Null
            Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object { `$_.CommandLine -match "uvicorn" } | ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 2
            Start-Process -PassThru -FilePath `$venv -ArgumentList "-m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload" -WorkingDirectory `$beDir -RedirectStandardOutput "$logDir\backend.log" -RedirectStandardError "$logDir\backend-err.log" -WindowStyle Hidden
            "[`$(Get-Date -Format 'HH:mm:ss')] Servidor actualizado." | Out-File -FilePath "$logDir\server.log" -Append
        }
    } catch {}
}
"@
$monitorFile = "$logDir\monitor-run.ps1"
$monitorScript | Set-Content -Path $monitorFile -Encoding UTF8
Start-Process -PassThru -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$monitorFile`"" -WindowStyle Hidden

# ─── Mostrar URLs ───
Write-Log ""
Write-Log "========== SGC EN LINEA =========="
Write-Log "  LOCAL:    http://localhost:3000"
Write-Log "  LOCAL:    http://localhost:8000/docs"
$lanIPs = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' } | Select-Object -ExpandProperty IPAddress
foreach ($ip in $lanIPs) {
    Write-Log "  LAN:      http://${ip}:3000"
}
if ($tunnelExists -and (Test-Path "$env:USERPROFILE\.cloudflared\cert.pem")) {
    Write-Log "  INTERNET: https://${domain}"
} else {
    $ltUrlFile = "$logDir\tunnel-url.txt"
    if (Test-Path $ltUrlFile) {
        $savedUrl = Get-Content $ltUrlFile -Raw -ErrorAction SilentlyContinue
        if ($savedUrl) { Write-Log "  INTERNET: $savedUrl" }
    }
}
Write-Log "=================================="
Write-Log "Logs en: $logDir"
Write-Log "Para detener: .\scripts\stop-all.ps1"
