<#
.SYNOPSIS
  Conecta tu laptop al servidor SGC via carpeta compartida.
  Ejecutar en tu laptop (NO en el servidor).

.DESCRIPTION
  - Monta X:\ como la carpeta compartida del servidor
  - Abre el proyecto en el explorador
  - Muestra las URLs del servidor
#>

$serverIP = "192.168.1.194"
$shareName = "sgc"
$username = "sgc"
$password = "SgcAdmin2024!"
$driveLetter = "X:"

Write-Host "Conectando a \\$serverIP\$shareName ..." -ForegroundColor Cyan

try { net use $driveLetter /delete /y 2>$null } catch {}

net use $driveLetter \\$serverIP\$shareName /user:$username $password 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Unidad $driveLetter montada como \\$serverIP\$shareName" -ForegroundColor Green
    Invoke-Item "$driveLetter\"
    Write-Host ""
    Write-Host "Accesos:" -ForegroundColor Cyan
    Write-Host "  Frontend: http://$serverIP`:3000" -ForegroundColor Green
    Write-Host "  Backend:  http://$serverIP`:8000/docs" -ForegroundColor Green
    Write-Host "  API Docs: http://$serverIP`:8000/docs" -ForegroundColor Green
    Write-Host ""
    Write-Host "Comandos utiles (en X:\):" -ForegroundColor Yellow
    Write-Host "  .\rdp-toggle.ps1 -On   (activar RDP)" -ForegroundColor Gray
    Write-Host "  npm run dev             (ver logs en servidor)" -ForegroundColor Gray
    Write-Host "  npm run status          (ver estado)" -ForegroundColor Gray
} else {
    Write-Host "[ERROR] No se pudo conectar. Verifica:" -ForegroundColor Red
    Write-Host "  1. El servidor esta encendido?" -ForegroundColor Yellow
    Write-Host "  2. Estas en la misma red LAN?" -ForegroundColor Yellow
    Write-Host "  3. Firewall? Puerto 445 abierto?" -ForegroundColor Yellow
    Write-Host "  Conecta manual: net use X: \\$serverIP\$shareName /user:$username" -ForegroundColor Yellow
}
