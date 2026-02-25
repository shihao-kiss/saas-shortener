# Kubernetes 项目实战解读

> 逐文件解读本项目 `deploy/k8s/` 下的所有配置，串联概念与实践。
>
> 建议先阅读 [K8S 概念入门指南](./k8s-concepts.md)。

---

## 部署文件总览

```
deploy/k8s/
├── namespace.yaml              # 1. 创建命名空间
├── configmap.yaml              # 2. 注入普通配置
├── secret.yaml                 # 3. 注入敏感配置
├── deployment.yaml             # 4. 部署应用（核心）
├── service.yaml                # 5. 集群内服务发现
├── ingress.yaml                # 6. 对外暴露 HTTP
├── hpa.yaml                    # 7. 自动扩缩容
└── monitoring/
    ├── prometheus.yaml          # 8. Prometheus 采集配置
    ├── grafana-datasource.yaml  # 9. Grafana 数据源
    ├── grafana-dashboard.json   # 10. Grafana 仪表盘
    └── servicemonitor.yaml      # 11. K8S 原生监控发现
```

**部署顺序**（有依赖关系，必须按顺序）：

```
Namespace → ConfigMap / Secret → Deployment → Service → Ingress → HPA
```

> 原因：Deployment 引用了 ConfigMap 和 Secret，Service 引用了 Deployment 的 Pod 标签，Ingress 引用了 Service，HPA 引用了 Deployment。

**一键部署命令**：

```bash
kubectl apply -f deploy/k8s/namespace.yaml
kubectl apply -f deploy/k8s/configmap.yaml
kubectl apply -f deploy/k8s/secret.yaml
kubectl apply -f deploy/k8s/deployment.yaml
kubectl apply -f deploy/k8s/service.yaml
kubectl apply -f deploy/k8s/ingress.yaml
kubectl apply -f deploy/k8s/hpa.yaml
kubectl apply -f deploy/k8s/monitoring/

# 或者一次性全部应用（K8S 会自动处理依赖）
kubectl apply -f deploy/k8s/ --recursive
```

---

## 1. namespace.yaml — 划分领地

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: saas-shortener
  labels:
    app: saas-shortener
    monitoring: enabled         # Prometheus 通过此标签发现整个 Namespace
```

**作用**：为项目创建独立的命名空间，后续所有资源都放在 `saas-shortener` 这个 Namespace 下。

**为什么不用 default Namespace？**

- 资源隔离：不同项目互不干扰
- 权限控制：可以对 Namespace 设置 RBAC 权限
- 资源配额：可以限制整个 Namespace 的 CPU/内存总量
- 便于管理：`kubectl delete namespace saas-shortener` 一键清理所有资源

---

## 2. configmap.yaml — 配置中心

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: saas-shortener-config
  namespace: saas-shortener
data:
  APP_ENV: "production"
  SERVER_PORT: "8080"
  DB_HOST: "postgres-service"        # K8S 内部 DNS 名称
  DB_PORT: "5432"
  DB_NAME: "saas_shortener"
  DB_SSLMODE: "disable"
  REDIS_ADDR: "redis-service:6379"
  TENANT_DEFAULT_RATE_LIMIT: "100"
  TENANT_MAX_URLS: "1000"
```

**要点**：

- `DB_HOST: "postgres-service"` — 这不是 IP，而是 K8S Service 的 DNS 名称，集群内自动解析
- 所有值都是**字符串**（即使是数字也要加引号）
- 修改 ConfigMap 后，需要**重启 Pod** 才能生效（环境变量方式注入不会热更新）

```bash
# 修改后重启 Pod 的方式
kubectl rollout restart deployment/saas-shortener -n saas-shortener
```

---

## 3. secret.yaml — 密码保险箱

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: saas-shortener-secret
  namespace: saas-shortener
type: Opaque
data:
  DB_USER: cG9zdGdyZXM=             # "postgres" 的 Base64
  DB_PASSWORD: cG9zdGdyZXM=         # "postgres" 的 Base64
  REDIS_PASSWORD: ""
```

**要点**：

- `type: Opaque` 是最常见的 Secret 类型，表示自定义键值对
- 生产环境密码绝不能是 "postgres"，应使用强随机密码
- 不要把 Secret 的 YAML 文件提交到 Git！生产环境建议用 Sealed Secrets 或 External Secrets Operator

**其他 Secret 类型**：

| type | 用途 |
|------|------|
| `Opaque` | 自定义键值对（最常用） |
| `kubernetes.io/tls` | TLS 证书（cert + key） |
| `kubernetes.io/dockerconfigjson` | 镜像仓库拉取凭证 |
| `kubernetes.io/basic-auth` | 用户名密码 |

---

## 4. deployment.yaml — 核心部署（逐段解读）

这是最重要也最复杂的文件，分段解读：

### 4.1 元数据

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: saas-shortener
  namespace: saas-shortener
  labels:
    app: saas-shortener
    version: v1
```

- `apiVersion: apps/v1` — Deployment 属于 `apps` API 组
- `labels.version: v1` — 版本标签，方便灰度发布时区分版本

### 4.2 副本与选择器

