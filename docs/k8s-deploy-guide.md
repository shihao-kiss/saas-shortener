# 虚拟机 Kubernetes 部署指南

> 目标：在 CentOS 7 虚拟机（4C8G）上安装 K8S 单节点集群，部署本项目，并通过 Dashboard 可视化管理。
>
> 方案选择：使用 **Minikube**（单节点 K8S），适合学习和开发环境。

---

## 方案选型

在虚拟机上搭建 K8S 有多种方式：

| 方案 | 节点数 | 难度 | 资源占用 | 适合场景 |
|------|--------|------|---------|---------|
| **Minikube** | 单节点 | ⭐ 简单 | ~2GB 内存 | **学习入门（推荐）** |
| **k3s** | 单/多节点 | ⭐⭐ 简单 | ~512MB 内存 | 轻量级生产/边缘计算 |
| **kubeadm** | 多节点 | ⭐⭐⭐ 较难 | 每节点 ~2GB | 正式生产环境 |
| **Kind** | 单节点 | ⭐ 简单 | ~2GB 内存 | CI/CD 测试 |

> 你的虚拟机是 4C8G 单台，Minikube 最合适。如果以后想模拟多节点生产环境，可以再学 kubeadm。

---

## 一、前置准备

### 1.1 确认 Docker 已安装

Minikube 需要容器运行时，你的虚拟机上应该已经有 Docker：

```bash
docker --version
# Docker version 24.x.x 或更高
```

如果没有，先安装 Docker：

```bash
# 安装 Docker
curl -fsSL https://get.docker.com | sh

# 启动并设置开机自启
sudo systemctl start docker
sudo systemctl enable docker

# 将当前用户加入 docker 组（免 sudo）
sudo usermod -aG docker $USER
newgrp docker
```

### 1.2 关闭 swap（K8S 要求）

```bash
# 临时关闭
sudo swapoff -a

# 永久关闭（注释掉 swap 行）
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# 验证
free -h
# Swap 行应该全是 0
```

### 1.3 关闭 SELinux

```bash
# 临时关闭
sudo setenforce 0

# 永久关闭
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
```

---

## 二、安装 kubectl（K8S 命令行工具）

`kubectl` 是操作 K8S 集群的命令行工具，所有操作都通过它完成。

**方式1：使用 yum 安装（CentOS 推荐，最简单）**

```bash
# 添加阿里云 Kubernetes yum 源
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.29/rpm/repodata/repomd.xml.key
EOF

# 安装
sudo yum install -y kubectl

# 验证
kubectl version --client
```

---

## 三、安装 Minikube

### 3.1 下载安装 Minikube

**使用国内镜像下载（推荐）：**

```bash
# 方式1：通过 npmmirror（阿里前端镜像站，速度快）
curl -LO https://registry.npmmirror.com/-/binary/minikube/v1.33.0/minikube-linux-amd64

# 方式2：通过 GitHub 代理加速
curl -LO https://ghfast.top/https://github.com/kubernetes/minikube/releases/download/v1.33.0/minikube-linux-amd64

# 安装
chmod +x minikube-linux-amd64
sudo mv minikube-linux-amd64 /usr/local/bin/minikube

# 验证
minikube version
```

### 3.2 配置 Docker 镜像加速（关键！影响后续所有镜像拉取速度）

Minikube 启动时要拉取大量 K8S 组件镜像（kube-apiserver、etcd、coredns 等），不配加速会非常慢甚至超时。

```bash
# 配置 Docker 镜像加速器
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me",
    "https://docker.ketches.cn"
  ],
  "dns": ["223.5.5.5", "114.114.114.114"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# 重启 Docker 使配置生效
sudo systemctl daemon-reload
sudo systemctl restart docker

# 验证加速器是否生效
docker info | grep -A 5 "Registry Mirrors"
```

> ⚠️ 镜像加速器地址可能失效，如遇到拉取超时，搜索"docker 镜像加速 2026"获取最新可用地址。

### 3.3 启动 Minikube 集群

