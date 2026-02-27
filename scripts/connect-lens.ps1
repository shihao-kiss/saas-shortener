# Lens connect Minikube automation script

param(
    [string]$LinuxIP = "192.168.3.200",
    [string]$LinuxUser = "root",
    [string]$KubeconfigPath = "$env:USERPROFILE\.kube\minikube-config"
)

$ErrorActionPreference = "Stop"

Write-Host "========== Lens -> Minikube ==========" -ForegroundColor Green
Write-Host "Linux VM: $LinuxUser@$LinuxIP"
Write-Host "Kubeconfig: $KubeconfigPath"
Write-Host ""

# 1. Export kubeconfig from Linux
Write-Host "[1/5] Export kubeconfig..." -ForegroundColor Cyan
ssh $LinuxUser@$LinuxIP "kubectl config view --flatten > /tmp/kubeconfig-export.yaml"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: SSH connection failed" -ForegroundColor Red
    exit 1
}
Write-Host "OK: Export done" -ForegroundColor Green

# 2. Copy to Windows
Write-Host "[2/5] Copy kubeconfig to local..." -ForegroundColor Cyan
$kubeconfigDir = Split-Path -Parent $KubeconfigPath
if (!(Test-Path $kubeconfigDir)) {
    New-Item -ItemType Directory -Path $kubeconfigDir -Force | Out-Null
}
scp "${LinuxUser}@${LinuxIP}:/tmp/kubeconfig-export.yaml" $KubeconfigPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: SCP copy failed" -ForegroundColor Red
    exit 1
}
Write-Host "OK: Saved to $KubeconfigPath" -ForegroundColor Green

# 3. Add insecure-skip-tls-verify
Write-Host "[3/5] Patch kubeconfig..." -ForegroundColor Cyan
$content = Get-Content $KubeconfigPath -Raw
if ($content -notmatch "insecure-skip-tls-verify") {
    $content = $content -replace "(server: https://127\.0\.0\.1:\d+)", "`$1`n    insecure-skip-tls-verify: true"
    Set-Content -Path $KubeconfigPath -Value $content -NoNewline
    Write-Host "OK: Added insecure-skip-tls-verify" -ForegroundColor Green
} else {
    Write-Host "OK: Already patched, skip" -ForegroundColor Green
}

# 4. Get minikube actual port
Write-Host "[4/5] Get Minikube API Server port..." -ForegroundColor Cyan
$portMapping = ssh $LinuxUser@$LinuxIP "docker port minikube 2>/dev/null | grep 8443/tcp"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($portMapping)) {
    Write-Host "ERROR: Cannot get port. Is Minikube running?" -ForegroundColor Red
    exit 1
}

$actualPort = ""
if ($portMapping -match "127\.0\.0\.1:(\d+)") {
    $actualPort = $Matches[1]
    Write-Host "OK: API Server port = $actualPort" -ForegroundColor Green
} else {
    Write-Host "ERROR: Cannot parse port" -ForegroundColor Red
    exit 1
}

# 5. Create SSH tunnel
Write-Host "[5/5] Create SSH tunnel..." -ForegroundColor Cyan

$existingConn = Get-NetTCPConnection -LocalPort 8443 -ErrorAction SilentlyContinue
if ($existingConn) {
    Write-Host "WARN: Port 8443 already in use, tunnel may exist" -ForegroundColor Yellow
} else {
    Write-Host "Starting tunnel: localhost:8443 -> $actualPort ..." -ForegroundColor Cyan
    Start-Process -FilePath "ssh" -ArgumentList "-L","8443:127.0.0.1:${actualPort}","${LinuxUser}@${LinuxIP}","-N" -WindowStyle Hidden
    Start-Sleep -Seconds 2

    $tunnel = Get-NetTCPConnection -LocalPort 8443 -State Listen -ErrorAction SilentlyContinue
    if ($tunnel) {
        Write-Host "OK: SSH tunnel running (background)" -ForegroundColor Green
    } else {
        Write-Host "WARN: Tunnel may not have started" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "========== ALL DONE ==========" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Open Lens Desktop"
Write-Host "  2. File -> Add Cluster"
Write-Host "  3. Select: $KubeconfigPath"
Write-Host ""
Write-Host "Tunnel info:" -ForegroundColor Cyan
Write-Host "  Local:  127.0.0.1:8443"
Write-Host "  Remote: $LinuxIP -> Minikube:$actualPort"
Write-Host ""
