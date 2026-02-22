# 云原生 SaaS 短链接服务 — 项目指南

> 环境：CentOS 7 虚拟机（4C8G）+ 宝塔面板 + Docker
>
> 本文档包含：项目介绍、部署运行、API 测试、学习路线

---

## 一、项目介绍

### 1.1 这个项目是什么

一个**多租户 URL 短链接服务**，模拟真实的 SaaS 产品。用户（租户）注册后获得 API Key，通过 API 创建短链接、查看统计，不同套餐有不同的功能配额。

简单说就是：你平时用的短链接服务（如 bit.ly），我们自己造一个，同时学习背后的云原生技术栈。

### 1.2 业务功能

| 功能 | 说明 | 对应 API |
|------|------|----------|
| 租户注册 | 公司/个人注册，获取 API Key | `POST /api/v1/tenants` |
| 创建短链接 | 将长 URL 转为短码 | `POST /api/v1/urls` |
| 短链接跳转 | 访问短码自动 302 重定向到原始 URL | `GET /:code` |
| 点击统计 | 记录每次访问的 IP、User-Agent、Referer | 自动记录 |
| 数据查询 | 查看自己创建的短链接列表和统计 | `GET /api/v1/urls`、`GET /api/v1/stats` |
| 套餐分级 | free/pro/enterprise 三个套餐，配额不同 | 注册时选择 |

### 1.3 SaaS 特性

| SaaS 概念 | 在本项目中的体现 | 代码位置 |
|-----------|-----------------|----------|
| **多租户隔离** | 所有数据表都有 `tenant_id`，查询自动过滤 | `internal/model/model.go` |
| **API Key 认证** | 每个请求携带 `X-API-Key`，中间件自动识别租户 | `internal/middleware/tenant.go` |
| **套餐与配额** | 不同套餐不同限制（URL 数量上限、请求频率） | `internal/service/service.go` |
| **分布式限流** | 基于 Redis 滑动窗口，按租户独立计数 | `internal/middleware/ratelimit.go` |
| **API 版本管理** | 路径前缀 `/api/v1/`，便于后续迭代 | `internal/handler/handler.go` |

### 1.4 云原生特性

| 云原生概念 | 在本项目中的体现 | 代码位置 |
|-----------|-----------------|----------|
| **12-Factor App** | 所有配置通过环境变量注入 | `internal/config/config.go` |
| **容器化** | 多阶段 Dockerfile，最终镜像仅 ~15MB | `deploy/docker/Dockerfile` |
| **编排** | Kubernetes Deployment + Service + Ingress | `deploy/k8s/` |
| **自动扩缩容** | HPA 根据 CPU/内存自动调整 Pod 数量 | `deploy/k8s/hpa.yaml` |
| **健康检查** | Liveness + Readiness + Startup 三种探针 | `deploy/k8s/deployment.yaml` |
| **Prometheus 监控** | 自定义指标（QPS、延迟、租户维度统计） | `internal/middleware/metrics.go` |
| **Grafana 可视化** | 预配置仪表盘展示核心指标 | `deploy/k8s/monitoring/` |
| **结构化日志** | JSON 格式，便于 ELK/Loki 采集 | `internal/middleware/logging.go` |
| **优雅关闭** | 收到 SIGTERM 后等待请求完成再退出 | `cmd/server/main.go` |
| **配置管理** | K8s ConfigMap（普通配置）+ Secret（敏感信息） | `deploy/k8s/configmap.yaml` |

### 1.5 技术栈

| 层次 | 技术 | 作用 |
|------|------|------|
| 语言 | Go 1.22 | 后端开发 |
| Web 框架 | Gin | HTTP 路由和中间件 |
| ORM | GORM | 数据库操作 |
| 数据库 | PostgreSQL 16 | 持久化存储 |
| 缓存 | Redis 7 | 缓存 + 限流 |
| 日志 | Zap | 结构化日志 |
| 监控 | Prometheus | 指标采集 |
| 可视化 | Grafana | 监控仪表盘 |
| 容器 | Docker + Docker Compose | 容器化运行 |
| 编排 | Kubernetes | 生产级部署 |

### 1.6 项目结构