```bash
# 使用 Docker 驱动 + 阿里云 K8S 镜像源启动
# 1. 从 Docker Hub 拉取 kicbase 基础镜像
docker pull kicbase/stable:v0.0.43

# 2. 打上 Minikube 期望的标签
docker tag kicbase/stable:v0.0.43 gcr.io/k8s-minikube/kicbase:v0.0.43

# 3. 确认镜像已就位
docker images | grep kicbase


---------------------------
问题：
问题出在 --image-mirror-country=cn 这个参数——它把 K8S 二进制文件（kubeadm/kubelet）的下载也指向了阿里云 OSS，但那个 OSS 上缺少 v1.29.0 的 sha256 校验文件，所以 404 了。
解决方案：去掉 --image-mirror-country=cn，手动预缓存二进制文件。

# 1. 创建新版本的缓存目录
mkdir -p ~/.minikube/cache/linux/amd64/v1.29.15/

# 2. 把已有的文件移过去
mv ~/.minikube/cache/linux/amd64/v1.29.0/* ~/.minikube/cache/linux/amd64/v1.29.15/

# 3. 用匹配版本的 kubectl 替换
cp /usr/bin/kubectl ~/.minikube/cache/linux/amd64/v1.29.15/kubectl

# 4. kubeadm 和 kubelet 版本不匹配，需要重新下载 v1.29.15
cd ~/.minikube/cache/linux/amd64/v1.29.15/
curl -L -o kubectl https://dl.k8s.io/release/v1.29.15/bin/linux/amd64/kubectl
curl -L -o kubeadm https://dl.k8s.io/release/v1.29.15/bin/linux/amd64/kubeadm
curl -L -o kubelet https://dl.k8s.io/release/v1.29.15/bin/linux/amd64/kubelet
chmod +x kubeadm kubelet kubectl

# 5. 确认三个文件都在
ls -lh ~/.minikube/cache/linux/amd64/v1.29.15/
---------------------------

# 4. 重新启动（加 --base-image 指定使用本地镜像）
minikube start \
  --driver=docker \
  --cpus=2 \
  --memory=4096 \
  --image-repository=registry.cn-hangzhou.aliyuncs.com/google_containers \
  --kubernetes-version=v1.29.15 \
  --force \
  --base-image=gcr.io/k8s-minikube/kicbase:v0.0.43

# 参数说明：
# --driver=docker                 使用 Docker 作为运行时（不需要 VirtualBox）
# --cpus=2                        分配 2 核 CPU
# --memory=4096                   分配 4GB 内存
# --image-mirror-country=cn       使用国内镜像加速
# --image-repository=registry...  指定阿里云 K8S 镜像仓库（核心提速参数！）
# --kubernetes-version=v1.29.0    指定版本，避免拉取 latest 时反复查询
# --force                         允许以 root 用户运行（虚拟机学习环境需要）
```

> ⚠️ `--force` 是因为 Minikube 默认不允许 root 用户使用 docker 驱动。学习环境直接加 `--force` 即可。生产环境建议创建普通用户运行。

> 配合阿里云镜像仓库后，首次启动通常 **3-5 分钟**即可完成（不加速可能 30 分钟甚至失败）。

### 提速效果对比

| 步骤 | 不加速 | 加速后 |
|------|--------|--------|
| 下载 kubectl | 10-30 分钟或超时 | **几秒** |
| 下载 Minikube | 10-30 分钟或超时 | **几秒** |
| `minikube start` 拉取镜像 | 30+ 分钟或失败 | **3-5 分钟** |
| 后续 `docker pull` | 龟速 | 正常速度 |

### 3.3 验证集群状态

```bash
# 查看集群状态
minikube status

# 期望输出：
# minikube
# type: Control Plane
# host: Running
# kubelet: Running
# apiserver: Running
# kubeconfig: Configured

# 查看节点
kubectl get nodes

# 期望输出：
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   1m    v1.29.x

# 查看系统 Pod
kubectl get pods -n kube-system
```

---

## 四、构建应用镜像

Minikube 有自己的 Docker 环境，需要把镜像构建到 Minikube 内部：

```bash
# 将当前 shell 的 Docker 指向 Minikube 内部的 Docker
eval $(minikube docker-env)

# 确认已切换（注意看 DOCKER_HOST）
docker info | grep "Name:"

# 在项目根目录构建镜像
cd /path/to/saas-shortener
docker build -t saas-shortener:latest -f deploy/docker/Dockerfile .

# 验证镜像已构建
docker images | grep saas-shortener
```

> ⚠️ 每次打开新终端都需要重新执行 `eval $(minikube docker-env)`，否则镜像会构建到宿主机 Docker 中，Minikube 内找不到。

---

## 五、部署前准备 — 数据库和 Redis

K8S 配置文件中 `DB_HOST=postgres-service`、`REDIS_ADDR=redis-service:6379`，说明需要在集群内部署 PostgreSQL 和 Redis。

### 5.1 快速部署 PostgreSQL

