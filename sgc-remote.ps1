<#
.SYNOPSIS
  SGC - Acceso Remoto por Carpeta Compartida + RDP Controlado
  Configura SMB share, WinRM, RDP toggle, y GitHub auto-sync.

.DESCRIPTION
  - Carpeta compartida (SMB) para edicion hot-reload desde tu laptop
  - RDP controlado: se activa SOLO con rdp-toggle.ps1
  - WinRM (PowerShell Remoto) para comandos sin interfaz
  - Auto-sync bidireccional con GitHub
  - Se ejecuta UNA SOLA VEZ en el SERVIDOR como ADMINISTRADOR

.PARAMETER ProjectPath
  Ruta del proyecto SGC (default: auto-detect)

.PARAMETER ShareName
  Nombre del recurso compartido SMB (default: sgc)

.PARAMETER Username
  Nombre del usuario dedicado (default: sgc)

.PARAMETER Password
  Clave del usuario dedicado (default: SgcAdmin2024!)

.PARAMETER SshKeyPath
  Ruta a la clave SSH para GitHub (default: auto-generate)

.EXAMPLE
  .\sgc-remote.ps1
  .\sgc-remote.ps1 -ProjectPath D:\LABUGRAM\sgc -Password MiClaveSegura2025!
#>

param(
    [string]$ProjectPath = "",
    [string]$ShareName = "sgc",
    [string]$Username = "sgc",
    [string]$Password = "SgcAdmin2024!",
    [string]$SshKeyPath = "$env:USERPROFILE\.ssh\id_ed25519"
)

$ErrorActionPreference = "Stop"

# ── Verificar ADMIN ──
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Ejecuta como ADMINISTRADOR" -ForegroundColor Red
    exit 1
}

function Write-Banner { param([string]$T, [string]$D)
    Write-Host "`n" ("─" * 60) -ForegroundColor DarkGray
    Write-Host " $T" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host " $D" -ForegroundColor Gray
    Write-Host ("─" * 60) -ForegroundColor DarkGray
}

function Write-OK { Write-Host "  [OK]" -NoNewline -ForegroundColor Green; Write-Host " $args" }
function Write-Warn { Write-Host "  [!]" -NoNewline -ForegroundColor Yellow; Write-Host " $args" }

# ── Auto-detect project ──
if (-not $ProjectPath) {
    $candidates = @(
        "D:\LABUGRAM\sgc",
        "C:\LABUGRAM\sgc",
        "C:\Proyectos\sgc",
        "C:\sgc",
        "$env:USERPROFILE\sgc"
    )
    foreach ($p in $candidates) {
        $resolved = Resolve-Path $p -ErrorAction SilentlyContinue
        if ($resolved -and (Test-Path "$resolved\backend\app\main.py")) {
            $ProjectPath = $resolved.Path; break
        }
    }
    if (-not $ProjectPath) {
        Write-Host "Ruta del proyecto: " -ForegroundColor Cyan -NoNewline
        $ProjectPath = Read-Host
        if (-not (Test-Path "$ProjectPath\backend\app\main.py")) {
            Write-Host "ERROR: No es un proyecto SGC valido" -ForegroundColor Red; exit 1
        }
    }
}

Write-Host @"

  ╔══════════════════════════════════════════════════════╗
  ║     SGC - CONFIGURACION DE ACCESO REMOTO            ║
  ╚══════════════════════════════════════════════════════╝
  Proyecto: $ProjectPath
  Host:     $env:COMPUTERNAME
  IP LAN:   $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' } | Select-Object -First 1 -ExpandProperty IPAddress))
"@ -ForegroundColor Cyan

# ════════════════════════════════════════════
# 1. USUARIO DEDICADO
# ════════════════════════════════════════════
Write-Banner "PASO 1/6" "Crear usuario '$Username' para acceso remoto"

