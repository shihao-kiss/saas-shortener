# Lens connect Minikube automation script
# Only requires SSH password TWICE: once for data, once for tunnel

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

# ==========================================
# Step 1: Single SSH call to get ALL remote data
#   - kubeconfig content (via kubectl config view --flatten)
#   - minikube port mapping (via docker port)
# This avoids multiple SSH connections / password prompts
# ==========================================
Write-Host "[1/3] Fetch remote data (kubeconfig + port)..." -ForegroundColor Cyan
Write-Host "  -> SSH password required (1st time)" -ForegroundColor Yellow

$separator = "===LENS_SCRIPT_SEPARATOR==="
$remoteCmd = "kubectl config view --flatten 2>/dev/null; echo '$separator'; docker port minikube 2>/dev/null | grep 8443/tcp"
$rawOutput = ssh $LinuxUser@$LinuxIP $remoteCmd

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($rawOutput)) {
    Write-Host "ERROR: SSH failed or no output" -ForegroundColor Red
    exit 1
}

# Split output by separator
$parts = ($rawOutput -join "`n") -split $separator
if ($parts.Length -lt 2) {
    Write-Host "ERROR: Unexpected output format" -ForegroundColor Red
    exit 1
}

$kubeconfigContent = $parts[0].Trim()
$portLine = $parts[1].Trim()

# Parse actual port
$actualPort = ""
if ($portLine -match "127\.0\.0\.1:(\d+)") {
    $actualPort = $Matches[1]
} else {
    Write-Host "ERROR: Cannot parse Minikube port from: $portLine" -ForegroundColor Red
    exit 1
}

Write-Host "OK: Kubeconfig fetched, API port = $actualPort" -ForegroundColor Green

# ==========================================
# Step 2: Patch and save kubeconfig locally
#   - Replace server address with 127.0.0.1:8443 (SSH tunnel endpoint)
#   - Add insecure-skip-tls-verify: true
# ==========================================
Write-Host "[2/3] Patch and save kubeconfig..." -ForegroundColor Cyan

$kubeconfigDir = Split-Path -Parent $KubeconfigPath
if (!(Test-Path $kubeconfigDir)) {
    New-Item -ItemType Directory -Path $kubeconfigDir -Force | Out-Null
}

# Replace server URL: any https://127.0.0.1:XXXXX -> https://127.0.0.1:8443
$kubeconfigContent = $kubeconfigContent -replace "server: https://127\.0\.0\.1:\d+", "server: https://127.0.0.1:8443"

# Add insecure-skip-tls-verify if not present
if ($kubeconfigContent -notmatch "insecure-skip-tls-verify") {
    $kubeconfigContent = $kubeconfigContent -replace "(server: https://127\.0\.0\.1:8443)", "`$1`n    insecure-skip-tls-verify: true"
}

Set-Content -Path $KubeconfigPath -Value $kubeconfigContent -NoNewline
Write-Host "OK: Saved to $KubeconfigPath" -ForegroundColor Green
Write-Host "  server: https://127.0.0.1:8443" -ForegroundColor White
Write-Host "  insecure-skip-tls-verify: true" -ForegroundColor White

# ==========================================
# Step 3: Create SSH tunnel (background)
#   Maps local 8443 -> Linux 127.0.0.1:actualPort -> Minikube API Server
# ==========================================
Write-Host "[3/3] Create SSH tunnel (8443 -> $actualPort)..." -ForegroundColor Cyan

$existingConn = Get-NetTCPConnection -LocalPort 8443 -ErrorAction SilentlyContinue
if ($existingConn) {
    Write-Host "WARN: Port 8443 already in use, tunnel may exist" -ForegroundColor Yellow
} else {
    Write-Host "  -> SSH password required (2nd time, last)" -ForegroundColor Yellow
    Start-Process -FilePath "ssh" -ArgumentList "-L","8443:127.0.0.1:${actualPort}","${LinuxUser}@${LinuxIP}","-N" -WindowStyle Hidden
    Start-Sleep -Seconds 3

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
Write-Host "Tunnel: localhost:8443 -> $LinuxIP -> Minikube:$actualPort" -ForegroundColor Cyan
Write-Host ""
Write-Host "TIP: To avoid password prompts, setup SSH key:" -ForegroundColor Yellow
Write-Host "  ssh-keygen -t ed25519"
Write-Host "  ssh-copy-id $LinuxUser@$LinuxIP"
Write-Host ""
