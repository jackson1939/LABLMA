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
    [int]$Interval = 60,
    [string]$Branch = "main"
)

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$LogDir = "$ProjectRoot\logs"
$SyncLog = "$LogDir\auto-sync.log"

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

function Write-Sync($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $msg" | Out-File -FilePath $SyncLog -Append -Encoding UTF8
    Write-Host "[$ts] $msg"
}

Write-Sync "Auto-sync iniciado (intervalo: $Interval s, rama: $Branch)"

while ($true) {
    Start-Sleep -Seconds $Interval
    try {
        & git -C $ProjectRoot fetch origin $Branch 2>&1 | Out-Null

        $local = & git -C $ProjectRoot rev-parse $Branch 2>$null
        $remote = & git -C $ProjectRoot rev-parse origin/$Branch 2>$null

        if ($local -and $remote -and $local -ne $remote) {
            Write-Sync "Cambios remotos detectados. Haciendo pull..."
            & git -C $ProjectRoot pull origin $Branch 2>&1 | Out-Null
            Write-Sync "Pull completado"
        }

        $status = & git -C $ProjectRoot status --porcelain 2>&1
        if ($status) {
            $msg = "auto-sync: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            & git -C $ProjectRoot add -A 2>&1 | Out-Null
            & git -C $ProjectRoot commit -m "$msg" 2>&1 | Out-Null
            & git -C $ProjectRoot push origin $Branch 2>&1 | Out-Null
            Write-Sync "Push completado: $msg"
        }
    } catch {
        Write-Sync "ERROR en sync: $_"
    }
}
