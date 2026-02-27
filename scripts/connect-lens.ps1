# Lens 连接 Minikube 自动化脚本
# 用途：自动导出 kubeconfig、建立 SSH 隧道，方便 Lens 连接

param(
    [string]$LinuxIP = "192.168.3.200",
    [string]$LinuxUser = "root",
    [string]$KubeconfigPath = "$env:USERPROFILE\.kube\minikube-config"
)

$ErrorActionPreference = "Stop"

Write-Host "========== Lens 连接 Minikube 自动化脚本 ==========" -ForegroundColor Green
Write-Host "Linux 虚拟机: $LinuxUser@$LinuxIP"
Write-Host "Kubeconfig 保存路径: $KubeconfigPath"
Write-Host ""

# 1. 在 Linux 上导出 kubeconfig
Write-Host "[1/5] 在 Linux 上导出 kubeconfig..." -ForegroundColor Cyan
ssh $LinuxUser@$LinuxIP "kubectl config view --flatten > /tmp/kubeconfig-export.yaml"
if ($LASTEXITCODE -ne 0) {
    Write-Host "错误: 无法连接到 Linux 或导出失败" -ForegroundColor Red
    exit 1
}
Write-Host "✓ 导出成功" -ForegroundColor Green

# 2. 复制到 Windows
Write-Host "[2/5] 复制 kubeconfig 到本地..." -ForegroundColor Cyan
$kubeconfigDir = Split-Path -Parent $KubeconfigPath
if (!(Test-Path $kubeconfigDir)) {
    New-Item -ItemType Directory -Path $kubeconfigDir -Force | Out-Null
}
scp "${LinuxUser}@${LinuxIP}:/tmp/kubeconfig-export.yaml" $KubeconfigPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "错误: 复制失败" -ForegroundColor Red
    exit 1
}
Write-Host "✓ 复制成功: $KubeconfigPath" -ForegroundColor Green

# 3. 修改 kubeconfig（添加 insecure-skip-tls-verify）
Write-Host "[3/5] 修改 kubeconfig，添加跳过证书验证..." -ForegroundColor Cyan
$content = Get-Content $KubeconfigPath -Raw
if ($content -notmatch "insecure-skip-tls-verify") {
    # 在第一个 cluster 的 server 行后插入 insecure-skip-tls-verify
    $content = $content -replace "(server: https://127\.0\.0\.1:8443)", "`$1`n    insecure-skip-tls-verify: true"
    Set-Content -Path $KubeconfigPath -Value $content
    Write-Host "✓ 已添加 insecure-skip-tls-verify: true" -ForegroundColor Green
} else {
    Write-Host "✓ 配置已存在，跳过" -ForegroundColor Green
}

# 4. 获取 Minikube 实际端口
Write-Host "[4/5] 获取 Minikube API Server 实际端口..." -ForegroundColor Cyan
$portMapping = ssh $LinuxUser@$LinuxIP "docker port minikube | grep '8443/tcp'"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($portMapping)) {
    Write-Host "错误: 无法获取端口映射，请确保 Minikube 已启动" -ForegroundColor Red
    exit 1
}

# 解析端口号（格式：8443/tcp -> 127.0.0.1:32779）
if ($portMapping -match "127\.0\.0\.1:(\d+)") {
    $actualPort = $Matches[1]
    Write-Host "✓ API Server 实际端口: $actualPort" -ForegroundColor Green
} else {
    Write-Host "错误: 无法解析端口号" -ForegroundColor Red
    Write-Host "输出: $portMapping" -ForegroundColor Yellow
    exit 1
}

# 5. 建立 SSH 隧道（检查是否已存在）
Write-Host "[5/5] 建立 SSH 隧道..." -ForegroundColor Cyan

# 检查 8443 端口是否已被占用
$existingProcess = Get-NetTCPConnection -LocalPort 8443 -ErrorAction SilentlyContinue
if ($existingProcess) {
    Write-Host "⚠ 端口 8443 已被占用，可能隧道已存在" -ForegroundColor Yellow
    Write-Host "  如需重建隧道，请先关闭占用该端口的进程" -ForegroundColor Yellow
} else {
    # 后台启动 SSH 隧道
    Write-Host "正在启动 SSH 隧道: 8443 -> $actualPort..." -ForegroundColor Cyan
    Start-Process -FilePath "ssh" -ArgumentList "-L","8443:127.0.0.1:$actualPort","${LinuxUser}@${LinuxIP}","-N" -WindowStyle Hidden
    Start-Sleep -Seconds 2
    
    # 验证隧道是否成功
    $tunnel = Get-NetTCPConnection -LocalPort 8443 -State Listen -ErrorAction SilentlyContinue
    if ($tunnel) {
        Write-Host "✓ SSH 隧道已建立（后台运行）" -ForegroundColor Green
    } else {
        Write-Host "⚠ 隧道可能未成功启动，请检查 SSH 连接" -ForegroundColor Yellow
    }
}

# 完成提示
Write-Host ""
Write-Host "========== 配置完成 ==========" -ForegroundColor Green
Write-Host ""
Write-Host "下一步操作：" -ForegroundColor Cyan
Write-Host "  1. 打开 Lens Desktop" -ForegroundColor White
Write-Host "  2. File → Add Cluster" -ForegroundColor White
Write-Host "  3. 选择文件: $KubeconfigPath" -ForegroundColor White
Write-Host ""
Write-Host "SSH 隧道信息：" -ForegroundColor Cyan
Write-Host "  本地监听: 127.0.0.1:8443" -ForegroundColor White
Write-Host "  转发到: $LinuxIP → Minikube 端口 $actualPort" -ForegroundColor White
Write-Host ""
Write-Host "关闭隧道：" -ForegroundColor Cyan
Write-Host "  Get-Process | Where-Object {`$_.ProcessName -eq 'ssh' -and `$_.CommandLine -like '*8443*'} | Stop-Process" -ForegroundColor White
Write-Host ""
