# ============================================================
# SaaS 短链接服务 - API 测试脚本 (PowerShell)
# 使用方式：.\scripts\test-api.ps1
# ============================================================

$BASE_URL = "http://localhost:8080"

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " SaaS 短链接服务 - API 测试" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# ==================== 1. 健康检查 ====================
Write-Host "[1/6] 健康检查..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "$BASE_URL/healthz" -Method Get
    Write-Host "  Liveness:  $($health | ConvertTo-Json -Compress)" -ForegroundColor Green
    
    $ready = Invoke-RestMethod -Uri "$BASE_URL/readyz" -Method Get
    Write-Host "  Readiness: $($ready | ConvertTo-Json -Compress)" -ForegroundColor Green
} catch {
    Write-Host "  服务未启动! 请先运行: docker compose -f deploy/docker-compose/docker-compose.yaml up -d --build" -ForegroundColor Red
    exit 1
}
Write-Host ""

# ==================== 2. 创建租户 ====================
Write-Host "[2/6] 创建测试租户..." -ForegroundColor Yellow
$tenantBody = @{
    name = "test-company"
    plan = "free"
} | ConvertTo-Json

try {
    $tenant = Invoke-RestMethod -Uri "$BASE_URL/api/v1/tenants" -Method Post -Body $tenantBody -ContentType "application/json"
    $API_KEY = $tenant.api_key
    Write-Host "  租户ID:   $($tenant.id)" -ForegroundColor Green
    Write-Host "  租户名称: $($tenant.name)" -ForegroundColor Green
    Write-Host "  套餐:     $($tenant.plan)" -ForegroundColor Green
    Write-Host "  API Key:  $API_KEY" -ForegroundColor Magenta
    Write-Host "  (API Key 只显示一次，请妥善保存!)" -ForegroundColor Magenta
} catch {
    Write-Host "  创建租户失败: $_" -ForegroundColor Red
    exit 1
}
Write-Host ""

# ==================== 3. 创建短链接 ====================
Write-Host "[3/6] 创建短链接..." -ForegroundColor Yellow
$urls = @(
    "https://github.com",
    "https://www.google.com",
    "https://go.dev"
)

$createdCodes = @()
foreach ($url in $urls) {
    $urlBody = @{ url = $url } | ConvertTo-Json
    try {
        $result = Invoke-RestMethod -Uri "$BASE_URL/api/v1/urls" -Method Post `
            -Body $urlBody -ContentType "application/json" `
            -Headers @{ "X-API-Key" = $API_KEY }
        $createdCodes += $result.code
        Write-Host "  $url -> /$($result.code)" -ForegroundColor Green
    } catch {
        Write-Host "  创建失败 ($url): $_" -ForegroundColor Red
    }
}
Write-Host ""

# ==================== 4. 查看短链接列表 ====================
Write-Host "[4/6] 查询短链接列表..." -ForegroundColor Yellow
try {
    $list = Invoke-RestMethod -Uri "$BASE_URL/api/v1/urls?page=1&page_size=10" -Method Get `
        -Headers @{ "X-API-Key" = $API_KEY }
    Write-Host "  总数: $($list.total) 条" -ForegroundColor Green
    foreach ($item in $list.data) {
        Write-Host "  - /$($item.code) -> $($item.original_url) (点击: $($item.clicks))" -ForegroundColor Green
    }
} catch {
    Write-Host "  查询失败: $_" -ForegroundColor Red
}
Write-Host ""

# ==================== 5. 测试重定向 ====================
Write-Host "[5/6] 测试短链接重定向..." -ForegroundColor Yellow
if ($createdCodes.Count -gt 0) {
    $testCode = $createdCodes[0]
    try {
        # 使用 -MaximumRedirection 0 来捕获 302 重定向而不是跟随它
        $response = Invoke-WebRequest -Uri "$BASE_URL/$testCode" -Method Get -MaximumRedirection 0 -ErrorAction SilentlyContinue
        Write-Host "  /$testCode -> 302 重定向到: $($response.Headers.Location)" -ForegroundColor Green
    } catch {
        # Invoke-WebRequest 会把 3xx 当作错误
        if ($_.Exception.Response.StatusCode.value__ -eq 302) {
            $location = $_.Exception.Response.Headers.Location
            Write-Host "  /$testCode -> 302 重定向到: $location" -ForegroundColor Green
        } else {
            Write-Host "  重定向测试: 状态码 $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Yellow
        }
    }
}
Write-Host ""

# ==================== 6. 查看统计 ====================
Write-Host "[6/6] 查看统计信息..." -ForegroundColor Yellow
try {
    $stats = Invoke-RestMethod -Uri "$BASE_URL/api/v1/stats" -Method Get `
        -Headers @{ "X-API-Key" = $API_KEY }
    Write-Host "  总 URL 数:   $($stats.total_urls)" -ForegroundColor Green
    Write-Host "  活跃 URL 数: $($stats.active_urls)" -ForegroundColor Green
    Write-Host "  总点击数:    $($stats.total_clicks)" -ForegroundColor Green
} catch {
    Write-Host "  查询失败: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " 测试完成!" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "接下来你可以：" -ForegroundColor White
Write-Host "  1. 打开 Prometheus:  http://localhost:9090" -ForegroundColor White
Write-Host "     试试查询: rate(http_requests_total[1m])" -ForegroundColor Gray
Write-Host "  2. 打开 Grafana:     http://localhost:3000  (admin/admin)" -ForegroundColor White
Write-Host "     左侧 Explore -> 选 Prometheus -> 输入 PromQL" -ForegroundColor Gray
Write-Host "  3. 查看应用日志:" -ForegroundColor White
Write-Host "     docker compose -f deploy/docker-compose/docker-compose.yaml logs -f app" -ForegroundColor Gray
Write-Host ""