```bash
# 创建命名空间（先执行，后面所有资源都在这个 Namespace 下）
kubectl apply -f deploy/k8s/namespace.yaml

# 部署 PostgreSQL
kubectl -n saas-shortener run postgres \
  --image=postgres:16-alpine \
  --env="POSTGRES_USER=postgres" \
  --env="POSTGRES_PASSWORD=postgres" \
  --env="POSTGRES_DB=saas_shortener" \
  --port=5432

# 为 PostgreSQL 创建 Service
kubectl -n saas-shortener expose pod postgres \
  --name=postgres-service \
  --port=5432 \
  --target-port=5432

# 验证
kubectl get pods,svc -n saas-shortener
```

### 5.2 快速部署 Redis

```bash
# 部署 Redis
kubectl -n saas-shortener run redis \
  --image=redis:7-alpine \
  --port=6379

# 为 Redis 创建 Service
kubectl -n saas-shortener expose pod redis \
  --name=redis-service \
  --port=6379 \
  --target-port=6379

# 验证
kubectl get pods,svc -n saas-shortener
```

---

## 六、部署应用服务

### 6.1 按顺序应用 K8S 配置

```bash
# 1. 命名空间（已在上一步创建）
kubectl apply -f deploy/k8s/namespace.yaml

# 2. 配置和密钥
kubectl apply -f deploy/k8s/configmap.yaml
kubectl apply -f deploy/k8s/secret.yaml

# 3. 部署应用
kubectl apply -f deploy/k8s/deployment.yaml

# 4. 创建 Service
kubectl apply -f deploy/k8s/service.yaml

# 5. 创建 Ingress（可选，Minikube 需要先启用插件）
minikube addons enable ingress
kubectl apply -f deploy/k8s/ingress.yaml

# 6. 自动扩缩容（可选，需要先启用 metrics-server）
minikube addons enable metrics-server
kubectl apply -f deploy/k8s/hpa.yaml
```

### 6.2 验证部署状态

```bash
# 查看所有资源
kubectl get all -n saas-shortener

# 查看 Pod 状态（等待 STATUS 变为 Running）
kubectl get pods -n saas-shortener -w

# 期望输出：
# NAME                              READY   STATUS    RESTARTS   AGE
# saas-shortener-xxxx-yyyy          1/1     Running   0          30s
# saas-shortener-xxxx-zzzz          1/1     Running   0          30s
# postgres                          1/1     Running   0          5m
# redis                             1/1     Running   0          5m

# 查看 Pod 日志
kubectl logs -f deployment/saas-shortener -n saas-shortener

# 如果 Pod 状态异常，查看详细信息
kubectl describe pod <pod-name> -n saas-shortener
```

### 6.3 访问服务

```bash
# 方式1：通过 minikube service 直接打开（最简单）
minikube service saas-shortener-service -n saas-shortener

# 方式2：端口转发到本地（推荐调试用）
kubectl port-forward svc/saas-shortener-service 8080:80 -n saas-shortener
# 然后访问 http://localhost:8080

# 方式3：通过 Ingress 访问（需要配置 hosts）
echo "$(minikube ip) shortener.example.com" | sudo tee -a /etc/hosts
# 然后访问 http://shortener.example.com
```

### 6.4 测试 API

```bash
# 健康检查
curl http://localhost:8080/healthz

# 创建租户
curl -X POST http://localhost:8080/api/v1/tenants \
  -H "Content-Type: application/json" \
  -d '{"name": "test-company", "email": "test@example.com", "plan": "free"}'
```

---

## 七、K8S 可视化面板

K8S 有多种可视化工具可以查看 Pod、Namespace、Service 等资源：

### 7.1 Kubernetes Dashboard（官方）

这是 K8S 官方提供的 Web UI，Minikube 内置支持：

```bash
# 一键启用并打开 Dashboard
minikube dashboard
```

这会自动打开浏览器，你可以看到：

```
┌─────────────────────────────────────────────────────────┐
│              Kubernetes Dashboard                        │
│                                                         │
│  左侧菜单：                                              │
│  ├── Cluster                                            │
│  │   ├── Namespaces          ← 查看所有命名空间           │
│  │   └── Nodes               ← 查看节点状态              │
│  ├── Workloads                                          │
│  │   ├── Deployments         ← 查看部署                  │
│  │   ├── Pods                ← 查看所有 Pod 状态          │
│  │   └── Replica Sets        ← 查看副本集                │
│  ├── Service                                            │
│  │   ├── Services            ← 查看 Service              │
│  │   └── Ingresses           ← 查看 Ingress              │
│  └── Config                                             │
│      ├── Config Maps         ← 查看 ConfigMap            │
│      └── Secrets             ← 查看 Secret               │
│                                                         │
│  功能：查看日志、进入容器终端、编辑 YAML、扩缩容等          │
└─────────────────────────────────────────────────────────┘
```