```
saas-shortener/
├── cmd/server/main.go              # 程序入口（依赖注入、优雅关闭）
├── internal/
│   ├── config/config.go            # 配置管理（12-Factor）
│   ├── model/model.go              # 数据模型（多租户核心）
│   ├── repository/repository.go    # 数据访问层（DB + Redis + 缓存）
│   ├── service/service.go          # 业务逻辑层（配额、认证、短码生成）
│   ├── handler/handler.go          # HTTP 处理器（路由、请求响应）
│   └── middleware/
│       ├── tenant.go               # 租户认证中间件
│       ├── ratelimit.go            # 限流中间件
│       ├── metrics.go              # Prometheus 指标中间件
│       └── logging.go              # 结构化日志中间件
├── deploy/
│   ├── docker/Dockerfile           # 多阶段 Docker 构建
│   ├── docker-compose/             # 本地一键启动
│   └── k8s/                        # Kubernetes 部署清单
│       ├── deployment.yaml         # 部署（探针、资源限制、滚动更新）
│       ├── service.yaml            # 服务发现
│       ├── ingress.yaml            # 对外入口
│       ├── hpa.yaml                # 自动扩缩容
│       ├── configmap.yaml          # 配置
│       ├── secret.yaml             # 密钥
│       └── monitoring/             # Prometheus + Grafana 配置
├── docs/                           # 文档
├── scripts/                        # 脚本
└── Makefile                        # 快捷命令
```

---

## 二、部署运行

### 2.1 前提条件

确认虚拟机中已完成：

- [x] Docker 和 Docker Compose 已安装（`docker --version` 和 `docker compose version`）
- [x] Docker 镜像加速和 DNS 已配置（`/etc/docker/daemon.json`）
- [x] 防火墙已放行端口（8080、9090、3000）
- [x] 项目代码已上传到虚拟机

### 2.2 上传代码

从 Windows 宿主机上传（如果还没上传的话）：

```powershell
# 在 Windows PowerShell 中执行（替换 IP 为你的虚拟机 IP）
scp -r "d:\project\study\saas-shortener" dev@192.168.3.200:~/
```

或者通过宝塔面板的 **文件管理** 上传。

### 2.3 启动项目

SSH 连接到虚拟机（或通过宝塔终端）：

```bash
cd ~/saas-shortener

# 一键启动所有服务（首次需要几分钟拉取镜像和编译）
docker compose -f deploy/docker-compose/docker-compose.yaml up -d --build

# 查看所有容器状态（等待全部变成 healthy/running）
docker compose -f deploy/docker-compose/docker-compose.yaml ps
```

### 2.4 验证服务

```bash
# 健康检查
curl http://192.168.3.200:8080/healthz
# 期望: {"service":"saas-shortener","status":"ok"}

# 就绪检查（验证数据库和 Redis 正常）
curl http://192.168.3.200:8080/readyz
# 期望: {"status":"ready"}

# 查看 Prometheus 指标
curl http://192.168.3.200:8080/metrics | head -20
```

### 2.5 访问服务

在 Windows 浏览器中打开（替换为你的虚拟机 IP）：

| 服务 | 地址 | 说明 |
|------|------|------|
| 应用 API | `http://192.168.3.200:8080` | 短链接服务 |
| Prometheus | `http://192.168.3.200:9090` | 监控指标查询 |
| Grafana | `http://192.168.3.200:3000` | 可视化仪表盘（admin/admin） |
| 宝塔面板 | `http://192.168.3.200:8888` | 服务器管理 |

### 2.6 常用管理命令

```bash
# 查看所有容器状态
docker compose -f deploy/docker-compose/docker-compose.yaml ps

# 查看应用日志（Ctrl+C 退出）
docker compose -f deploy/docker-compose/docker-compose.yaml logs -f app

# 查看所有服务日志
docker compose -f deploy/docker-compose/docker-compose.yaml logs -f

# 停止所有服务
docker compose -f deploy/docker-compose/docker-compose.yaml down

# 停止并清除所有数据（重头再来）
docker compose -f deploy/docker-compose/docker-compose.yaml down -v

# 修改代码后重新构建启动
docker compose -f deploy/docker-compose/docker-compose.yaml up -d --build app

# 查看容器资源占用
docker stats
```

---