$existing = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
if (-not $existing) {
    $secure = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $Username -Password $secure -FullName "SGC Remote" -Description "Acceso remoto SGC - carpeta compartida y RDP" | Out-Null
    Add-LocalGroupMember -Group "Administradores" -Member $Username -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group "Usuarios" -Member $Username -ErrorAction SilentlyContinue
    Write-OK "Usuario '$Username' creado y agregado a Administradores"
} else {
    Write-OK "Usuario '$Username' ya existe"
    # Asegurar que sea admin
    try { Add-LocalGroupMember -Group "Administradores" -Member $Username -ErrorAction Stop } catch {}
}
Write-Host "    Usuario: $Username" -ForegroundColor Yellow
Write-Host "    Clave:   $Password" -ForegroundColor Yellow
Write-Host "    (Cambiala con: net user $Username *)" -ForegroundColor DarkGray

# ════════════════════════════════════════════
# 2. COMPARTIR CARPETA SMB
# ════════════════════════════════════════════
Write-Banner "PASO 2/6" "Compartir carpeta del proyecto por SMB"

# Activar guest auth para redes domesticas
try {
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "AllowInsecureGuestAuth" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
} catch {}

# Habilitar NetBIOS sobre TCP/IP en la interfaz de red
try {
    $adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" }
    foreach ($adapter in $adapters) {
        $interfaceIndex = $adapter.ifIndex
        $netConfig = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "Index = $interfaceIndex" -ErrorAction SilentlyContinue
        if ($netConfig -and $netConfig.TcpipNetbiosOptions -ne 0) {
            $netConfig.SetTcpipNetbiosOptions(0) | Out-Null
        }
    }
} catch {}

$existingShare = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
if ($existingShare) {
    Remove-SmbShare -Name $ShareName -Force -Confirm:$false
    Start-Sleep -Seconds 1
}

New-SmbShare -Name $ShareName -Path $ProjectPath -FullAccess "$env:COMPUTERNAME\$Username" -ChangeAccess "$env:COMPUTERNAME\$Username" -Description "SGC - Edicion de codigo remota" | Out-Null

# Firewall para SMB
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue
try {
    New-NetFirewallRule -DisplayName "SGC-SMB-TCP-445" -Direction Inbound -Protocol TCP -LocalPort 445 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "SGC-SMB-UDP-137-138" -Direction Inbound -Protocol UDP -LocalPort 137-138 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "SGC-SMB-UDP-445" -Direction Inbound -Protocol UDP -LocalPort 445 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
} catch {}

Write-OK "Carpeta compartida como \\$env:COMPUTERNAME\$ShareName"
Write-Host "    Ruta de red: \\$env:COMPUTERNAME\$ShareName" -ForegroundColor Cyan
$lanIP = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' } | Select-Object -First 1 -ExpandProperty IPAddress
if ($lanIP) { Write-Host "    Tambien:     \\$lanIP\$ShareName" -ForegroundColor Cyan }

# ════════════════════════════════════════════
# 3. WINRM (POWERSHELL REMOTO)
# ════════════════════════════════════════════
Write-Banner "PASO 3/6" "PowerShell Remoto (WinRM) para comandos sin interfaz"

try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop
    Write-OK "PSRemoting habilitado"
} catch {
    Write-Warn "PSRemoting ya estaba configurado o fallo: $_"
}

try {
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.*" -Force -ErrorAction Stop
} catch {}
try {
    Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true -Force -ErrorAction Stop
} catch {}

# Firewall WinRM
try {
    New-NetFirewallRule -DisplayName "SGC-WinRM-HTTP" -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "SGC-WinRM-HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
} catch {}

Write-OK "PowerShell Remoto activado (puerto 5985/5986)"

# ════════════════════════════════════════════
# 4. RDP CONTROLADO (SCRIPT TOGGLE)
# ════════════════════════════════════════════
Write-Banner "PASO 4/6" "RDP controlado - se activa SOLO con toggle"

# Crear script toggle RDP
$rdpTogglePath = Join-Path $ProjectPath "rdp-toggle.ps1"
@"
<#
.SYNOPSIS
  Activa o desactiva RDP en el servidor SGC.
  Ejecutar desde la carpeta compartida (X:\) como ADMINISTRADOR.

