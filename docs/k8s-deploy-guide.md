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

> 虚拟机是 4C8G 单台，Minikube 最合适。如果以后想模拟多节点生产环境，可以用 kubeadm。

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
请参考：https://blog.shpym.cn/index.php/archives/83/
```

### 1.2 配置 Docker 镜像加速（关键！影响后续所有镜像拉取速度）

Minikube 启动时要拉取大量 K8S 组件镜像（kube-apiserver、etcd、coredns 等），不配加速会非常慢甚至超时。

```bash
# 配置 Docker 镜像加速器
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me",
    "https://docker.ketches.cn",
    "docker.m.daocloud.io",
    "dockerpull.org",
    "https://slk30g05.mirror.aliyuncs.com"
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

### 1.3 关闭 swap（K8S 要求）

```bash
# 临时关闭
sudo swapoff -a

# 永久关闭（注释掉 swap 行）
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# 验证
free -h
# Swap 行应该全是 0
```

### 1.4 关闭 SELinux

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

### 3.2 预拉取 kicbase 基础镜像

Minikube 使用 Docker 驱动时，会创建一个 Docker 容器来模拟 K8S 节点。这个容器的基础镜像叫 **kicbase**（Kubernetes In Container base），里面预装了 kubelet、kubeadm、容器运行时等 K8S 节点所需的全部组件。

`minikube start` 时会自动从 `gcr.io`（Google Container Registry）拉取 kicbase，但国内无法访问 `gcr.io`。解决方法是从 Docker Hub 上的镜像仓库预拉取，再打上 Minikube 期望的标签：

```bash
# 1. 从 Docker Hub 拉取 kicbase 基础镜像
docker pull kicbase/stable:v0.0.43

# 2. 打上 Minikube 期望的标签
docker tag kicbase/stable:v0.0.43 gcr.io/k8s-minikube/kicbase:v0.0.43

# 3. 确认镜像已就位
docker images | grep kicbase
```