## 三、使用 Postman 测试 API

### 3.1 导入 Collection

项目提供了现成的 Postman Collection 文件：

1. 在 Windows 上打开 Postman（下载：https://www.postman.com/downloads/）
2. 点击 **Import** → 拖入 `docs/saas-shortener.postman_collection.json`
3. 导入后点击 Collection 名称 → **Variables** 标签
4. 将 `base_url` 改为 `http://192.168.3.200:8080`（你的虚拟机 IP）
5. 保存

Collection 中包含 4 组请求，带有自动化脚本（创建租户后自动保存 API Key）：

| 分组 | 包含请求 |
|------|---------|
| 基础设施 | 健康检查、就绪检查、Prometheus 指标 |
| 租户管理 | 创建 Free 租户、创建 Pro 租户 |
| 短链接管理 | 创建短链接、查看列表、查看统计、测试重定向 |
| 错误场景测试 | 无 API Key（401）、错误 Key（401）、不存在的短码（404）、参数错误（400） |

### 3.2 手动测试流程

如果不用 Collection，也可以手动创建请求：

#### Step 1：创建租户

| 项 | 值 |
|----|----|
| Method | `POST` |
| URL | `http://192.168.3.200:8080/api/v1/tenants` |
| Headers | `Content-Type: application/json` |
| Body | `{"name": "test-company", "plan": "free"}` |

响应中的 `api_key` 只显示一次，**立即复制保存**。

#### Step 2：创建短链接

| 项 | 值 |
|----|----|
| Method | `POST` |
| URL | `http://192.168.3.200:8080/api/v1/urls` |
| Headers | `Content-Type: application/json` 和 `X-API-Key: <你的api_key>` |
| Body | `{"url": "https://github.com"}` |

#### Step 3：测试重定向

在浏览器中直接访问 `http://192.168.3.200:8080/<返回的code>`，会自动跳转到 GitHub。

#### Step 4：查看统计

| 项 | 值 |
|----|----|
| Method | `GET` |
| URL | `http://192.168.3.200:8080/api/v1/stats` |
| Headers | `X-API-Key: <你的api_key>` |

---

## 四、查看监控

### 4.1 Prometheus

访问 `http://192.168.3.200:9090`，在查询框中输入 PromQL：

| 查询 | 含义 |
|------|------|
| `http_requests_total` | 请求总数 |
| `rate(http_requests_total[1m])` | 每秒请求数（QPS） |
| `histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))` | P99 延迟 |
| `shorturl_created_total` | 短链接创建总数 |
| `rate_limit_hits_total` | 限流触发次数 |

### 4.2 Grafana

访问 `http://192.168.3.200:3000`（admin/admin）：

1. 左侧菜单 → **Explore**
2. 顶部数据源选择 **Prometheus**
3. 输入上面的 PromQL 查询，点击 **Run query**

也可以导入预置仪表盘：
1. 左侧菜单 → **Dashboards** → **Import**
2. 上传 `deploy/k8s/monitoring/grafana-dashboard.json`

---

## 五、学习路线

### 阶段总览

```
阶段一：跑通项目，理解 SaaS 多租户          ← 你在这里
    ↓
阶段二：深入代码，理解中间件和分层架构
    ↓
阶段三：学习监控体系，Prometheus + Grafana
    ↓
阶段四：容器化原理，Docker 深入理解
    ↓
阶段五：Kubernetes 部署，理解编排
    ↓
阶段六：动手改造，添加新功能
```

---

### 阶段一：跑通项目，理解 SaaS 多租户（第 1-2 天）

> 目标：项目能跑起来，理解"多租户"这个 SaaS 核心概念

#### 学习内容

1. **启动项目**，用 Postman 跑通完整 API 流程
2. **阅读数据模型** `internal/model/model.go`
   - 理解 `Tenant`（租户）和 `ShortURL`（短链接）的关系
   - 注意每张表都有 `TenantID` 字段 — 这就是多租户隔离的关键
3. **动手验证租户隔离**
   - 创建两个不同的租户（租户 A 和租户 B）
   - 用租户 A 的 API Key 创建几个短链接
   - 用租户 B 的 API Key 查看列表 → 看不到租户 A 的数据
   - 这就是 SaaS 的数据隔离