> 如果用 SSH 远程连接虚拟机，Dashboard 无法直接打开浏览器，需要用代理方式：
> ```bash
> # 启动 Dashboard（后台运行）
> minikube dashboard --url &
> # 输出类似：http://127.0.0.1:43210/api/v1/namespaces/kubernetes-dashboard/...
>
> # 用 kubectl proxy 使其可远程访问
> kubectl proxy --address='0.0.0.0' --accept-hosts='.*'
> # 然后在 Windows 浏览器访问：
> # http://<虚拟机IP>:8001/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/
> ```

### 7.2 K9s（终端 UI，强烈推荐）

K9s 是一个**终端内的 K8S 管理界面**，不需要浏览器，SSH 连上就能用，非常适合虚拟机环境：

```bash
# 安装 K9s
curl -sS https://webinstall.dev/k9s | bash

# 或手动下载
curl -LO https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz
tar -xzf k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/local/bin/

# 启动
k9s
```

K9s 界面：

```
┌─────────────────────────────────────────────────────────────┐
│ K9s - Kubernetes CLI Dashboard                              │
│                                                             │
│ Context: minikube    Cluster: minikube    Namespace: all     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  NAMESPACE          NAME                    READY  STATUS   │
│  saas-shortener     saas-shortener-abc123   1/1    Running  │
│  saas-shortener     saas-shortener-def456   1/1    Running  │
│  saas-shortener     postgres                1/1    Running  │
│  saas-shortener     redis                   1/1    Running  │
│  kube-system        coredns-xxx             1/1    Running  │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ 快捷键:                                                     │
│  :pod      查看 Pod          :svc     查看 Service           │
│  :deploy   查看 Deployment   :ns      查看 Namespace         │
│  :hpa      查看 HPA          :ing     查看 Ingress           │
│  l         查看日志           s        进入容器 Shell          │
│  d         描述资源           e        编辑 YAML              │
│  ctrl+d    删除资源           /        搜索过滤               │
│  :q        退出                                              │
└─────────────────────────────────────────────────────────────┘
```

> K9s 是运维利器——纯键盘操作，比 Dashboard 快得多，强烈推荐日常使用。

### 7.3 Lens（桌面客户端）

如果你想在 **Windows 主机**上远程管理虚拟机中的 K8S，Lens 是最佳选择：

```
安装步骤：
1. 在 Windows 上下载 Lens：https://k8slens.dev/
2. 从虚拟机复制 kubeconfig 文件：
   scp root@<虚拟机IP>:~/.kube/config C:\Users\你的用户名\.kube\config
3. 修改 config 中的 server 地址为虚拟机 IP
4. 打开 Lens，自动检测集群
```

Lens 功能：

- 图形化查看所有 K8S 资源（Pod、Service、Deployment 等）
- 实时日志查看
- 一键进入容器终端
- 资源使用率监控（CPU、内存图表）
- 多集群管理

### 7.4 三种工具对比

| 工具 | 类型 | 安装位置 | 适合场景 |
|------|------|---------|---------|
| **Dashboard** | Web UI | 集群内 | 浏览器操作，简单直观 |
| **K9s** | 终端 UI | 虚拟机上 | **SSH 远程管理，日常运维推荐** |
| **Lens** | 桌面客户端 | Windows 主机上 | 图形化远程管理，功能最全 |

---

## 八、常用运维操作

### 8.1 更新应用版本

```bash
# 1. 重新构建镜像
eval $(minikube docker-env)
docker build -t saas-shortener:v2 -f deploy/docker/Dockerfile .

# 2. 更新 Deployment 的镜像
kubectl set image deployment/saas-shortener \
  saas-shortener=saas-shortener:v2 \
  -n saas-shortener

# 3. 查看滚动更新进度
kubectl rollout status deployment/saas-shortener -n saas-shortener
```

### 8.2 回滚

```bash
# 回滚到上一个版本
kubectl rollout undo deployment/saas-shortener -n saas-shortener

# 查看历史版本
kubectl rollout history deployment/saas-shortener -n saas-shortener
```

### 8.3 扩缩容

```bash
# 手动扩容到 4 个 Pod
kubectl scale deployment/saas-shortener --replicas=4 -n saas-shortener

# 查看 HPA 自动扩缩容状态
kubectl get hpa -n saas-shortener
```

