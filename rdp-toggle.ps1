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
    [switch]$On,
    [switch]$Off
)

$ErrorActionPreference = "Stop"

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "Ejecuta como ADMINISTRADOR" -ForegroundColor Red
    exit 1
}

$serverIP = "$((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' } | Select-Object -First 1 -ExpandProperty IPAddress))"

if ($On) {
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
    Write-Host "║  Win+R > mstsc > $serverIP                        ║" -ForegroundColor Green
    Write-Host "║  Usuario: sgc / Clave: SgcAdmin2024!             ║" -ForegroundColor Green
    Write-Host "║                                                   ║" -ForegroundColor Green
    Write-Host "║  Para salir:  .\rdp-toggle.ps1 -Off               ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Green
}
elseif ($Off) {
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 1
    Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Write-Host "RDP DESACTIVADO - Servidor seguro" -ForegroundColor Green
}
else {
    Write-Host "Uso:" -ForegroundColor Cyan
    Write-Host "  .\rdp-toggle.ps1 -On    (activar RDP)" -ForegroundColor Cyan
    Write-Host "  .\rdp-toggle.ps1 -Off   (desactivar RDP)" -ForegroundColor Cyan
}