#### 动手任务

```
□ 启动项目，所有容器正常运行
□ 创建 2 个租户（一个 free，一个 pro）
□ 分别用两个租户的 API Key 创建短链接
□ 验证：租户 A 看不到租户 B 的数据
□ 在浏览器中测试短链接跳转
□ 阅读 internal/model/model.go，理解数据模型
```

#### 核心知识点

- 多租户三种模式：独立数据库 / 独立 Schema / 共享表（本项目用的第三种）
- `TenantID` 是多租户隔离的根基，所有查询都必须带上它
- 不同套餐 = 不同配额（free: 1000 URL, pro: 10000 URL）

---

### 阶段二：深入代码，理解中间件和分层架构（第 3-4 天）

> 目标：理解请求从进来到返回经历了什么，每一层的职责是什么

#### 学习内容

按照请求流转顺序阅读代码：

```
客户端请求
  → Gin Recovery（panic 恢复）
  → middleware/logging.go（记录结构化日志）
  → middleware/metrics.go（记录 Prometheus 指标）
  → middleware/tenant.go（提取 API Key，识别租户）
  → middleware/ratelimit.go（检查限流）
  → handler/handler.go（处理请求，调用 Service）
  → service/service.go（业务逻辑：配额检查、短码生成）
  → repository/repository.go（数据库操作 + Redis 缓存）
  → 返回响应
```

#### 阅读顺序

1. `internal/middleware/tenant.go` — 租户认证怎么做的
2. `internal/middleware/ratelimit.go` — 限流怎么实现的
3. `internal/handler/handler.go` — 路由怎么注册的，Handler 怎么调 Service
4. `internal/service/service.go` — 业务逻辑在哪里，配额怎么检查的
5. `internal/repository/repository.go` — 数据怎么存的，缓存策略是什么
6. `internal/config/config.go` — 配置怎么加载的（12-Factor App）

#### 动手任务

```
□ 按上面的顺序阅读完 6 个文件
□ 能画出一个请求的完整流转图（不用很精确，大致流程就行）
□ 回答：API Key 在哪个环节被提取和验证？
□ 回答：限流数据存在哪里？用的什么算法？
□ 回答：短链接的原始 URL 被缓存在哪里？TTL 是多少？
□ 修改一个配置（如限流阈值），通过环境变量生效，验证效果
```

#### 核心知识点

- 中间件链模式（洋葱模型）：请求层层穿过中间件，响应层层返回
- 分层架构：Handler → Service → Repository，职责分明
- 12-Factor App：配置不硬编码，全部从环境变量读取

---

### 阶段三：学习监控体系（第 5-6 天）

> 目标：理解云原生可观测性三大支柱 — Metrics、Logging、Tracing

#### 学习内容

1. **指标（Metrics）**
   - 阅读 `internal/middleware/metrics.go`
   - 理解 Counter、Histogram、Gauge 三种指标类型
   - 访问 Prometheus `http://虚拟机IP:9090`，练习 PromQL 查询
   
2. **日志（Logging）**
   - 阅读 `internal/middleware/logging.go`
   - 查看应用日志：`docker compose logs -f app`
   - 观察 JSON 格式的结构化日志，注意 tenant_id 等字段

3. **可视化（Grafana）**
   - 导入预置仪表盘 `deploy/k8s/monitoring/grafana-dashboard.json`
   - 理解每个面板的 PromQL 查询含义

#### 动手任务

```
□ 在 Prometheus 中查询 http_requests_total，观察数据
□ 用 Postman 连续发送 10 次请求，观察 QPS 指标变化
□ 在 Prometheus 中查询 P99 延迟
□ 查看应用日志，找到包含特定 tenant_id 的日志条目
□ 在 Grafana 中导入仪表盘，观察图表
□ 尝试触发限流（短时间内大量请求），在 Prometheus 中查看 rate_limit_hits_total
```

#### 核心知识点

- Prometheus Pull 模式：应用暴露 `/metrics` 端点，Prometheus 定期拉取
- PromQL：`rate()` 计算速率，`histogram_quantile()` 计算分位数
- 结构化日志为什么用 JSON：便于日志系统解析、索引和检索

---

### 阶段四：容器化深入理解（第 7-8 天）

