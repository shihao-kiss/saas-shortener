# Windows 本地开发环境搭建指南

> 推荐配置：4C8G 以上。你的 12C32G 非常充裕，无需任何资源限制。

## 一、需要安装的软件

### 必装（第一阶段：Docker Compose 跑通项目）

| 软件 | 用途 | 安装方式 |
|------|------|----------|
| **Docker Desktop** | 容器运行环境（已内置 Docker Compose） | 官网下载安装包 |
| **Go 1.22+** | 本地开发调试 | 官网下载或 `winget install GoLang.Go` |
| **Git** | 版本控制 | 官网下载或 `winget install Git.Git` |

### 选装（第二阶段：学习 Kubernetes）

| 软件 | 用途 | 安装方式 |
|------|------|----------|
| **kubectl** | K8s 命令行工具 | `winget install Kubernetes.kubectl` |
| **minikube** | 本地 K8s 集群（推荐） | `winget install Kubernetes.minikube` |
| **Helm** | K8s 包管理器 | `winget install Helm.Helm` |
| **k9s** | K8s 终端 UI（非常好用） | `winget install derailed.k9s` |

---

## 二、第一阶段：用 Docker Compose 跑起来

这是最简单的方式，一键启动所有服务。

### Step 1：安装 Docker Desktop

1. 下载：https://www.docker.com/products/docker-desktop/
2. 安装时勾选 **Use WSL 2 instead of Hyper-V**（推荐）
3. 安装完成后重启电脑
4. 打开 Docker Desktop，等待左下角变成绿色 "Engine running"

验证安装：
```powershell
docker --version          # 应显示 Docker version 2x.x.x
docker compose version    # 应显示 Docker Compose version v2.x.x
```

### Step 2：启动项目

```powershell
# 进入项目目录
cd d:\project\study\saas-shortener

# 一键启动所有服务（首次会拉取镜像 + 编译，需要几分钟）
docker compose -f deploy/docker-compose/docker-compose.yaml up -d --build

# 查看所有容器状态（应该都是 Up/healthy）
docker compose -f deploy/docker-compose/docker-compose.yaml ps
```

### Step 3：验证服务

```powershell
# 1. 健康检查
curl http://localhost:8080/healthz
# 期望输出: {"service":"saas-shortener","status":"ok"}

# 2. 就绪检查（验证数据库和 Redis 连接正常）
curl http://localhost:8080/readyz
# 期望输出: {"status":"ready"}

# 3. 查看 Prometheus 指标
curl http://localhost:8080/metrics
# 期望输出: 一大堆 Prometheus 格式的指标数据
```

### Step 4：使用 Postman 测试 API

```
导出了 Postman Collection 文件
docs/saas-shortener.postman_collection.json 可以直接导入 Postman：
打开 Postman → Import → 拖入这个 JSON 文件
导入后会看到 4 组请求：
基础设施 — 健康检查、就绪检查、Prometheus 指标
租户管理 — 创建 Free/Pro 租户
短链接管理 — 创建/查询/重定向
错误场景测试 — 401、404、400 等异常情况
修改 Collection 变量中的 base_url 为你的实际地址（点击 Collection 名称 → Variables 标签）
Collection 中内置了自动化脚本：创建租户后 api_key 会自动保存到变量，创建短链接后 short_code 也会自动保存，后续请求直接引用，不用手动复制粘贴。
```

推荐使用 Postman 测试 API，操作更直观，还能保存请求方便复用。

**安装 Postman**：https://www.postman.com/downloads/ 下载安装即可。

> 以下示例中 `{{base_url}}` 代表服务地址。
> 如果服务跑在本机：`http://localhost:8080`
> 如果服务跑在虚拟机：`http://192.168.110.xxx:8080`（替换为你的虚拟机 IP）

#### 4.1 健康检查

| 项 | 值 |
|----|----|
| Method | `GET` |
| URL | `{{base_url}}/healthz` |
| Headers | 无 |
| Body | 无 |

期望响应：
```json
{
  "service": "saas-shortener",
  "status": "ok"
}
```

#### 4.2 创建租户（获取 API Key）

| 项 | 值 |
|----|----|
| Method | `POST` |
| URL | `{{base_url}}/api/v1/tenants` |
| Headers | `Content-Type: application/json` |
| Body (raw JSON) | 见下方 |

Body：
```json
{
  "name": "test-company",
  "plan": "free"
}
```

期望响应：
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "test-company",
  "api_key": "abc123def456...",
  "plan": "free"
}
```

**⚠️ 复制 `api_key` 的值！后续所有请求都要用它。建议在 Postman 中设置为环境变量：**

1. 右上角点击 **Environment** → **New Environment**
2. 添加两个变量：
   - `base_url` = `http://localhost:8080`（或虚拟机 IP 地址）
   - `api_key` = 上一步返回的 api_key 值
3. 保存并选中这个环境

#### 4.3 创建短链接

| 项 | 值 |
|----|----|
| Method | `POST` |
| URL | `{{base_url}}/api/v1/urls` |
| Headers | `Content-Type: application/json` |
| | `X-API-Key: {{api_key}}` |
| Body (raw JSON) | 见下方 |

Body：
```json
{
  "url": "https://github.com"
}
```

