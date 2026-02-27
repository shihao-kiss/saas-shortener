# Lens connect Minikube automation script
# Only requires SSH password ONCE (if SSH key is configured: zero times)

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
# Step 1: Single SSH call to fetch ALL data
#   - Generate clean kubeconfig on Linux side with proper format
#   - Get Minikube port mapping
# ==========================================
Write-Host "[1/3] Fetch remote data..." -ForegroundColor Cyan
Write-Host "  -> SSH password required (only once)" -ForegroundColor Yellow

$separator = "===LENS_SCRIPT_SEPARATOR==="

# Remote script that generates clean kubeconfig (single line to avoid CRLF issues)
$remoteScript = "kubectl config view --flatten | sed 's|server: https://.*:8443|server: https://127.0.0.1:8443|' | sed '/certificate-authority-data:/d' | awk '/server: https:\/\/127.0.0.1:8443/{print; print \`"    insecure-skip-tls-verify: true\`"; next}1'; echo '$separator'; docker port minikube 2>/dev/null | grep 8443/tcp"

$rawOutput = ssh $LinuxUser@$LinuxIP $remoteScript

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($rawOutput)) {
    Write-Host "ERROR: SSH failed" -ForegroundColor Red
    exit 1
}

# Split output
$parts = ($rawOutput -join "`n") -split $separator
if ($parts.Length -lt 2) {
    Write-Host "ERROR: Unexpected output" -ForegroundColor Red
    exit 1
}

$kubeconfigContent = $parts[0].Trim()
$portLine = $parts[1].Trim()

# Parse port
$actualPort = ""
if ($portLine -match "127\.0\.0\.1:(\d+)") {
    $actualPort = $Matches[1]
} else {
    Write-Host "ERROR: Cannot parse port from: $portLine" -ForegroundColor Red
    exit 1
}

Write-Host "OK: Data fetched, API port = $actualPort" -ForegroundColor Green

# ==========================================
# Step 2: Save kubeconfig locally
# ==========================================
Write-Host "[2/3] Save kubeconfig..." -ForegroundColor Cyan

$kubeconfigDir = Split-Path -Parent $KubeconfigPath
if (!(Test-Path $kubeconfigDir)) {
    New-Item -ItemType Directory -Path $kubeconfigDir -Force | Out-Null
}

Set-Content -Path $KubeconfigPath -Value $kubeconfigContent -NoNewline
Write-Host "OK: Saved to $KubeconfigPath" -ForegroundColor Green
Write-Host "  server: https://127.0.0.1:8443" -ForegroundColor White
Write-Host "  insecure-skip-tls-verify: true" -ForegroundColor White
Write-Host "  certificate-authority-data: [removed]" -ForegroundColor White

# ==========================================
# Step 3: Create SSH tunnel
# ==========================================
Write-Host "[3/3] Create SSH tunnel (8443 -> $actualPort)..." -ForegroundColor Cyan

$existingConn = Get-NetTCPConnection -LocalPort 8443 -ErrorAction SilentlyContinue
if ($existingConn) {
    Write-Host "WARN: Port 8443 in use, tunnel exists" -ForegroundColor Yellow
} else {
    # Generate tunnel.bat for reliable SSH window launch
    $tunnelBat = "$env:TEMP\lens-ssh-tunnel.bat"
    $batContent = @"
@echo off
title SSH Tunnel: Lens -> Minikube
echo ========================================
echo   SSH Tunnel for Lens
echo ========================================
echo.
echo Local:  127.0.0.1:8443
echo Remote: $LinuxIP -> Minikube:$actualPort
echo.
echo Keep this window open!
echo Closing it will disconnect Lens.
echo.
echo ========================================
echo.
ssh -L 8443:127.0.0.1:$actualPort $LinuxUser@$LinuxIP -N -o ServerAliveInterval=60
"@
    Set-Content -Path $tunnelBat -Value $batContent
    
    Write-Host "  -> Launching SSH tunnel window..." -ForegroundColor Yellow
    Start-Process -FilePath $tunnelBat
    Start-Sleep -Seconds 8

    $tunnel = Get-NetTCPConnection -LocalPort 8443 -State Listen -ErrorAction SilentlyContinue
    if ($tunnel) {
        Write-Host "OK: SSH tunnel running" -ForegroundColor Green
    } else {
        Write-Host "WARN: Tunnel not detected yet. Enter password in the SSH window." -ForegroundColor Yellow
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
Write-Host "TIP: Setup SSH key to avoid password:" -ForegroundColor Yellow
Write-Host "  ssh-keygen -t ed25519"
Write-Host "  type `$env:USERPROFILE\.ssh\id_ed25519.pub | ssh $LinuxUser@$LinuxIP `"cat >> ~/.ssh/authorized_keys`""
Write-Host ""