### 8.4 查看日志和调试

```bash
# 查看 Pod 日志
kubectl logs -f <pod-name> -n saas-shortener

# 进入 Pod 容器
kubectl exec -it <pod-name> -n saas-shortener -- /bin/sh

# 查看 Pod 事件（排查启动失败）
kubectl describe pod <pod-name> -n saas-shortener

# 查看所有事件
kubectl get events -n saas-shortener --sort-by='.lastTimestamp'
```

### 8.5 Minikube 管理

```bash
# 停止集群（保留数据）
minikube stop

# 启动集群
minikube start

# 删除集群（清除所有数据！）
minikube delete

# 查看 Minikube IP
minikube ip

# 查看已启用的插件
minikube addons list
```

---

## 九、完整部署一键脚本

```bash
#!/bin/bash
# deploy.sh - 一键部署脚本

set -e

echo "=== 1. 切换到 Minikube Docker 环境 ==="
eval $(minikube docker-env)

echo "=== 2. 构建应用镜像 ==="
docker build -t saas-shortener:latest -f deploy/docker/Dockerfile .

echo "=== 3. 创建 Namespace ==="
kubectl apply -f deploy/k8s/namespace.yaml

echo "=== 4. 部署 PostgreSQL ==="
kubectl -n saas-shortener run postgres \
  --image=postgres:16-alpine \
  --env="POSTGRES_USER=postgres" \
  --env="POSTGRES_PASSWORD=postgres" \
  --env="POSTGRES_DB=saas_shortener" \
  --port=5432 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n saas-shortener expose pod postgres \
  --name=postgres-service --port=5432 --target-port=5432 \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== 5. 部署 Redis ==="
kubectl -n saas-shortener run redis \
  --image=redis:7-alpine --port=6379 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n saas-shortener expose pod redis \
  --name=redis-service --port=6379 --target-port=6379 \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== 6. 等待数据库就绪 ==="
kubectl wait --for=condition=Ready pod/postgres -n saas-shortener --timeout=60s
kubectl wait --for=condition=Ready pod/redis -n saas-shortener --timeout=60s

echo "=== 7. 部署应用 ==="
kubectl apply -f deploy/k8s/configmap.yaml
kubectl apply -f deploy/k8s/secret.yaml
kubectl apply -f deploy/k8s/deployment.yaml
kubectl apply -f deploy/k8s/service.yaml

echo "=== 8. 启用插件 ==="
minikube addons enable ingress 2>/dev/null || true
minikube addons enable metrics-server 2>/dev/null || true
kubectl apply -f deploy/k8s/ingress.yaml
kubectl apply -f deploy/k8s/hpa.yaml

echo "=== 9. 等待应用就绪 ==="
kubectl wait --for=condition=Ready pods -l app=saas-shortener \
  -n saas-shortener --timeout=120s

echo ""
echo "=== 部署完成！==="
echo ""
kubectl get all -n saas-shortener
echo ""
echo "访问方式："
echo "  kubectl port-forward svc/saas-shortener-service 8080:80 -n saas-shortener"
echo "  然后访问: http://localhost:8080/healthz"
```

---

## 常见问题

### Q1: Pod 一直处于 ImagePullBackOff 状态

```bash
# 原因：Minikube 内找不到镜像
# 解决：确保在 Minikube Docker 环境中构建镜像
eval $(minikube docker-env)
docker build -t saas-shortener:latest -f deploy/docker/Dockerfile .

# 确认 Deployment 中 imagePullPolicy 是 IfNotPresent（不是 Always）
```

### Q2: Pod 一直处于 CrashLoopBackOff 状态

```bash
# 查看日志找原因
kubectl logs <pod-name> -n saas-shortener

# 常见原因：数据库连不上
# 检查 PostgreSQL 和 Redis 是否 Running
kubectl get pods -n saas-shortener
```

### Q3: Minikube start 失败

```bash
# 清理后重试
minikube delete
minikube start --driver=docker --cpus=2 --memory=4096 --image-mirror-country=cn
```

### Q4: kubectl 命令返回 "connection refused"

```bash
# Minikube 可能没有启动
minikube status

# 如果 stopped，重新启动
minikube start
```

### Q5: Dashboard 远程访问不了

```bash
# 使用 kubectl proxy 暴露
kubectl proxy --address='0.0.0.0' --accept-hosts='.*' &

# 确保虚拟机防火墙放行 8001 端口
sudo firewall-cmd --add-port=8001/tcp --permanent
sudo firewall-cmd --reload
```