.PARAMETER On
  Activa RDP y reglas de firewall

.PARAMETER Off
  Desactiva RDP (estado seguro por defecto)
#>
param(
    [switch]`$On,
    [switch]`$Off
)

`$ErrorActionPreference = "Stop"

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "Ejecuta como ADMINISTRADOR" -ForegroundColor Red
    exit 1
}

`$serverIP = "$((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { `$_.IPAddress -like '192.168.*' } | Select-Object -First 1 -ExpandProperty IPAddress))"

if (`$On) {
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    try {
        New-NetFirewallRule -DisplayName "SGC-RDP-TCP" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "SGC-RDP-UDP" -Direction Inbound -Protocol UDP -LocalPort 3389 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
    } catch {}
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║        RDP ACTIVADO - Conexion disponible        ║" -ForegroundColor Green
    Write-Host "╠═══════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "║  Win+R > mstsc > `$serverIP                       ║" -ForegroundColor Green
    Write-Host "║  Usuario: $Username / Clave: $Password           ║" -ForegroundColor Green
    Write-Host "║                                                   ║" -ForegroundColor Green
    Write-Host "║  Para salir:  .\rdp-toggle.ps1 -Off               ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Green
}
elseif (`$Off) {
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 1
    Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Write-Host "RDP DESACTIVADO - Servidor seguro" -ForegroundColor Green
}
else {
    Write-Host "Uso:" -ForegroundColor Cyan
    Write-Host "  .\rdp-toggle.ps1 -On    (activar RDP)" -ForegroundColor Cyan
    Write-Host "  .\rdp-toggle.ps1 -Off   (desactivar RDP)" -ForegroundColor Cyan
}
"@ | Set-Content -Path $rdpTogglePath -Encoding UTF8 -Force

# Desactivar RDP por defecto (seguro)
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 1
try {
    Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
} catch {}

Write-OK "RDP DESACTIVADO por defecto (seguro)"
Write-OK "Script toggle: $rdpTogglePath"

# ════════════════════════════════════════════
# 5. GITHUB AUTO-SYNC
# ════════════════════════════════════════════
Write-Banner "PASO 5/6" "GitHub - configurar clave SSH y auto-sync"

Push-Location $ProjectPath

# Verificar remotes
$remoteOrigin = git remote get-url origin 2>$null
if (-not $remoteOrigin) {
    Write-Warn "No hay remote 'origin' configurado"
    Write-Host "    Configuralo con:" -ForegroundColor Yellow
    Write-Host "    git remote add origin https://github.com/MIJAELMERIDA1939/LABLMA.git" -ForegroundColor Cyan
    $remoteOrigin = "https://github.com/MIJAELMERIDA1939/LABLMA.git"
}

Write-OK "Remote origin: $remoteOrigin"

# Configurar git user si no existe
$email = git config --global user.email
$name = git config --global user.name
if (-not $email) { git config --global user.email "jackson@sgc.local" 2>$null; Write-OK "Git email configurado" }
if (-not $name) { git config --global user.name "Jackson" 2>$null; Write-OK "Git name configurado" }

# Generar SSH key si no existe
if (-not (Test-Path $SshKeyPath)) {
    Write-Host "  Generando clave SSH para GitHub..." -ForegroundColor Yellow
    $sshDir = Split-Path $SshKeyPath -Parent
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    ssh-keygen -t ed25519 -f $SshKeyPath -N '""' -C "jackson@sgc.local" 2>$null
    if (Test-Path $SshKeyPath) {
        Write-OK "Clave SSH generada: ${SshKeyPath}.pub"
        Write-Host "    AGREGALA A GITHUB:" -ForegroundColor Yellow
        Write-Host "    https://github.com/settings/ssh/new" -ForegroundColor Cyan
        $pubKey = Get-Content "${SshKeyPath}.pub" -Raw
        Write-Host "    Clave:" -ForegroundColor Yellow
        Write-Host "    $pubKey" -ForegroundColor Gray
    }
}

# Crear script de auto-sync
$syncScriptPath = "$ProjectPath\scripts\auto-sync.ps1"
@"
<#
.SYNOPSIS
  SGC - Sincronizacion automatica con GitHub.
  Se ejecuta como proceso en segundo plano cada N segundos.
  Hace git pull + git push automaticamente.

.PARAMETER Interval
  Intervalo en segundos entre cada chequeo (default: 60)

.PARAMETER Branch
  Rama a sincronizar (default: main)
#>
param(
    [int]`$Interval = 60,
    [string]`$Branch = "main"
)

`$ProjectRoot = "$ProjectPath"
`$LogDir = "`$ProjectRoot\logs"
`$SyncLog = "`$LogDir\auto-sync.log"

New-Item -ItemType Directory -Path "`$LogDir" -Force | Out-Null

function Write-Sync(`$msg) {
    `$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[`$ts] `$msg" | Out-File -FilePath "`$SyncLog" -Append -Encoding UTF8
    Write-Host "[`$ts] `$msg"
}

Write-Sync "Auto-sync iniciado (intervalo: `$Interval s, rama: `$Branch)"

while (`$true) {
    Start-Sleep -Seconds `$Interval
    try {
        # 1. Fetch remoto
        & git -C "`$ProjectRoot" fetch origin "`$Branch" 2>&1 | Out-Null

        # 2. Check diferencias
        `$local = & git -C "`$ProjectRoot" rev-parse "`$Branch" 2>`$null
        `$remote = & git -C "`$ProjectRoot" rev-parse "origin/`$Branch" 2>`$null

        if (`$local -and `$remote -and `$local -ne `$remote) {
            Write-Sync "Cambios detectados. Sincronizando..."
            & git -C "`$ProjectRoot" pull origin "`$Branch" 2>&1 | Out-Null
            Write-Sync "Pull completado"
        }

        # 3. Push cambios locales
        `$status = & git -C "`$ProjectRoot" status --porcelain 2>&1
        if (`$status) {
            `$msg = "auto-sync: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            & git -C "`$ProjectRoot" add -A 2>&1 | Out-Null
            & git -C "`$ProjectRoot" commit -m "`$msg" 2>&1 | Out-Null
            & git -C "`$ProjectRoot" push origin "`$Branch" 2>&1 | Out-Null
            Write-Sync "Push completado: `$msg"
        }
    } catch {
        Write-Sync "ERROR en sync: $_"
    }
}
"@ | Set-Content -Path $syncScriptPath -Encoding UTF8 -Force