```yaml
spec:
  replicas: 2
  selector:
    matchLabels:
      app: saas-shortener
```

- `replicas: 2` — 始终保持 2 个 Pod 运行（配合 HPA 后，此值会被 HPA 覆盖）
- `selector.matchLabels` — **必须**和 `template.metadata.labels` 匹配，否则 Deployment 不知道管理哪些 Pod

### 4.3 滚动更新策略

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0       # 更新时，不可用的 Pod 数 = 0
    maxSurge: 1             # 更新时，额外多创建的 Pod 数 = 1
```

**本项目的策略含义**：更新时先创建 1 个新 Pod，确认就绪后再删除 1 个旧 Pod，始终保持 2 个可用 Pod——**零停机更新**。

### 4.4 Pod 模板 — Annotations

```yaml
template:
  metadata:
    labels:
      app: saas-shortener
      version: v1
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "8080"
      prometheus.io/path: "/metrics"
```

- `labels` 被 Service 的 selector 用来发现 Pod
- `annotations` 告诉 Prometheus "请采集这个 Pod 的 8080 端口 /metrics 路径"

> Label vs Annotation：Label 用于选择/过滤（K8S 系统使用），Annotation 用于存储附加信息（第三方工具使用）。

### 4.5 Pod 模板 — 容器配置

```yaml
spec:
  terminationGracePeriodSeconds: 30
  containers:
    - name: saas-shortener
      image: saas-shortener:latest
      imagePullPolicy: IfNotPresent
      ports:
        - name: http
          containerPort: 8080
```

- `terminationGracePeriodSeconds: 30` — Pod 被删除时，给 30 秒优雅退出（处理完当前请求）
- `imagePullPolicy: IfNotPresent` — 本地有镜像就不拉取（生产环境建议用具体 tag，如 `v1.2.3`，避免用 `latest`）

### 4.6 环境变量注入

```yaml
envFrom:
  - configMapRef:
      name: saas-shortener-config     # 注入整个 ConfigMap
  - secretRef:
      name: saas-shortener-secret     # 注入整个 Secret
```

这两行把 ConfigMap 和 Secret 中的所有键值对都注入为环境变量。在 Go 代码中通过 `os.Getenv("DB_HOST")` 读取。

### 4.7 三种健康检查探针

```yaml
startupProbe:                          # 启动探针
  httpGet:
    path: /healthz
    port: http
  periodSeconds: 5
  failureThreshold: 12                 # 最多等 60 秒启动

livenessProbe:                         # 存活探针
  httpGet:
    path: /healthz
    port: http
  initialDelaySeconds: 10
  periodSeconds: 15
  failureThreshold: 3                  # 连续 3 次失败 → 重启

readinessProbe:                        # 就绪探针
  httpGet:
    path: /readyz
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 3                  # 连续 3 次失败 → 摘流量
```

**时间线**：

```
0s        5s       10s      15s      20s      25s      30s
│         │        │        │        │        │        │
├─ startup probe ──────────────────────────────────────┤ (最多60s)
│  每5s检查一次，成功后：                                  │
│                  ├─ liveness (每15s) ─────────────────┤
│              ├─ readiness (每10s) ────────────────────┤
```

**`/healthz` vs `/readyz` 的区别**：

| 端点 | 检查内容 | 失败含义 |
|------|---------|---------|
| `/healthz` | 应用进程是否存活 | 应用已死，需要重启 |
| `/readyz` | 应用是否能处理请求（DB/Redis 连接正常） | 暂时别发请求给我 |

### 4.8 资源限制

```yaml
resources:
  requests:
    cpu: "100m"             # 调度保障：0.1 核
    memory: "128Mi"         # 调度保障：128MB
  limits:
    cpu: "500m"             # 上限：0.5 核
    memory: "256Mi"         # 上限：256MB（超过会 OOM Kill）
```

---

## 5. service.yaml — 服务发现

```yaml
apiVersion: v1
kind: Service
metadata:
  name: saas-shortener-service
  namespace: saas-shortener
spec:
  type: ClusterIP
  selector:
    app: saas-shortener           # 匹配 Pod 的 label
  ports:
    - name: http
      port: 80                    # Service 的端口
      targetPort: http            # Pod 的端口（8080）
```

**流量路径**：

```
Ingress → Service:80 → Pod:8080

具体来说：
请求到达 saas-shortener-service:80
       ↓ selector 匹配 app=saas-shortener 的 Pod
       ↓ 负载均衡（轮询）
Pod 1:8080  或  Pod 2:8080
```

**`port` vs `targetPort`**：

- `port: 80` — 其他服务访问 Service 时用的端口
- `targetPort: http` — Service 转发到 Pod 的端口（这里 `http` 是端口名，对应 Deployment 中 `containerPort: 8080`）

---

## 6. ingress.yaml — 外部入口

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: saas-shortener-ingress
  namespace: saas-shortener
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/limit-rps: "50"
    nginx.ingress.kubernetes.io/limit-burst-multiplier: "5"
    nginx.ingress.kubernetes.io/enable-cors: "true"
spec:
  ingressClassName: nginx
  rules:
    - host: shortener.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: saas-shortener-service
                port:
                  number: 80
```

