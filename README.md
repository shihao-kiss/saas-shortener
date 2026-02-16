# 云原生 SaaS 短链接服务

一个用于学习云原生和 SaaS 开发模式的示例项目。

## 项目简介

这是一个多租户 URL 短链接服务，演示了以下云原生/SaaS 核心概念：

| 概念 | 实现方式 | 相关文件 |
|------|----------|----------|
| **多租户** | 共享数据库 + TenantID 隔离 | `internal/model/model.go` |
| **12-Factor App** | 环境变量配置 | `internal/config/config.go` |
| **API 认证** | API Key + 中间件 | `internal/middleware/tenant.go` |
| **限流** | Redis 滑动窗口 | `internal/middleware/ratelimit.go` |
| **配额管理** | 按套餐分级 (free/pro/enterprise) | `internal/service/service.go` |
| **容器化** | 多阶段 Docker 构建 | `deploy/docker/Dockerfile` |
| **编排** | Kubernetes Deployment/Service/Ingress/HPA | `deploy/k8s/` |
| **自动扩缩容** | Kubernetes HPA | `deploy/k8s/hpa.yaml` |
| **健康检查** | Liveness + Readiness + Startup Probes | `deploy/k8s/deployment.yaml` |
| **监控指标** | Prometheus + 自定义指标 | `internal/middleware/metrics.go` |
| **可视化** | Grafana Dashboard | `deploy/k8s/monitoring/` |
| **结构化日志** | Zap JSON Logger | `internal/middleware/logging.go` |
| **优雅关闭** | Signal + Graceful Shutdown | `cmd/server/main.go` |
| **缓存** | Redis 多级缓存 | `internal/repository/repository.go` |

## 技术栈

- **语言**: Go 1.22
- **Web 框架**: Gin
- **数据库**: PostgreSQL 16
- **缓存**: Redis 7
- **ORM**: GORM
- **日志**: Zap
- **监控**: Prometheus + Grafana
- **容器**: Docker + Docker Compose
- **编排**: Kubernetes

## 快速开始

### 方式一：Docker Compose（推荐初学者）

一键启动所有服务（应用 + 数据库 + Redis + Prometheus + Grafana）：

```bash
# 启动完整环境
make docker-up

# 查看日志
make docker-logs

# 停止
make docker-down
```

### 方式二：本地开发

```bash
# 1. 启动基础设施（数据库 + Redis + 监控）
make infra-up

# 2. 安装 Go 依赖
make deps

# 3. 本地运行
make run
```

### 方式三：部署到 Kubernetes

```bash
# 1. 构建镜像
make docker-build

# 2. 部署到 K8s
make k8s-deploy

# 3. 查看状态
make k8s-status
```

## API 使用示例

### 1. 创建租户（获取 API Key）

```bash
curl -X POST http://localhost:8080/api/v1/tenants \
  -H "Content-Type: application/json" \
  -d '{"name": "我的公司", "plan": "free"}'
```

响应：
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "我的公司",
  "api_key": "abc123...",  // ⚠️ 请妥善保存，只显示一次！
  "plan": "free"
}
```

### 2. 创建短链接

```bash
curl -X POST http://localhost:8080/api/v1/urls \
  -H "Content-Type: application/json" \
  -H "X-API-Key: abc123..." \
  -d '{"url": "https://github.com"}'
```

### 3. 访问短链接

```bash
curl -L http://localhost:8080/AbCdEf
```

### 4. 查看统计

```bash
curl http://localhost:8080/api/v1/stats \
  -H "X-API-Key: abc123..."
```

## 监控

| 服务 | 地址 | 说明 |
|------|------|------|
| 应用 | http://localhost:8080 | SaaS 短链接服务 |
| Prometheus | http://localhost:9090 | 指标采集和查询 |
| Grafana | http://localhost:3000 | 可视化仪表盘 (admin/admin) |

### Prometheus 常用查询 (PromQL)

```promql
# QPS（每秒请求数）
sum(rate(http_requests_total[1m]))

# P99 延迟
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# 按租户统计短链接创建速率
sum(rate(shorturl_created_total[5m])) by (tenant_id)

# 错误率
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100
```

## 项目结构

```
saas-shortener/
├── cmd/
│   └── server/
│       └── main.go              # 程序入口（优雅关闭、依赖注入）
├── internal/
│   ├── config/
│   │   └── config.go            # 12-Factor 配置管理
│   ├── handler/
│   │   └── handler.go           # HTTP 处理器 + 路由注册
│   ├── middleware/
│   │   ├── tenant.go            # 租户认证中间件
│   │   ├── ratelimit.go         # 限流中间件
│   │   ├── metrics.go           # Prometheus 指标中间件
│   │   └── logging.go           # 结构化日志中间件
│   ├── model/
│   │   └── model.go             # 数据模型（多租户）
│   ├── repository/
│   │   └── repository.go        # 数据访问层（DB + Redis）
│   └── service/
│       └── service.go           # 业务逻辑层
├── deploy/
│   ├── docker/
│   │   └── Dockerfile           # 多阶段构建
│   ├── docker-compose/
│   │   └── docker-compose.yaml  # 本地开发环境
│   └── k8s/
│       ├── namespace.yaml       # K8s 命名空间
│       ├── configmap.yaml       # 配置映射
│       ├── secret.yaml          # 密钥
│       ├── deployment.yaml      # 部署（含探针和资源限制）
│       ├── service.yaml         # 服务发现
│       ├── ingress.yaml         # 入口（对外暴露）
│       ├── hpa.yaml             # 自动扩缩容
│       └── monitoring/
│           ├── prometheus.yaml        # Prometheus 配置
│           ├── grafana-datasource.yaml# Grafana 数据源
│           ├── grafana-dashboard.json # Grafana 仪表盘
│           └── servicemonitor.yaml    # K8s ServiceMonitor
├── Makefile                     # 构建和管理命令
├── go.mod
└── README.md
```

## 学习路径建议

1. **第一步 - 理解多租户**: 阅读 `internal/model/model.go`，理解 TenantID 隔离
2. **第二步 - 理解中间件链**: 阅读 `internal/middleware/` 下的四个文件
3. **第三步 - 本地运行**: `make docker-up`，用 curl 调用 API
4. **第四步 - 看监控**: 访问 Grafana (localhost:3000)，观察指标变化
5. **第五步 - 理解 K8s 部署**: 阅读 `deploy/k8s/` 下的 YAML 文件
6. **第六步 - 部署到 K8s**: 使用 minikube 或云服务商的 K8s 集群实践

## SaaS 核心概念速查

| 概念 | 说明 | 本项目中的体现 |
|------|------|---------------|
| Multi-Tenancy | 多租户共享基础设施 | 所有表都有 tenant_id 字段 |
| Tenant Isolation | 租户数据互不可见 | 查询都带 WHERE tenant_id = ? |
| Subscription Plans | 订阅套餐分级 | free/pro/enterprise 三个套餐 |
| API Rate Limiting | API 调用频率限制 | Redis 滑动窗口限流 |
| Quota Management | 资源配额管理 | 不同套餐不同 URL 数量上限 |
| API Key Auth | API 密钥认证 | X-API-Key Header |
| Horizontal Scaling | 水平扩展 | K8s HPA 自动扩缩容 |
| Zero-Downtime Deploy | 零停机部署 | K8s 滚动更新策略 |
| Observability | 可观测性 | Prometheus + Grafana + 结构化日志 |