Write-OK "Auto-sync script: $syncScriptPath"
Write-Host "    Se inicia automaticamente con start-all.ps1" -ForegroundColor Cyan

Pop-Location

# ════════════════════════════════════════════
# 6. SCRIPT DE CONEXION PARA LAPTOP
# ════════════════════════════════════════════
Write-Banner "PASO 6/6" "Generar script de conexion para tu laptop"

$connectScriptPath = Join-Path $ProjectPath "connect-laptop.ps1"
@"
<#
.SYNOPSIS
  Conecta tu laptop al servidor SGC via carpeta compartida.
  Ejecutar en tu laptop (NO en el servidor).

.DESCRIPTION
  - Monta X:\ como la carpeta compartida del servidor
  - Abre el proyecto en el explorador
  - Muestra las URLs del servidor
#>

`$serverIP = "$((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { `$_.IPAddress -like '192.168.*' } | Select-Object -First 1 -ExpandProperty IPAddress))"
`$shareName = "$ShareName"
`$username = "$Username"
`$password = "$Password"
`$driveLetter = "X:"

Write-Host "Conectando a \\`$serverIP\`$shareName ..." -ForegroundColor Cyan

# Desmontar si ya existe
try { net use `$driveLetter /delete /y 2>`$null } catch {}

# Montar carpeta compartida
net use `$driveLetter \\`$serverIP\`$shareName /user:`$username `$password 2>&1

if (`$LASTEXITCODE -eq 0) {
    Write-Host "[OK] Unidad `$driveLetter montada como \\`$serverIP\`$shareName" -ForegroundColor Green
    Invoke-Item "`$driveLetter\"
    Write-Host ""
    Write-Host "Accesos:" -ForegroundColor Cyan
    Write-Host "  Frontend: http://`$serverIP`:3000" -ForegroundColor Green
    Write-Host "  Backend:  http://`$serverIP`:8000/docs" -ForegroundColor Green
    Write-Host "  API Docs: http://`$serverIP`:8000/docs" -ForegroundColor Green
    Write-Host ""
    Write-Host "Comandos utiles (en X:\):" -ForegroundColor Yellow
    Write-Host "  .\rdp-toggle.ps1 -On   (activar RDP)" -ForegroundColor Gray
    Write-Host "  npm run dev             (ver logs en servidor)" -ForegroundColor Gray
    Write-Host "  npm run status          (ver estado)" -ForegroundColor Gray
} else {
    Write-Host "[ERROR] No se pudo conectar. Verifica:" -ForegroundColor Red
    Write-Host "  1. El servidor esta encendido?" -ForegroundColor Yellow
    Write-Host "  2. Estas en la misma red LAN?" -ForegroundColor Yellow
    Write-Host "  3. firewall? Puerto 445 abierto?" -ForegroundColor Yellow
    Write-Host "  Conecta manualmente: net use X: \\`$serverIP\`$shareName /user:`$username" -ForegroundColor Yellow
}
"@ | Set-Content -Path $connectScriptPath -Encoding UTF8 -Force