> 目标：理解 Docker 的核心概念，能自己写 Dockerfile

#### 学习内容

1. **阅读 Dockerfile** `deploy/docker/Dockerfile`
   - 理解多阶段构建：为什么分 builder 和 runtime 两个阶段
   - 理解层缓存：为什么先 COPY go.mod 再 COPY 源码
   - 理解安全实践：为什么用非 root 用户运行

2. **阅读 Docker Compose** `deploy/docker-compose/docker-compose.yaml`
   - 理解服务编排：多个容器如何协作
   - 理解网络：容器之间通过服务名互相访问
   - 理解持久化：volumes 如何保存数据
   - 理解健康检查：healthcheck 如何判断服务就绪

#### 动手任务

```
□ 阅读 Dockerfile，理解每一行的作用
□ 手动构建镜像：docker build -t saas-shortener:test -f deploy/docker/Dockerfile .
□ 查看镜像大小：docker images saas-shortener
□ 进入运行中的容器：docker exec -it saas-shortener sh
□ 查看容器内的进程：ps aux（只有一个 Go 进程）
□ 查看 Docker 网络：docker network ls 和 docker network inspect
□ 停止 PostgreSQL 容器，观察应用的 Readiness 探针是否变为 not ready
□ 重启 PostgreSQL，观察应用自动恢复
```

#### 核心知识点

- 多阶段构建：编译环境和运行环境分离，最终镜像极小
- 层缓存：Docker 按层缓存，依赖不变就不重新下载
- 容器网络：同一个 docker-compose 中的容器共享网络，通过服务名访问

---

### 阶段五：Kubernetes 入门部署（第 9-12 天）

> 目标：理解 K8s 核心概念，能在本地 K8s 集群中部署项目

#### 准备工作

在虚拟机中安装 minikube（单节点 K8s）：

```bash
# 安装 kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# 安装 minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# 启动集群
minikube start --driver=docker --cpus=2 --memory=2048

# 验证
kubectl cluster-info
kubectl get nodes
```

#### 学习内容

按以下顺序阅读 K8s 清单文件：

| 顺序 | 文件 | 核心概念 |
|------|------|----------|
| 1 | `deploy/k8s/namespace.yaml` | Namespace：资源隔离的逻辑分组 |
| 2 | `deploy/k8s/configmap.yaml` | ConfigMap：非敏感配置 |
| 3 | `deploy/k8s/secret.yaml` | Secret：敏感信息（密码等） |
| 4 | `deploy/k8s/deployment.yaml` | Deployment：Pod 管理、探针、资源限制 |
| 5 | `deploy/k8s/service.yaml` | Service：稳定的网络入口 |
| 6 | `deploy/k8s/ingress.yaml` | Ingress：L7 负载均衡、域名路由 |
| 7 | `deploy/k8s/hpa.yaml` | HPA：自动水平扩缩容 |
| 8 | `deploy/k8s/monitoring/servicemonitor.yaml` | ServiceMonitor：Prometheus 自动发现 |

#### 动手任务

```
□ 安装 minikube，成功启动本地 K8s 集群
□ 按顺序阅读所有 K8s YAML 文件
□ 构建镜像：minikube image build -t saas-shortener:latest -f deploy/docker/Dockerfile .
□ 依次 kubectl apply 部署所有资源
□ 查看 Pod 状态：kubectl get pods -n saas-shortener
□ 查看 Pod 日志：kubectl logs -n saas-shortener <pod-name>
□ 端口转发访问：kubectl port-forward -n saas-shortener svc/saas-shortener-service 8080:80
□ 模拟 Pod 故障：kubectl delete pod <pod-name>，观察 K8s 自动重建
□ 手动扩容：kubectl scale deployment saas-shortener -n saas-shortener --replicas=3
□ 查看 HPA：kubectl get hpa -n saas-shortener
```

#### 核心知识点

- Pod 是 K8s 的最小调度单元，一个 Pod 可以包含多个容器
- Deployment 管理 Pod 的生命周期（创建、更新、回滚）
- Service 提供稳定的内部 DNS 和负载均衡
- HPA 根据指标自动扩缩容，是弹性伸缩的核心

---

### 阶段六：动手改造，巩固所学（第 13 天+）