> **版本号说明**：`v0.0.43` 对应 Minikube `v1.33.0`。不同 Minikube 版本需要不同的 kicbase 版本，可通过 `minikube start --dry-run` 或查看 [Minikube Release Notes](https://github.com/kubernetes/minikube/releases) 确认。

### 3.3 预缓存 K8S 二进制文件

`minikube start` 会自动下载 kubeadm、kubelet、kubectl 二进制文件。如果使用了 `--image-mirror-country=cn`，可能因为阿里云 OSS 上缺少对应版本的 sha256 校验文件而报 404 错误。

解决方法：去掉 `--image-mirror-country=cn`，手动预缓存二进制文件：

![image-20260226173157476](k8s-deploy-guide.assets/image-20260226173157476.png)

```bash
# 1. 创建缓存目录（版本号与 --kubernetes-version 一致）
mkdir -p ~/.minikube/cache/linux/amd64/v1.29.15/

# 2. 下载对应版本的二进制文件(下载慢的话可以windows下载好导入)
cd ~/.minikube/cache/linux/amd64/v1.29.15/
curl -L -o kubectl https://dl.k8s.io/release/v1.29.15/bin/linux/amd64/kubectl
curl -L -o kubeadm https://dl.k8s.io/release/v1.29.15/bin/linux/amd64/kubeadm
curl -L -o kubelet https://dl.k8s.io/release/v1.29.15/bin/linux/amd64/kubelet
chmod +x kubeadm kubelet kubectl

# 3. 确认三个文件都在
ls -lh ~/.minikube/cache/linux/amd64/v1.29.15/
```

> 如果 `dl.k8s.io` 下载慢，可使用代理或从 GitHub Mirror 下载。

### 3.4 启动 Minikube 集群

```bash
minikube start \
  --driver=docker \
  --cpus=2 \
  --memory=4096 \
  --image-repository=registry.cn-hangzhou.aliyuncs.com/google_containers \
  --kubernetes-version=v1.29.15 \
  --force \
  --base-image=gcr.io/k8s-minikube/kicbase:v0.0.43
```

| 参数 | 作用 |
|------|------|
| `--driver=docker` | 使用 Docker 作为运行时（不需要 VirtualBox） |
| `--cpus=2` | 分配 2 核 CPU |
| `--memory=4096` | 分配 4GB 内存 |
| `--image-repository=registry...` | 指定阿里云 K8S 镜像仓库（核心提速参数） |
| `--kubernetes-version=v1.29.15` | 指定 K8S 版本，避免拉取 latest 时反复查询 |
| `--force` | 允许以 root 用户运行（学习环境需要） |
| `--base-image=gcr.io/...kicbase:v0.0.43` | 使用 3.2 步骤预拉取的本地 kicbase 镜像，跳过从 gcr.io 下载 |

> `--force` 是因为 Minikube 默认不允许 root 用户使用 Docker 驱动。学习环境直接加 `--force` 即可，生产环境建议创建普通用户运行。

> 配合阿里云镜像仓库 + 预拉取 kicbase 后，首次启动通常 **3-5 分钟**即可完成（不加速可能 30 分钟甚至失败）。

### 3.5 配置代理访问 Docker Hub

如果 Docker 镜像加速器不稳定，或需要拉取 Docker Hub 官方镜像（如 Ingress Controller），可通过代理方案一次性解决所有镜像拉取问题。

#### 为什么需要代理

Minikube 运行在 Docker 容器中，内部有独立的 Docker daemon。即使宿主机 Docker 配了镜像加速，Minikube 内部的 Docker 并不继承这些配置。配置代理后，Minikube 内部可直接拉取 Docker Hub 镜像，无需预拉取或使用镜像站。

#### 方案：SSH 反向隧道 + Minikube 代理

适用场景：Windows 主机上有 Clash 等代理工具，需要将代理能力"穿透"到 Linux 虚拟机及其中的 Minikube。

**第一步：修改虚拟机 SSH 配置**

```bash
# 启用 GatewayPorts，允许非 127.0.0.1 地址访问转发的端口
sed -i 's/#*GatewayPorts.*/GatewayPorts yes/' /etc/ssh/sshd_config
systemctl restart sshd
```

**第二步：从 Windows 建立反向隧道**

![image-20260226172606076](k8s-deploy-guide.assets/image-20260226172606076.png)

```powershell
# 将虚拟机的 7897 端口转发到 Windows 本机的 Clash 代理端口
ssh -R 0.0.0.0:7897:127.0.0.1:7897 root@192.168.3.200
```

**第三步：获取 Minikube 容器的网关 IP**

```bash
# Minikube 容器看到的宿主机 IP（不是 172.17.0.1！）
minikube ssh -- ip route show default
# 输出示例: default via 192.168.49.1 dev eth0
```

> **注意**：Minikube 使用独立网络（`192.168.49.0/24`），网关不是 Docker 默认网桥的 `172.17.0.1`。

**第四步：验证代理连通性**

![image-20260226172850442](k8s-deploy-guide.assets/image-20260226172850442.png)

```bash
ss -tlnp | grep 7897                                     # 确认隧道在监听
curl -x http://192.168.49.1:7897 https://www.google.com  # 测试代理可用
```

**第五步：带代理参数启动 Minikube**

如果已有集群需要先删除再重建：

![image-20260226174420014](k8s-deploy-guide.assets/image-20260226174420014.png)

```bash
minikube delete

minikube start \
  --driver=docker \
  --cpus=2 \
  --memory=4096 \
  --kubernetes-version=v1.29.15 \
  --force \
  --base-image=gcr.io/k8s-minikube/kicbase:v0.0.43 \
  --docker-env=HTTP_PROXY=http://192.168.49.1:7897 \
  --docker-env=HTTPS_PROXY=http://192.168.49.1:7897 \
  --docker-env=NO_PROXY=localhost,127.0.0.1,10.96.0.0/12,192.168.0.0/16
```

| 参数 | 作用 |
|------|------|
| `--docker-env=HTTP_PROXY` | 设置 Minikube 内部 Docker daemon 的 HTTP 代理 |
| `--docker-env=HTTPS_PROXY` | 设置 HTTPS 代理（值仍用 `http://`，指代理协议） |
| `--docker-env=NO_PROXY` | 排除集群内部网段，避免 Pod 间通信走代理 |

#### 注意事项

**HTTPS_PROXY 的值为什么是 `http://` 而不是 `https://`？**

`HTTPS_PROXY` 中的 "HTTPS" 指要代理的**目标流量**是 HTTPS，而不是代理服务器本身使用 HTTPS 协议。

**SSH 隧道断开怎么办？**

隧道会在 SSH 连接断开时失效。如果 `docker pull` 突然报 `connection refused`：

```bash
ss -tlnp | grep 7897  # 检查隧道是否还在
# 没有输出 → 在 Windows 重建隧道
```

**BuildKit 的 FROM 指令不走 Docker daemon 代理**

即使配了代理，`docker build` 的 `FROM` 阶段可能仍然超时。解决方法是在构建前预拉取基础镜像：

```bash
eval $(minikube docker-env)
docker pull golang:1.22-alpine
docker pull alpine:3.19
docker build -t app:latest -f deploy/docker/Dockerfile .
```

> 项目的 `install.sh` 已内置此逻辑，无需手动操作。

### 3.6 验证集群状态

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

#### CoreDNS 崩溃导致 DNS 解析失败

**现象**

应用 Pod 持续 `CrashLoopBackOff`，日志显示数据库连接失败：

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

![image-20260226175734803](k8s-deploy-guide.assets/image-20260226175734803.png)

---

## 四、部署应用

![image-20260226181811686](k8s-deploy-guide.assets/image-20260226181811686.png)

![image-20260226184251600](k8s-deploy-guide.assets/image-20260226184251600.png)

```
Kubernetes:
  make k8s-deploy    - 一键部署到 Minikube（含镜像、数据库、应用）
  make k8s-uninstall - 一键卸载（删除命名空间及所有资源）
  make k8s-apply     - 仅应用 K8s 配置（已有数据库时用）
  make k8s-delete    - 删除 K8s 配置
  make k8s-status    - 查看 K8s 状态
```



### 4.1 验证部署状态

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

### 4.2 测试 API

部署成功了，但 K8S 集群内的服务不会自动暴露到宿主机端口。需要手动建立端口转发才能访问

![image-20260226185237484](k8s-deploy-guide.assets/image-20260226185237484.png)

```
# 方式1：端口转发（推荐）
kubectl port-forward svc/saas-shortener-service 8080:80 -n saas-shortener --address=0.0.0.0 &

# 然后在虚拟机上访问：curl http://localhost:8080
# 或从 Windows 访问：http://192.168.3.200:8080
```

---

## 五、K8S 可视化面板

###  Lens（桌面客户端）

如果你想在 **Windows 主机**上远程管理虚拟机中的 K8S，Lens 是最佳选择。

**安装与连接步骤：**

1. 在 Windows 上下载安装 Lens：https://k8slens.dev/
2. 从虚拟机复制 kubeconfig：

```powershell
scp root@<虚拟机IP>:~/.kube/config C:\Users\你的用户名\.kube\minikube-config
```

3. 建立 SSH 隧道（Minikube API Server 只监听容器内部，需要转发）：

```powershell
# 先查看 Minikube 容器实际暴露的端口（在 Linux 上执行）
# docker port minikube
# 输出示例: 8443/tcp -> 0.0.0.0:32769

# Windows 上建立隧道（端口号替换为上面查到的实际端口）
ssh -L 8443:127.0.0.1:32769 root@<虚拟机IP> -N
```

> 如果 `docker port minikube` 显示 `8443/tcp -> 0.0.0.0:8443`，则隧道命令为：
> `ssh -L 8443:127.0.0.1:8443 root@<虚拟机IP> -N`

4. kubeconfig 中 `server` 保持 `https://127.0.0.1:8443` 不变
5. 打开 Lens → File → Add Cluster → 选择或粘贴 kubeconfig 文件

**如果遇到证书错误**，在 kubeconfig 的 cluster 中添加：

```yaml
clusters:
- cluster:
    certificate-authority-data: LS0tLS1C...
    insecure-skip-tls-verify: true    # 跳过证书验证（仅开发环境）
    server: https://127.0.0.1:8443
  name: minikube
```

Lens 功能：

- 图形化查看所有 K8S 资源（Pod、Service、Deployment 等）
- 实时日志查看
- 一键进入容器终端
- 资源使用率监控（CPU、内存图表）
- 多集群管理

---

## 六、常用运维操作

### 6.1 更新应用版本

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

### 6.2 回滚

```bash
# 回滚到上一个版本
kubectl rollout undo deployment/saas-shortener -n saas-shortener

# 查看历史版本
kubectl rollout history deployment/saas-shortener -n saas-shortener
```

### 6.3 扩缩容

```bash
# 手动扩容到 4 个 Pod
kubectl scale deployment/saas-shortener --replicas=4 -n saas-shortener

# 查看 HPA 自动扩缩容状态
kubectl get hpa -n saas-shortener
```

### 6.4 查看日志和调试

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

### 6.5 Minikube 管理

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

## 七、一键部署与卸载脚本

项目已提供一键部署和一键卸载脚本，在项目根目录执行即可。

### 7.1 一键部署

```bash
# 前置：minikube 已启动 (minikube start)
make k8s-deploy
```

脚本将依次完成：构建镜像 → 创建 Namespace → 部署 PostgreSQL/Redis → 部署应用 → 启用 Ingress/HPA。

### 7.2 一键卸载

```bash
make k8s-uninstall
```

脚本会删除 `saas-shortener` 命名空间及其下所有资源（应用、数据库、Redis、配置等）。卸载前会要求确认。

**免确认强制卸载：**
```bash
K8S_UNINSTALL_FORCE=1 ./deploy/k8s/uninstall.sh
```