**Annotations 解读**：

| Annotation | 值 | 作用 |
|-----------|-----|------|
| `rewrite-target` | `/` | URL 重写 |
| `ssl-redirect` | `false` | 不强制跳转 HTTPS（开发环境） |
| `limit-rps` | `50` | 限流：每秒最多 50 个请求 |
| `limit-burst-multiplier` | `5` | 允许突发 50×5=250 个请求 |
| `enable-cors` | `true` | 允许跨域请求 |

**完整请求链路**：

```
用户浏览器
    │
    │ https://shortener.example.com/api/shorten
    ▼
DNS 解析 → 云 LB 的公网 IP
    │
    ▼
Ingress Controller (Nginx)
    │ 匹配规则: host=shortener.example.com, path=/
    ▼
Service: saas-shortener-service:80
    │ selector: app=saas-shortener
    │ 负载均衡
    ▼
Pod 1 或 Pod 2 (:8080)
    │
    ▼
Go 应用处理请求 → 返回响应
```

---

## 7. hpa.yaml — 自动扩缩容

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: saas-shortener-hpa
  namespace: saas-shortener
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: saas-shortener              # 扩缩哪个 Deployment
  minReplicas: 2                      # 最少 2 个 Pod
  maxReplicas: 10                     # 最多 10 个 Pod
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70      # CPU > 70% 触发扩容
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80      # 内存 > 80% 触发扩容
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60  # 扩容冷却 60 秒
      policies:
        - type: Pods
          value: 2                    # 每次最多加 2 个
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300 # 缩容冷却 5 分钟
      policies:
        - type: Pods
          value: 1                    # 每次最多减 1 个
          periodSeconds: 120
```

**扩缩容场景模拟**：

```
时间    CPU    Pod数    HPA 动作
──────────────────────────────────────────────
10:00   30%    2       无操作（低于 70%）
10:05   75%    2       触发扩容 → 2+2=4
10:06   60%    4       冷却期内，不操作
10:10   40%    4       触发缩容 → 4-1=3
10:15   35%    3       冷却期内（5分钟），不操作
10:20   30%    3       触发缩容 → 3-1=2
10:25   25%    2       已达 minReplicas，不再缩容
```

---

## 8-11. monitoring/ — 监控配置

### 8. prometheus.yaml

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'saas-shortener'
    static_configs:
      - targets: ['app:8080']
    metrics_path: '/metrics'
    scrape_interval: 10s
```

这是 Docker Compose 本地开发用的静态配置。在 K8S 中用 ServiceMonitor 替代。

### 9. servicemonitor.yaml（K8S 生产环境用）

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: saas-shortener-monitor
  labels:
    release: prometheus                # Prometheus Operator 通过此标签发现
spec:
  selector:
    matchLabels:
      app: saas-shortener              # 匹配 Service 的标签
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
  namespaceSelector:
    matchNames:
      - saas-shortener
```

**ServiceMonitor 的工作流程**：

```
1. 你创建 ServiceMonitor
2. Prometheus Operator 监听到新 ServiceMonitor
3. Operator 自动更新 Prometheus 配置
4. Prometheus 开始从 saas-shortener-service:80/metrics 拉取指标
```

### 10. grafana-datasource.yaml

```yaml
datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    isDefault: true
```

Grafana 启动时自动加载此配置，连接 Prometheus 数据源。

---

## Docker Compose vs K8S 对照表

| 功能 | Docker Compose | Kubernetes |
|------|---------------|------------|
| 配置注入 | `environment:` 直接写 | ConfigMap + Secret |
| 副本管理 | 无（单实例） | Deployment + replicas |
| 自动扩缩容 | 无 | HPA |
| 服务发现 | 服务名 DNS | Service + ClusterIP |
| 对外暴露 | `ports: "8080:8080"` | Ingress |
| 健康检查 | `healthcheck:` | livenessProbe / readinessProbe |
| 负载均衡 | 无 | Service 自动负载均衡 |
| 滚动更新 | 无（需停机） | RollingUpdate 策略 |
| 回滚 | 无 | `kubectl rollout undo` |
| 资源限制 | `deploy.resources` | `resources.requests/limits` |
| 存储 | `volumes:` 命名卷 | PV / PVC |
| 监控 | 手动配置 Prometheus | ServiceMonitor 自动发现 |

---

## 生产部署 Checklist

```
□ 镜像使用具体版本 tag（如 v1.2.3），不用 latest
□ Secret 不提交到 Git，使用 Sealed Secrets 或 External Secrets
□ 数据库密码使用强随机密码
□ 配置 TLS 证书（cert-manager + Let's Encrypt）
□ Ingress 开启 ssl-redirect
□ 设置合理的 resources.requests 和 limits
□ 配置 HPA 确保弹性伸缩
□ 三种探针都已配置（startup / liveness / readiness）
□ 配置 PodDisruptionBudget（保证升级时最少可用 Pod 数）
□ 安装 Metrics Server（HPA 依赖）
□ 安装 Prometheus Operator + Grafana
□ 配置告警规则（CPU/内存/错误率）
```