> 目标：自己动手添加功能，把学到的知识用起来

#### 改造建议（难度递增）

| 难度 | 改造内容 | 练习目标 |
|------|---------|---------|
| ★☆☆ | 给短链接加过期时间功能 | 修改 Model、Service、Handler |
| ★☆☆ | 增加一个 `DELETE /api/v1/urls/:id` 删除接口 | 理解 RESTful API 设计 |
| ★★☆ | 给统计接口加上时间范围过滤（最近7天/30天） | 复杂查询、PromQL |
| ★★☆ | 实现按租户的独立 Grafana 面板 | 深入 Grafana 变量和模板 |
| ★★★ | 添加 WebSocket 实时点击通知 | 实时通信、云原生消息 |
| ★★★ | 接入 CI/CD（GitHub Actions 自动构建部署） | 持续集成/持续部署 |
| ★★★ | 添加 OpenTelemetry 分布式链路追踪 | 可观测性第三支柱 |

---

## 六、常见问题

### Q: docker compose up 构建报错（Alpine 包下载超时）

Docker 容器内 DNS 或网络不通，参见 `vmware-setup-guide.md` 中的排查方法。
确认 `/etc/docker/daemon.json` 中配置了 DNS：

```json
{
  "dns": ["223.5.5.5", "114.114.114.114"]
}
```

### Q: 端口被占用

```bash
# 查看占用端口的进程
ss -tlnp | grep :8080

# 杀掉对应进程
sudo kill -9 <PID>
```

### Q: 容器启动后立即退出

```bash
# 查看退出原因
docker compose -f deploy/docker-compose/docker-compose.yaml logs app

# 常见原因：数据库连接失败（PostgreSQL 还没启动好）
# 解决：等待 PostgreSQL healthy 后重启 app
docker compose -f deploy/docker-compose/docker-compose.yaml restart app
```

### Q: 修改了代码但没生效

Docker 会缓存已构建的层，需要重新构建：

```bash
# 重新构建并启动（--build 是关键）
docker compose -f deploy/docker-compose/docker-compose.yaml up -d --build app
```

### Q: 想完全重新开始

```bash
# 停止所有服务并清除数据（包括数据库数据）
docker compose -f deploy/docker-compose/docker-compose.yaml down -v

# 重新启动
docker compose -f deploy/docker-compose/docker-compose.yaml up -d --build
```



# 七、计划 todo

## 7.1 项目开机自启动

改好了。把改好的文件同步到虚拟机后，重新应用配置：

```
cd ~/saas-shortener

*# 重新应用配置（不会重建容器，只更新重启策略）*

docker compose -f deploy/docker-compose/docker-compose.yaml up -d

现在虚拟机开机后，Docker 服务自动启动 → 5 个容器自动恢复运行，不需要手动操作。
```

### 改了什么

| 修改                                    | 说明                                                         |
| :-------------------------------------- | :----------------------------------------------------------- |
| 删掉 version: "3.8"                     | 消除 version is obsolete 警告，新版 Docker Compose 不需要这个字段 |
| 所有 5 个服务加 restart: unless-stopped | Docker 启动后自动恢复容器                                    |

### restart 策略说明

| 策略           | 行为                                               |
| :------------- | :------------------------------------------------- |
| no             | 默认值，不自动重启                                 |
| always         | 总是重启（包括手动 stop 后重启 Docker 也会拉起来） |
| unless-stopped | 自动重启，除非是手动 stop 的（推荐，更可控）       |
| on-failure     | 只在异常退出时重启                                 |

用 unless-stopped 最合适：开机自动拉起，但 docker compose down 停掉后不会自己又跑起来。

## 7.2 学习 Prometheus

## 7.3 学习 Grafana

## 7.4 学习 K8S

## 7.5 CICD 流程化发布

## 7.6 内网穿透

## 7.7 ELK 日志追踪

## 7.8 链路追踪

## 7.9 NATS

## 7.10 Opensearch

## 7.11 版本跟踪git

## 7.11 不懂的名词

| K8S HPA     |      |
| ----------- | ---- |
| K8S HPA     |      |
| DDD领域设计 |      |
| K8S Ingress |      |
|             |      |
|             |      |

