期望响应：
```json
{
  "id": "...",
  "code": "AbCdEf",
  "short_url": "/AbCdEf",
  "original_url": "https://github.com",
  "clicks": 0,
  "created_at": "2026-02-14T..."
}
```

> 可以多创建几个，换不同的 URL 测试。

#### 4.4 查看短链接列表

| 项 | 值 |
|----|----|
| Method | `GET` |
| URL | `{{base_url}}/api/v1/urls?page=1&page_size=20` |
| Headers | `X-API-Key: {{api_key}}` |
| Body | 无 |

#### 4.5 查看统计信息

| 项 | 值 |
|----|----|
| Method | `GET` |
| URL | `{{base_url}}/api/v1/stats` |
| Headers | `X-API-Key: {{api_key}}` |
| Body | 无 |

期望响应：
```json
{
  "total_urls": 3,
  "total_clicks": 0,
  "active_urls": 3
}
```

#### 4.6 测试短链接重定向

| 项 | 值 |
|----|----|
| Method | `GET` |
| URL | `{{base_url}}/AbCdEf`（替换为你创建的 code） |
| Headers | 无 |
| Settings | 关闭 "Automatically follow redirects"（在 Settings 标签页中） |

> **关闭自动重定向**后可以看到 302 响应和 `Location` 头部。如果不关，Postman 会直接跳转到目标页面。

#### 4.7 Postman 配置技巧

**设置环境变量自动保存 API Key：**

在"创建租户"请求的 **Tests** 标签页中添加以下脚本，创建租户后自动保存 api_key：

```javascript
if (pm.response.code === 201) {
    var data = pm.response.json();
    pm.environment.set("api_key", data.api_key);
    console.log("API Key 已自动保存: " + data.api_key);
}
```

这样后续请求的 `{{api_key}}` 会自动填充，不用手动复制粘贴。

### Step 5：查看监控

打开浏览器访问：
- **Prometheus**: http://localhost:9090
  - 尝试查询: `http_requests_total` 或 `rate(http_requests_total[1m])`
- **Grafana**: http://localhost:3000
  - 账号: admin / 密码: admin
  - 左侧菜单 → Explore → 选择 Prometheus 数据源 → 输入 PromQL 查询

### 常用管理命令

```powershell
# 查看所有容器日志
docker compose -f deploy/docker-compose/docker-compose.yaml logs -f

# 只看应用日志
docker compose -f deploy/docker-compose/docker-compose.yaml logs -f app

# 停止所有服务
docker compose -f deploy/docker-compose/docker-compose.yaml down

# 停止并清除所有数据（包括数据库）
docker compose -f deploy/docker-compose/docker-compose.yaml down -v

# 重启应用（代码改了之后）
docker compose -f deploy/docker-compose/docker-compose.yaml up -d --build app
```

---

## 三、第二阶段：本地 Kubernetes（进阶）

当你熟悉了 Docker Compose 之后，可以进一步学习 K8s 部署。

### 方案 A：Docker Desktop 自带 K8s（最简单）

1. 打开 Docker Desktop → Settings → Kubernetes
2. 勾选 **Enable Kubernetes**
3. 点击 Apply & Restart，等待几分钟
4. 验证：`kubectl cluster-info`

### 方案 B：Minikube（推荐，更接近真实环境）

```powershell
# 安装
winget install Kubernetes.minikube

# 启动集群（分配 4GB 内存、2 核 CPU）
minikube start --cpus=4 --memory=4096 --driver=docker

# 验证
kubectl cluster-info
kubectl get nodes
```

### 部署到本地 K8s

```powershell
# 1. 先在 minikube 中构建镜像（不用推到远程仓库）
minikube image build -t saas-shortener:latest -f deploy/docker/Dockerfile .

# 2. 在 K8s 中部署 PostgreSQL 和 Redis（简易版）
#    生产环境通常用 Helm Chart 部署，这里先简单跑起来
kubectl apply -f deploy/k8s/namespace.yaml
kubectl apply -f deploy/k8s/configmap.yaml
kubectl apply -f deploy/k8s/secret.yaml
kubectl apply -f deploy/k8s/deployment.yaml
kubectl apply -f deploy/k8s/service.yaml
kubectl apply -f deploy/k8s/hpa.yaml

# 3. 查看状态
kubectl get all -n saas-shortener

# 4. 端口转发（本地访问）
kubectl port-forward -n saas-shortener svc/saas-shortener-service 8080:80
```

---

## 四、常见问题

### Q: docker compose up 时镜像拉取很慢？
配置 Docker 镜像加速器：
Docker Desktop → Settings → Docker Engine → 添加：
```json
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ]
}
```

### Q: 端口被占用？
```powershell
# 查看占用端口的进程
netstat -ano | findstr :8080
# 杀掉对应 PID
taskkill /PID <PID> /F
```

### Q: WSL 2 没安装？
Docker Desktop 需要 WSL 2，如果没有：
```powershell
# 以管理员身份运行 PowerShell
wsl --install
# 重启电脑
```

### Q: Go 编译很慢？
设置 Go 代理加速依赖下载：
```powershell
go env -w GOPROXY=https://goproxy.cn,direct
```