Write-OK "Script de conexion: $connectScriptPath"
Write-Host "    Llevate este script a tu laptop y ejecutalo ahi" -ForegroundColor Cyan

# ════════════════════════════════════════════
# RESUMEN
# ════════════════════════════════════════════
Write-Host @"

╔══════════════════════════════════════════════════════════════════╗
║              CONFIGURACION COMPLETA - RESUMEN                    ║
╚══════════════════════════════════════════════════════════════════╝

┌────────────────────────────────────────────────────────────────┐
│  TRABAJO DIARIO - CARPETA COMPARTIDA (SMB)                     │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  En tu LAPTOP (una sola vez):                                  │
│    .\connect-laptop.ps1                                        │
│    (o manual: net use X: \\$env:COMPUTERNAME\sgc /user:$Username $Password) │
│                                                                │
│  Abris X:\, editas, guardas. Hot-reload se refleja al instante.│
│                                                                │
│  Para sincronizar cambios a GitHub:                            │
│    cd X:\                                                      │
│    git add .; git commit -m "descripcion"; git push            │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│  EMERGENCIA - RDP CONTROLADO                                   │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Solo cuando necesites escritorio completo:                    │
│    PowerShell Admin > X:\.\rdp-toggle.ps1 -On                  │
│    Win+R > mstsc > $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { `$_.IPAddress -like '192.168.*' } | Select-Object -First 1 -ExpandProperty IPAddress))    │
│    Usuario: $Username / Clave: $Password                       │
│    Al terminar: .\rdp-toggle.ps1 -Off                          │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│  AUTO-SYNC GITHUB (servidor)                                   │
├────────────────────────────────────────────────────────────────┤
│  El servidor sincroniza automaticamente cada 60s:              │
│  - Hace git pull de cambios remotos                            │
│  - Hace git push de cambios locales                            │
│  - Reinicia servicios si detecta cambios                       │
│  Log: logs\auto-sync.log                                       │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│  ARCHIVOS CREADOS                                              │
├────────────────────────────────────────────────────────────────┤
│  $rdpTogglePath         (toggle RDP on/off)      │
│  $connectScriptPath     (conexion desde laptop)   │
│  $syncScriptPath (auto-sync GitHub)   │
│  $ProjectPath\sgc-remote.ps1       (este script)               │
└────────────────────────────────────────────────────────────────┘
"@ -ForegroundColor White

Write-Host "`n✅ Configuracion completa en $env:COMPUTERNAME" -ForegroundColor Green
Write-Host "   Ejecuta en tu laptop: .\connect-laptop.ps1 (despues de copiarlo)" -ForegroundColor Cyan
