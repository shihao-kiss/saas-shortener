# K8S 部署问题排查手册

> 记录在 CentOS 虚拟机 + Minikube 环境部署 saas-shortener 过程中遇到的所有问题及解决方案。

---

## 目录

- [一、Docker 构建阶段](#一docker-构建阶段)
  - [1.1 Docker Hub 访问超时](#11-docker-hub-访问超时)
  - [1.2 Shell 脚本 CRLF 换行符](#12-shell-脚本-crlf-换行符)
- [二、镜像拉取问题](#二镜像拉取问题)
  - [2.1 Pod 镜像拉取失败（ImagePullBackOff）](#21-pod-镜像拉取失败imagepullbackoff)
  - [2.2 宿主机 Docker vs Minikube Docker](#22-宿主机-docker-vs-minikube-docker)
  - [2.3 Ingress 插件 @sha256 摘要导致拉取失败](#23-ingress-插件-sha256-摘要导致拉取失败)
  - [2.4 BuildKit 不走 Docker daemon 代理](#24-buildkit-不走-docker-daemon-代理)
- [2.5 CoreDNS 崩溃导致 DNS 解析失败](#25-coredns-崩溃导致-dns-解析失败)
- [三、Minikube 代理配置](#三minikube-代理配置)
  - [3.1 为什么需要代理](#31-为什么需要代理)
  - [3.2 SSH 反向隧道方案](#32-ssh-反向隧道方案)
  - [3.3 Minikube 启动时配置代理](#33-minikube-启动时配置代理)
  - [3.4 代理相关的注意事项](#34-代理相关的注意事项)
- [四、Namespace 卡在 Terminating](#四namespace-卡在-terminating)
- [五、常用排查命令速查](#五常用排查命令速查)

---

## 一、Docker 构建阶段

### 1.1 Docker Hub 访问超时

**现象**

```
ERROR: failed to solve: alpine:3.19: failed to resolve source metadata for docker.io/library/alpine:3.19:
dial tcp 199.59.148.106:443: i/o timeout
```

**原因**

国内无法直接访问 Docker Hub（`registry-1.docker.io`）。

**解决方案**

方案 A：Dockerfile 使用 `DOCKER_REGISTRY` 变量，通过 `--build-arg` 切换镜像源：

```dockerfile
ARG DOCKER_REGISTRY=docker.io/library
FROM ${DOCKER_REGISTRY}/golang:1.22-alpine AS builder
```

```bash
# 使用国内镜像源构建
docker build --build-arg DOCKER_REGISTRY=docker.m.daocloud.io -t app:latest .
```

方案 B：配置 Docker daemon 镜像加速（`/etc/docker/daemon.json`）：

```json
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ]
}
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
```

方案 C：为 Minikube 配置代理（推荐，详见[第三节](#三minikube-代理配置)）。

---

### 1.2 Shell 脚本 CRLF 换行符

**现象**

```
deploy/k8s/install.sh: line 8: $'\r': command not found
: invalid optionll.sh: line 9: set: -
```

**原因**

Windows 编辑器保存的 `.sh` 文件使用 CRLF（`\r\n`）换行，Linux 无法识别 `\r`。

**解决方案**

1. 在 Linux 上转换：

```bash
sed -i 's/\r$//' deploy/k8s/install.sh deploy/k8s/uninstall.sh
```

2. 项目根目录添加 `.gitattributes`，永久解决：

```
*.sh text eol=lf
```

3. 已有文件需要重新规范化：

```bash
git add --renormalize .
git commit -m "fix: enforce LF for shell scripts"
```

---

## 二、镜像拉取问题

### 2.1 Pod 镜像拉取失败（ImagePullBackOff）

**现象**

```
Warning  Failed   kubelet  Failed to pull image "postgres:16-alpine":
  Error response from daemon: Get "https://registry-1.docker.io/v2/":
  dial tcp 31.13.91.33:443: i/o timeout
```

Pod 状态显示 `ImagePullBackOff` 或 `ErrImagePull`。

**排查步骤**

```bash
# 查看 Pod 状态
kubectl get pods -n saas-shortener

# 查看失败原因
kubectl describe pod <pod-name> -n saas-shortener

# 查看 Events 部分，确认是镜像拉取问题
```

**解决方案**

Minikube 内部无法访问 Docker Hub，需要配置代理（详见[第三节](#三minikube-代理配置)）。

---

### 2.2 宿主机 Docker vs Minikube Docker

**区分方法**

```bash
# 查看当前使用的 Docker
docker info | grep "Name:"
# Name: minikube → Minikube 内部 Docker
# Name: saas-dev → 宿主机 Docker

# 查看环境变量
echo $DOCKER_HOST
# 空值 → 宿主机 Docker
# tcp://192.168.49.2:2376 → Minikube Docker
```

**切换命令**

```bash
# 切换到 Minikube Docker
eval $(minikube docker-env)

# 切回宿主机 Docker
eval $(minikube docker-env -u)
```

**关键区别**

| 特性 | 宿主机 Docker | Minikube Docker |
|------|--------------|-----------------|
| `registry-mirrors` | 通常已配置 | 未配置 |
| 代理 | 需单独配置 | 通过 `--docker-env` 配置 |
| 构建的镜像 | K8s Pod 看不到 | K8s Pod 可直接使用 |

---

### 2.3 Ingress 插件 @sha256 摘要问题

Minikube Ingress 插件会给镜像引用追加 `@sha256:xxxx` 摘要，这会导致两种不同的失败场景：

#### 场景 A：无代理时 —— 联网验证超时

**现象**

Minikube 启用 Ingress 插件后，admission Job 持续 `ImagePullBackOff`，即使镜像已存在于本地。

```bash
kubectl describe pod ingress-nginx-admission-create-xxx -n ingress-nginx
# Image: kube-webhook-certgen:v1.4.0@sha256:44d1d0e9...
# Failed to pull image: dial tcp xxx:443: i/o timeout
```

**根因**

即使本地已有 `kube-webhook-certgen:v1.4.0`，Docker 遇到 `@sha256:` 摘要引用时仍会联网验证摘要是否匹配，国内环境无法访问远程仓库导致超时。

| 镜像引用方式 | 本地有镜像时的行为 |
|---|---|
| `image:v1.4.0` | 直接使用本地镜像，不联网 |
| `image:v1.4.0@sha256:xxx` | 必须联网验证摘要，失败则拉取失败 |

#### 场景 B：有代理 + `--image-repository` —— 摘要不匹配

**现象**

已配置代理，网络畅通，但仍然 `ImagePullBackOff`，报错为 `manifest unknown`：

```
Failed to pull image "registry.cn-hangzhou.aliyuncs.com/google_containers/kube-webhook-certgen:v1.4.0@sha256:44d1d0e9...":
manifest for ...@sha256:44d1d0e9... not found: manifest unknown
```

**根因**

`@sha256:44d1d0e9...` 摘要来自 Docker Hub 原版镜像，但 `--image-repository` 把 registry 改成了阿里云。阿里云镜像是重新推送的，**摘要不同**，所以找不到匹配的 manifest。

```
Minikube 插件的镜像引用逻辑：
  原始: registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.0@sha256:44d1d0e9...
       ↓ --image-repository 替换 registry
  实际: registry.cn-hangzhou.aliyuncs.com/google_containers/kube-webhook-certgen:v1.4.0@sha256:44d1d0e9...
       ↓ 阿里云镜像的 sha256 与 Docker Hub 不同
  结果: manifest unknown（摘要不匹配）
```

#### 解决方案

**方案 A：有代理时，去掉 `--image-repository`（推荐，根治）**

既然有代理可以直接访问 Docker Hub / registry.k8s.io，不需要阿里云镜像仓库：

```bash
minikube delete

minikube start \
  --driver=docker \
  --cpus=2 \
  --memory=4096 \
  --kubernetes-version=v1.29.15 \
  --force \
  --docker-env=HTTP_PROXY=http://192.168.49.1:7897 \
  --docker-env=HTTPS_PROXY=http://192.168.49.1:7897 \
  --docker-env=NO_PROXY=localhost,127.0.0.1,10.96.0.0/12,192.168.0.0/16
```

这样 `@sha256:` 摘要与 registry 来源一致，不会有不匹配问题。

**方案 B：无代理或保留 `--image-repository` 时，手动去掉 `@sha256`**

```bash
# Deployment 可直接 apply
kubectl get deployment -n ingress-nginx -o json | \
  sed 's/@sha256:[a-f0-9]*//g' | kubectl apply -f -

# Job 不可变，需删除重建并清理自动生成的 selector/uid
kubectl get jobs -n ingress-nginx -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    for key in ['uid', 'resourceVersion', 'creationTimestamp']:
        item['metadata'].pop(key, None)
    item.pop('status', None)
    item['spec'].pop('selector', None)
    labels = item['spec']['template']['metadata'].get('labels', {})
    for key in list(labels):
        if 'controller-uid' in key:
            del labels[key]
    for c in item['spec']['template']['spec'].get('containers', []):
        if '@sha256:' in c.get('image', ''):
            c['image'] = c['image'].split('@')[0]
json.dump(data, sys.stdout)
" > /tmp/jobs-clean.json

kubectl delete jobs --all -n ingress-nginx --force --grace-period=0
kubectl create -f /tmp/jobs-clean.json
```

安装脚本（`deploy/k8s/install.sh`）已内置方案 B 的自动修复逻辑。

---

### 2.4 BuildKit 不走 Docker daemon 代理

**现象**

`docker pull` 正常（走代理），但 `docker build` 的 `FROM` 阶段超时：

```
ERROR: failed to solve: docker.io/library/alpine:3.19:
failed to authorize: failed to fetch anonymous token:
dial tcp 52.58.1.161:443: i/o timeout
```

**根因**

Docker BuildKit 有独立的网络栈：

| 操作 | 代理来源 | 是否走 `--docker-env` 代理 |
|------|---------|--------------------------|
| `docker pull` | Docker daemon | 是 |
| `docker build` → `FROM` | BuildKit | 否 |
| `docker build` → `RUN` | `--build-arg` | 需手动传入 |

**解决方案**

在 `docker build` 前预拉取基础镜像，让 BuildKit 使用本地缓存：

```bash
# docker pull 走 Docker daemon 代理，可以正常拉取
docker pull golang:1.22-alpine
docker pull alpine:3.19

# BuildKit 发现本地已有，不再联网
docker build -t app:latest -f deploy/docker/Dockerfile .
```

安装脚本（`deploy/k8s/install.sh`）已内置此逻辑。

---

### 2.5 CoreDNS 崩溃导致 DNS 解析失败

**现象**

应用 Pod 持续 `CrashLoopBackOff`，日志显示数据库连接失败：

```
failed to connect to `host=postgres-service user=postgres database=saas_shortener`:
hostname resolving error (lookup postgres-service on 10.96.0.10:53: read udp ... connection refused)
```

检查 CoreDNS 发现也在崩溃：

```bash
kubectl get pods -n kube-system | grep coredns
# coredns-xxx   0/1   CrashLoopBackOff

kubectl logs -l k8s-app=kube-dns -n kube-system
# Listen: listen tcp :53: bind: permission denied
```

**根因**

CoreDNS 新版本以非 root 用户运行，缺少 `NET_BIND_SERVICE` Linux 能力，无法绑定 53 端口（特权端口 < 1024）。这是 K8s v1.29+ 的已知兼容性问题。

```
CoreDNS 启动 → 绑定 :53 → permission denied → 崩溃
  ↓
集群 DNS 不可用 → Pod 无法解析 Service 域名 → 应用连不上数据库 → CrashLoopBackOff
```

**解决方案**

需要同时修改多个安全策略字段，使用 JSON patch 精确替换（strategic merge 对数组和布尔值可能不生效）：

```bash
# 1. 修复 capabilities 和权限
kubectl -n kube-system patch deployment coredns --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/securityContext/allowPrivilegeEscalation", "value": true},
  {"op": "replace", "path": "/spec/template/spec/containers/0/securityContext/capabilities/drop", "value": []},
  {"op": "add", "path": "/spec/template/spec/containers/0/securityContext/runAsUser", "value": 0},
  {"op": "add", "path": "/spec/template/spec/containers/0/securityContext/runAsNonRoot", "value": false}
]'

# 2. 等待重启
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=60s

# 3. 验证
kubectl get pods -n kube-system | grep coredns
# 应显示 1/1 Running
```

> **注意**：仅添加 `NET_BIND_SERVICE` 能力不够，还需要 `runAsUser: 0`（以 root 运行）和清除 `drop: ["ALL"]`。原始 securityContext 中 `drop: ALL` 会覆盖 `add`，且非 root 用户即使有该能力也可能因内核限制无法绑定特权端口。

修复 CoreDNS 后，重启应用：

```bash
kubectl rollout restart deployment/saas-shortener -n saas-shortener
```

安装脚本（`deploy/k8s/install.sh`）已在部署前自动检测并修复此问题。

---

## 三、Minikube 代理配置

### 3.1 为什么需要代理

Minikube 运行在 Docker 容器中，内部 Docker daemon 默认无法访问 Docker Hub。配置代理后，所有镜像拉取问题一次性解决，无需预拉取、去 `@sha256` 等 workaround。

### 3.2 SSH 反向隧道方案

适用场景：Windows 主机上有 Clash 等代理工具，虚拟机无法直接访问 Windows（防火墙限制）。

**1. 修改虚拟机 SSH 配置**

```bash
# 启用 GatewayPorts，允许非 127.0.0.1 地址访问转发的端口
sed -i 's/#*GatewayPorts.*/GatewayPorts yes/' /etc/ssh/sshd_config
systemctl restart sshd
```

**2. 从 Windows 建立反向隧道**

```powershell
ssh -R 0.0.0.0:7897:127.0.0.1:7897 root@虚拟机IP
```

- `0.0.0.0:7897`：虚拟机上监听所有接口的 7897 端口
- `127.0.0.1:7897`：转发到 Windows 本机的 Clash 代理端口

**3. 验证隧道**

```bash
# 确认监听所有接口
ss -tlnp | grep 7897
# 应显示 *:7897 或 0.0.0.0:7897

# 获取 Minikube 容器看到的宿主机 IP
minikube ssh -- ip route show default
# 输出: default via 192.168.49.1 dev eth0

# 测试代理连通性
curl -x http://192.168.49.1:7897 https://www.google.com
```

> **注意**：Minikube 容器内的宿主机 IP 不是 `172.17.0.1`（Docker 默认网桥），而是 `192.168.49.1`（Minikube 专用网络）。需通过 `minikube ssh -- ip route show default` 获取。

### 3.3 Minikube 启动时配置代理

```bash
minikube delete

minikube start \
  --driver=docker \
  --cpus=2 \
  --memory=4096 \
  --image-repository=registry.cn-hangzhou.aliyuncs.com/google_containers \
  --kubernetes-version=v1.29.15 \
  --force \
  --docker-env=HTTP_PROXY=http://192.168.49.1:7897 \
  --docker-env=HTTPS_PROXY=http://192.168.49.1:7897 \
  --docker-env=NO_PROXY=localhost,127.0.0.1,10.96.0.0/12,192.168.0.0/16
```

参数说明：

| 参数 | 作用 |
|------|------|
| `--docker-env=HTTP_PROXY` | 设置 Minikube 内部 Docker daemon 的 HTTP 代理 |
| `--docker-env=HTTPS_PROXY` | 设置 HTTPS 代理（值仍用 `http://`，指代理协议，非目标协议） |
| `--docker-env=NO_PROXY` | 排除集群内部网段，避免 Pod 间通信走代理 |
| `--image-repository` | K8s 组件镜像使用阿里云源（与代理无关，加速启动） |

### 3.4 代理相关的注意事项

**HTTPS_PROXY 的值为什么是 `http://` 而不是 `https://`？**

`HTTPS_PROXY` 中的 "HTTPS" 指要代理的**目标流量**是 HTTPS，而不是代理服务器本身使用 HTTPS 协议。Clash 的代理端口是普通 HTTP 代理，所以用 `http://`。

**SSH 隧道断开怎么办？**

SSH 隧道会在连接断开时失效。如果 `docker pull` 突然报 `connection refused`：

```bash
# 检查隧道是否还在
ss -tlnp | grep 7897

# 没有输出则需要在 Windows 重建隧道
ssh -R 0.0.0.0:7897:127.0.0.1:7897 root@虚拟机IP
```

**Docker 网桥网关 IP 不是固定的**

```bash
# 获取实际网关 IP
docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'
```

默认通常是 `172.17.0.1`，但 Minikube 容器使用的是独立网络（`192.168.49.0/24`），需用 `minikube ssh -- ip route show default` 获取。

---

## 四、Namespace 卡在 Terminating

**现象**

```bash
kubectl get namespace saas-shortener
# STATUS: Terminating（持续数分钟不消失）
```

**原因**

Namespace 中有资源的 Finalizer 未完成（如 Pod 的 `terminationGracePeriodSeconds`）。

**解决方案**

```bash
# 1. 先尝试强制删除残留 Pod
kubectl delete pods --all -n saas-shortener --force --grace-period=0

# 2. 如果仍然卡住，清除 Finalizer 强制删除
kubectl get namespace saas-shortener -o json | \
  sed 's/"kubernetes"//' | \
  kubectl replace --raw "/api/v1/namespaces/saas-shortener/finalize" -f -

# 3. 验证
kubectl get namespace saas-shortener
# 应返回 NotFound
```

---

## 五、常用排查命令速查

```bash
# ===== 状态查看 =====
kubectl get pods -n saas-shortener              # Pod 状态
kubectl get all -n saas-shortener               # 所有资源
kubectl describe pod <name> -n saas-shortener   # Pod 详情（含 Events）
kubectl logs <pod-name> -n saas-shortener       # Pod 日志

# ===== Docker 环境 =====
docker info | grep "Name:"                      # 当前 Docker 是宿主机还是 Minikube
eval $(minikube docker-env)                      # 切换到 Minikube Docker
eval $(minikube docker-env -u)                   # 切回宿主机 Docker
minikube image ls                                # 查看 Minikube 中的镜像

# ===== 代理排查 =====
ss -tlnp | grep 7897                            # SSH 隧道是否在监听
minikube ssh -- ip route show default            # Minikube 容器的网关 IP
curl -x http://192.168.49.1:7897 https://google.com  # 测试代理连通

# ===== Ingress 排查 =====
kubectl get pods,jobs -n ingress-nginx           # Ingress 组件状态
kubectl describe pod <name> -n ingress-nginx     # 查看拉取的镜像和错误

# ===== 清理 =====
K8S_UNINSTALL_FORCE=1 make k8s-uninstall        # 一键卸载
minikube addons disable ingress                  # 禁用 Ingress 插件
minikube delete                                  # 删除 Minikube 集群
```
