<#
.SYNOPSIS
  SGC - Configurar acceso remoto por carpeta compartida.
  EJECUTAR EN EL SERVIDOR (192.168.1.194) como ADMINISTRADOR.
  
  PASOS:
  1. Abri PowerShell como ADMINISTRADOR (boton derecho > Ejecutar como Admin)
  2. Navega: cd C:\LABUGRAM\sgc
  3. Ejecuta: .\setup-share-manual.ps1
#>

$ErrorActionPreference = "Stop"

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Ejecuta como ADMINISTRADOR (boton derecho > PowerShell Admin)" -ForegroundColor Red
    exit 1
}

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║  SGC - CONFIGURAR ACCESO REMOTO DESDE SERVIDOR             ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# ── 1. CREAR USUARIO ──
Write-Host "`n[PASO 1/4] Creando usuario 'sgc'..." -ForegroundColor Cyan
$username = "sgc"
$password = "SgcAdmin2024!"
$user = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
if (-not $user) {
    $pass = ConvertTo-SecureString $password -AsPlainText -Force
    New-LocalUser -Name $username -Password $pass -FullName "SGC Remote" -Description "Acceso remoto SGC - carpeta compartida"
    Add-LocalGroupMember -Group "Administradores" -Member $username
    Write-Host "  [OK] Usuario '$username' creado y agregado a Administradores" -ForegroundColor Green
} else {
    Write-Host "  [OK] Usuario '$username' ya existe" -ForegroundColor Green
}

# ── 2. COMPARTIR CARPETA ──
Write-Host "`n[PASO 2/4] Compartiendo carpeta del proyecto..." -ForegroundColor Cyan
$shareName = "sgc"
$projectPath = "C:\LABUGRAM\sgc"

$existing = Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue
if ($existing) { Remove-SmbShare -Name $shareName -Force -Confirm:$false; Start-Sleep 1 }

# Intentar con nombres de cuenta locales
try {
    New-SmbShare -Name $shareName -Path $projectPath -FullAccess "Todos","Administradores","sgc" -ChangeAccess "Todos","sgc" -Description "SGC - Edicion de codigo remota" -ErrorAction Stop
    Write-Host "  [OK] Carpeta compartida como \\$env:COMPUTERNAME\sgc" -ForegroundColor Green
} catch {
    # Fallback con SIDs
    New-SmbShare -Name $shareName -Path $projectPath -FullAccess "S-1-1-0","S-1-5-32-544" -ChangeAccess "S-1-1-0" -Description "SGC - Edicion remota" -ErrorAction Stop
    Write-Host "  [OK] Carpeta compartida (via SID)" -ForegroundColor Green
}

# ── 3. FIREWALL + RED ──
Write-Host "`n[PASO 3/4] Configurando firewall y red..." -ForegroundColor Cyan

# Activar reglas SMB
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue

# Abrir puertos explicitamente
$ports = @(445, 137, 138, 139)
foreach ($port in $ports) {
    $ruleName = "SGC-SMB-Port-$port"
    $exists = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if (-not $exists) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
    }
}

# Cambiar red a Privada (necesario para SMB)
try {
    Set-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop
    Write-Host "  [OK] Red cambiada a Privada" -ForegroundColor Green
} catch {
    Write-Host "  [!] No se pudo cambiar red automaticamente" -ForegroundColor Yellow
    Write-Host "      Hacelo manual: Configuracion > Red e Internet > WiFi > Propiedades" -ForegroundColor Yellow
    Write-Host "      Perfil de red > Privada" -ForegroundColor Yellow
}

# Habilitar guest auth
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "AllowInsecureGuestAuth" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Firewall y red configurados" -ForegroundColor Green

# ── 4. VERIFICAR ──
Write-Host "`n[PASO 4/4] Verificando..." -ForegroundColor Cyan
$ip = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' } | Select-Object -First 1 -ExpandProperty IPAddress

Write-Host @"

╔══════════════════════════════════════════════════════════════════╗
║  CONFIGURACION COMPLETA EN EL SERVIDOR                          ║
╚══════════════════════════════════════════════════════════════════╝

  Servidor: $env:COMPUTERNAME ($ip)

┌────────────────────────────────────────────────────────────────┐
│  AHORA EN TU LAPTOP (conectada a la MISMA red WiFi):           │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  1. PowerShell como ADMINISTRADOR:                             │
│     Windows > buscar "PowerShell" > Ejecutar como Admin        │
│                                                                │
│  2. Ejecuta:                                                   │
│     net use X: \\$ip\sgc /user:sgc SgcAdmin2024!              │
│     X:                                                         │
│                                                                │
│  3. Si da ERROR 53 o 67 (Windows no deja conectar):           │
│     En la laptop, PowerShell ADMIN, ejecuta:                   │
│                                                                │
│     -- Habilitar SMB en laptop:                                │
│     Enable-WindowsOptionalFeature -Online -FeatureName         │
│       SMB1Protocol -All                                        │
│                                                                │
│     -- Firewall laptop:                                        │
│     netsh advfirewall firewall set rule group=                 │
│       "Compartir archivos e impresoras" new enable=Yes         │
│                                                                │
│     -- Permitir guest auth en laptop:                          │
│     Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\          │
│       Services\LanmanWorkstation\Parameters"                   │
│       -Name AllowInsecureGuestAuth -Value 1 -Type DWord -Force │
│                                                                │
│     -- Reiniciar servicio:                                     │
│     net stop lanmanworkstation && net start lanmanworkstation  │
│                                                                │
│  4. Despues de conectar, abri X:\ en el explorador             │
│     y edita los archivos. Los cambios se ven al instante.      │
│                                                                │
└────────────────────────────────────────────────────────────────┘

  URL del sistema: http://$ip`:3000
"@ -ForegroundColor Cyan

Write-Host "`n✅ Listo. Configuración aplicada en el servidor." -ForegroundColor Green
