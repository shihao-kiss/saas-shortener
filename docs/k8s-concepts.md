# Kubernetes 概念入门指南

> 从零开始理解 Kubernetes（K8S）的核心概念，配合大量类比和图解，适合小白入门。
>
> 建议配合 [K8S 项目实战解读](./k8s-project-walkthrough.md) 一起阅读。

---

## 学习路线图

```
第一阶段：理解基础                第二阶段：核心资源              第三阶段：生产级能力
─────────────────              ─────────────────            ─────────────────
1. K8S 是什么                  5. Deployment（部署）          9. Ingress（入口网关）
2. 集群架构（Master/Node）      6. Service（服务发现）         10. HPA（自动扩缩容）
3. Pod（最小单元）              7. ConfigMap（配置）           11. 健康检查（探针）
4. Namespace（命名空间）        8. Secret（密钥）              12. 监控（Prometheus）
   Label & Selector（标签）        Workload（工作负载总览）        存储（PV/PVC）
```

---

## 第一阶段：理解基础

### 1. Kubernetes 是什么

**一句话定义**：Kubernetes 是一个**容器编排平台**，帮你自动管理成百上千个 Docker 容器。

**为什么需要它？**

假设你有一个 Docker 容器化的应用。开发时用 `docker run` 就够了，但到了生产环境：

| 问题 | 手动管理 | Kubernetes |
|------|---------|------------|
| 应用挂了怎么办？ | 人工发现 → 手动重启 | 自动检测 → 自动重启 |
| 流量暴涨怎么办？ | 手动开新服务器 → 手动部署 | 自动扩容到 N 个副本 |
| 发布新版本？ | 停机维护 → 替换 → 启动 | 滚动更新，零停机 |
| 新版本有 bug？ | 手忙脚乱回滚 | 一条命令回滚 |
| 10 台服务器怎么分配？ | 人工规划，容易不均 | 自动调度，合理分配 |

> **类比**：Docker 是"集装箱"（标准化打包），Kubernetes 是"港口调度系统"（管理成千上万个集装箱的装卸、调度、运输）。

---

### 2. 集群架构（Master / Node）

K8S 集群由两种角色的机器组成：

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes 集群                        │
│                                                         │
│  ┌───────────────────────────┐                          │
│  │     Master（控制平面）      │   ← 大脑：做决策         │
│  │                           │                          │
│  │  ┌─────────┐ ┌─────────┐ │                          │
│  │  │API Server│ │Scheduler│ │   API Server: 接收指令    │
│  │  └─────────┘ └─────────┘ │   Scheduler: 决定放哪台   │
│  │  ┌──────────────────────┐ │   Controller: 维持状态    │
│  │  │ Controller Manager   │ │   etcd: 存储所有数据      │
│  │  └──────────────────────┘ │                          │
│  │  ┌─────────┐              │                          │
│  │  │  etcd   │              │                          │
│  │  └─────────┘              │                          │
│  └───────────────────────────┘                          │
│                                                         │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐        │
│  │  Node 1    │  │  Node 2    │  │  Node 3    │  ← 手脚 │
│  │            │  │            │  │            │        │
│  │ ┌──┐ ┌──┐ │  │ ┌──┐ ┌──┐ │  │ ┌──┐       │        │
│  │ │P1│ │P2│ │  │ │P3│ │P4│ │  │ │P5│       │        │
│  │ └──┘ └──┘ │  │ └──┘ └──┘ │  │ └──┘       │        │
│  │  kubelet   │  │  kubelet   │  │  kubelet   │        │
│  └────────────┘  └────────────┘  └────────────┘        │
└─────────────────────────────────────────────────────────┘
```

| 角色 | 类比 | 职责 |
|------|------|------|
| **Master** | 公司总部 | 接收命令、做调度决策、维护集群状态 |
| **Node** | 各地工厂 | 实际运行容器（Pod），汇报状态给 Master |
| **API Server** | 前台接待 | 所有操作的入口，`kubectl` 命令都发给它 |
| **Scheduler** | HR 分配工位 | 决定新 Pod 放在哪个 Node 上运行 |
| **Controller Manager** | 车间主管 | 确保实际状态 = 期望状态（比如确保始终有 2 个副本） |
| **etcd** | 档案室 | 存储集群所有状态数据（分布式键值数据库） |
| **kubelet** | 工厂厂长 | 每个 Node 上的代理，负责管理本机上的 Pod |

### 2.1 资源在哪里运行？Master vs Node 分布

这是初学者最容易困惑的问题：我写的这些 YAML（Namespace、Deployment、Service……）到底跑在哪台机器上？

**关键区分：K8S 资源分为两类**

| 类别 | 说明 | 存在位置 |
|------|------|---------|
| **控制面资源**（定义/规则） | 存储在 etcd 中的"配置描述"，由 Master 上的 Controller 管理 | Master（etcd） |
| **数据面实体**（实际运行的东西） | 真正跑起来的进程/容器 | Node |

> **类比**：Deployment 是"招聘计划书"（存在总部档案室），Pod 是"实际到岗的员工"（在各工厂干活）。计划书本身不占工位，员工才占。

**各资源的分布详解**：

```
┌─────────────────── Master（控制平面） ──────────────────────┐
│                                                            │
│  etcd 中存储的资源定义（YAML 描述 → API 对象）：              │
│                                                            │
│  ┌───────────┐  ┌───────────┐  ┌──────────┐  ┌─────────┐  │
│  │ Namespace │  │Deployment │  │ Service  │  │ Ingress │  │
│  │  (定义)   │  │  (定义)   │  │  (定义)  │  │  (定义) │  │
│  └───────────┘  └───────────┘  └──────────┘  └─────────┘  │
│  ┌───────────┐  ┌───────────┐  ┌──────────┐               │
│  │ ConfigMap │  │  Secret   │  │   HPA    │               │
│  │  (定义)   │  │  (定义)   │  │  (定义)  │               │
│  └───────────┘  └───────────┘  └──────────┘               │
│                                                            │
│  Controller Manager（控制循环，监视并维持期望状态）：           │
│  ├── Deployment Controller → 管理 ReplicaSet / Pod         │
│  ├── Service Controller → 维护 Endpoints 列表              │
│  ├── HPA Controller → 每 15 秒检查指标，调整 replicas       │
│  └── Ingress Controller → ⚠️ 特殊！见下方说明               │
│                                                            │
└────────────────────────────────────────────────────────────┘
                            │
                            │ 调度 Pod 到 Node
                            ▼
┌──── Node 1 ────┐  ┌──── Node 2 ────┐  ┌──── Node 3 ────┐
│                │  │                │  │                │
│  ┌──────────┐  │  │  ┌──────────┐  │  │  ┌──────────┐  │
│  │  Pod A   │  │  │  │  Pod B   │  │  │  │  Pod C   │  │
│  │(应用容器) │  │  │  │(应用容器) │  │  │  │(应用容器) │  │
│  └──────────┘  │  │  └──────────┘  │  │  └──────────┘  │
│                │  │                │  │                │
│  ┌──────────┐  │  │  ┌──────────┐  │  │                │
│  │ Ingress  │  │  │  │ Ingress  │  │  │                │
│  │Controller│  │  │  │Controller│  │  │                │
│  │  (Nginx) │  │  │  │  (Nginx) │  │  │                │
│  └──────────┘  │  │  └──────────┘  │  │                │
│                │  │                │  │                │
│  kube-proxy    │  │  kube-proxy    │  │  kube-proxy    │
│  kubelet       │  │  kubelet       │  │  kubelet       │
└────────────────┘  └────────────────┘  └────────────────┘
```

**逐个资源说明**：

| 资源 | 存在位置 | 跨几个节点 | 说明 |
|------|---------|-----------|------|
| **Namespace** | Master (etcd) | 不占节点 | 纯逻辑概念，只是 etcd 中的一条记录，不消耗任何 Node 资源 |
| **ConfigMap / Secret** | Master (etcd) | 不占节点 | 纯数据存储，Pod 启动时从 etcd 读取注入。本身不运行在任何 Node 上 |
| **Deployment** | Master (etcd) + Controller | 不占节点 | "期望状态描述"存在 etcd，Deployment Controller 在 Master 上运行控制循环 |
| **Pod** | **Node** | 每个 Pod 在 **1 个** Node 上 | 真正运行容器的东西。Scheduler 决定放哪个 Node，一旦调度就固定在那个 Node（除非重建） |
| **Service** | Master (etcd) + 每个 Node 的 kube-proxy | **所有** Node | 定义存在 etcd，但 kube-proxy 在**每个 Node** 上设置 iptables/IPVS 规则实现负载均衡 |
| **Ingress** | Master (etcd) + Ingress Controller Pod | **部分** Node | Ingress 规则存在 etcd，但 Ingress Controller 是实际的 Nginx Pod，运行在 Node 上 |
| **HPA** | Master (etcd) + Controller | 不占节点 | HPA Controller 在 Master 上运行，定期查指标、调整 Deployment 的 replicas |

**三个容易混淆的重点**：

**1. Deployment 不跑在 Node 上，Pod 才跑在 Node 上**

```
你写的 YAML:  Deployment (replicas: 3)     ← 存在 Master 的 etcd 里
                    │
                    │ Deployment Controller 创建
                    ▼
实际运行:     Pod-1 (Node 1)   Pod-2 (Node 2)   Pod-3 (Node 3)
                                                    ↑
                                          Scheduler 自动分散到不同 Node
```

Deployment 本身只是一份"声明书"，真正消耗 CPU/内存的是它创建出来的 Pod。3 个 Pod 可能分散在 3 个不同的 Node 上（Scheduler 会自动做反亲和调度）。

**2. Service 在每个 Node 上都有"代理"**

```
Service 不是一个运行的进程，而是一组网络规则。

每个 Node 上的 kube-proxy 负责维护这些规则：

  Node 1                 Node 2                 Node 3
┌──────────┐         ┌──────────┐         ┌──────────┐
│kube-proxy│         │kube-proxy│         │kube-proxy│
│          │         │          │         │          │
│ iptables:│         │ iptables:│         │ iptables:│
│ svc:80 →│         │ svc:80 →│         │ svc:80 →│
│  Pod1:8080│         │  Pod1:8080│         │  Pod1:8080│
│  Pod2:8080│         │  Pod2:8080│         │  Pod2:8080│
└──────────┘         └──────────┘         └──────────┘

无论请求从哪个 Node 发起，kube-proxy 都能把流量转发到正确的 Pod。
所以 Service 是"到处都在"的。
```

**3. Ingress Controller 是一个实际运行在 Node 上的 Pod**

```
Ingress（YAML 规则）  ≠  Ingress Controller（Nginx Pod）

  Ingress 规则 → 存在 etcd 里（"shortener.example.com → Service A"）
                      │
                      │ 被读取
                      ▼
  Ingress Controller → 是一个 Nginx Pod，运行在 Node 上
                       它读取 Ingress 规则，自动生成 nginx.conf
                       真正接收外部流量并转发
```

Ingress Controller 通常部署为 DaemonSet（每个 Node 一个）或 Deployment（指定节点），是集群中真正监听 80/443 端口的进程。下面详细展开。

**Ingress Controller 的两种部署方式：**

**方式 A：DaemonSet —— 每个 Node 一个**

```
DaemonSet 的特性：保证每个 Node 上都运行恰好 1 个 Pod

┌──── Node 1 ────┐  ┌──── Node 2 ────┐  ┌──── Node 3 ────┐
│                │  │                │  │                │
│  ┌──────────┐  │  │  ┌──────────┐  │  │  ┌──────────┐  │
│  │ Ingress  │  │  │  │ Ingress  │  │  │  │ Ingress  │  │
│  │Controller│  │  │  │Controller│  │  │  │Controller│  │
│  │ (Nginx)  │  │  │  │ (Nginx)  │  │  │  │ (Nginx)  │  │
│  │ :80/:443 │  │  │  │ :80/:443 │  │  │  │ :80/:443 │  │
│  └──────────┘  │  │  └──────────┘  │  │  └──────────┘  │
│                │  │                │  │                │
│  App Pod x2    │  │  App Pod x1    │  │  App Pod x3    │
└────────────────┘  └────────────────┘  └────────────────┘

用户请求可以打到任意 Node 的 80/443 端口，都有 Nginx 在接。
```

- 优点：流量打到任何一台机器都能接住，高可用
- 缺点：Node 多了浪费资源（10 台 Node = 10 个 Nginx）
- 适合：自建机房、裸金属服务器

**方式 B：Deployment —— 只在指定的几个 Node 上**

```
Deployment 的方式：指定副本数，Scheduler 决定放哪几个 Node

┌──── Node 1 ────┐  ┌──── Node 2 ────┐  ┌──── Node 3 ────┐
│                │  │                │  │                │
│  ┌──────────┐  │  │  ┌──────────┐  │  │                │
│  │ Ingress  │  │  │  │ Ingress  │  │  │   没有 Ingress  │
│  │Controller│  │  │  │Controller│  │  │   Controller   │
│  │ (Nginx)  │  │  │  │ (Nginx)  │  │  │                │
│  │ :80/:443 │  │  │  │ :80/:443 │  │  │                │
│  └──────────┘  │  │  └──────────┘  │  │                │
│                │  │                │  │                │
│  App Pod x2    │  │  App Pod x1    │  │  App Pod x3    │
└────────────────┘  └────────────────┘  └────────────────┘
        ↑                  ↑                     ↑
    这两个 Node 前面挂一个云 LB          Node 3 不接外部流量
                                          只跑业务 Pod
```

- 优点：节省资源，只在入口节点部署
- 缺点：需要前面再放一个负载均衡器（云 LB）把流量导到这几个 Node
- 适合：云环境（AWS/阿里云，LB 服务现成的）

**"监听 80/443 端口"是什么意思？**

普通应用 Pod（比如你的 Go 服务）监听的是 `8080` 端口，而且是容器内部的端口，外面无法直接访问。Ingress Controller 不一样——它通过 `hostPort` 或 `hostNetwork` 直接绑定 **Node 物理机**的 80 和 443 端口：

```
外部用户
  │
  │ http://shortener.example.com（默认 80 端口）
  ▼
Node 的物理网卡 :80
  │
  │ hostPort / hostNetwork
  ▼
Ingress Controller Pod (Nginx)
  │
  │ 读取 Ingress 规则，匹配 host + path
  ▼
转发到 Service → Pod :8080
```

整个集群只有 Ingress Controller 在物理机上开了 80/443，所有外部 HTTP 流量都从它这里进来，然后根据 Ingress 规则分发给不同的 Service。

> **类比**：Ingress Controller 就是集群的"大门保安"。DaemonSet 方式 = 每栋楼门口都站一个保安；Deployment 方式 = 只在正门放两个保安，配一个前台（云 LB）引路。不管哪种方式，外面的人（用户请求）都要先过保安（Nginx :80/:443）才能进到里面找人（Service → Pod）。

**一句话总结**：

> YAML 里写的 Namespace、Deployment、Service、Ingress、HPA 都是**存在 Master etcd 中的"描述文件"**。真正消耗资源、跑在 Node 上的只有 **Pod**（应用容器）、**kube-proxy**（Service 的网络规则代理）和 **Ingress Controller**（Nginx 实例）。

---

### 3. Pod（最小调度单元）

**定义**：Pod 是 K8S 中**最小的部署单元**，一个 Pod 包含一个或多个容器。

> **类比**：如果容器（Container）是一个人，那 Pod 就是一间办公室。大多数情况下一间办公室坐一个人，但有时两个密切合作的人会坐在同一间。

```
┌──────── Pod ────────┐
│                      │
│  ┌────────────────┐  │
│  │ Container      │  │   ← 你的 Go 应用
│  │ saas-shortener │  │
│  └────────────────┘  │
│                      │
│  共享网络（同一个 IP） │   ← Pod 内的容器共享 localhost
│  共享存储（同一个卷）  │
└──────────────────────┘
```

**Pod 的特点**：

- 每个 Pod 有自己的 IP 地址
- Pod 内的容器共享网络（可以用 `localhost` 互相访问）
- Pod 是**临时的**（ephemeral）——随时可能被销毁重建，IP 会变
- 你几乎不会直接创建 Pod，而是通过 Deployment 来管理

**为什么 Pod IP 会变？**

```
场景：Node 2 宕机了

之前：Pod（IP: 10.0.2.5）运行在 Node 2
之后：K8S 自动在 Node 3 上新建一个 Pod（IP: 10.0.3.8）

IP 变了！如果其他服务硬编码了 10.0.2.5，就访问不到了
→ 这就是为什么需要 Service（后面会讲）
```

---

### 4. Namespace（命名空间）

**定义**：Namespace 是 K8S 中的**虚拟隔离空间**，用来把集群资源分组管理。

> **类比**：一个 K8S 集群就像一栋办公楼，Namespace 就是不同的楼层。每个楼层（Namespace）有自己的公司（项目），互不干扰。

```
┌──────────── K8S 集群 ────────────┐
│                                   │
│  ┌─ Namespace: saas-shortener ─┐  │   ← 我们的项目
│  │  Deployment, Service, Pod   │  │
│  │  ConfigMap, Secret, HPA     │  │
│  └─────────────────────────────┘  │
│                                   │
│  ┌─ Namespace: payment-system ─┐  │   ← 别的项目
│  │  Deployment, Service, Pod   │  │
│  └─────────────────────────────┘  │
│                                   │
│  ┌─ Namespace: kube-system ────┐  │   ← K8S 系统组件
│  │  CoreDNS, kube-proxy, ...   │  │
│  └─────────────────────────────┘  │
└───────────────────────────────────┘
```

**实际 YAML 示例**（来自本项目）：

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: saas-shortener
  labels:
    app: saas-shortener
    monitoring: enabled
```

**常用命令**：

```bash
# 查看所有 Namespace
kubectl get namespaces

# 查看某个 Namespace 下的所有资源
kubectl get all -n saas-shortener

# 创建 Namespace
kubectl apply -f namespace.yaml
```

**K8S 默认的 Namespace**：

| Namespace | 用途 |
|-----------|------|
| `default` | 不指定 Namespace 时的默认空间 |
| `kube-system` | K8S 系统组件（DNS、代理等） |
| `kube-public` | 公共资源，所有用户可读 |
| `kube-node-lease` | 节点心跳数据 |

---

### 5. Label 与 Selector（标签与选择器）

**定义**：Label 是附加在资源上的**键值对标签**，Selector 是根据标签**筛选资源**的机制。

> **类比**：Label 就像贴在快递包裹上的标签（"易碎"、"加急"、"北京仓"），Selector 就是分拣员根据标签把包裹分到不同传送带。

**这是 K8S 中最核心的关联机制**——Service 怎么找到 Pod？Deployment 怎么管理 Pod？全靠 Label + Selector。

```
                    Label: app=saas-shortener
                    ┌──────────────────────┐
                    │                      │
┌─────────┐        ┌┴──────┐  ┌───────┐  ┌┴──────┐
│ Service │──selector──►Pod 1│  │ Pod 2 │  │ Pod 3 │
│         │        │app=   │  │app=   │  │app=   │
│selector:│        │saas-  │  │saas-  │  │payment│
│ app=    │        │short  │  │short  │  │       │
│ saas-   │        └───────┘  └───────┘  └───────┘
│ shortener│            ↑          ↑          ✗
└─────────┘          匹配！      匹配！     不匹配
```

**实际例子**（本项目中 Label 如何把资源串起来）：

```yaml
# Deployment 给 Pod 打标签
spec:
  template:
    metadata:
      labels:
        app: saas-shortener     # ← Pod 的标签

# Service 通过 selector 找到这些 Pod
spec:
  selector:
    app: saas-shortener         # ← 匹配上面的标签

# HPA 通过 scaleTargetRef 找到 Deployment
spec:
  scaleTargetRef:
    name: saas-shortener        # ← 匹配 Deployment 的名称
```

**完整关联链**：

```
Ingress ──► Service ──selector──► Pod（由 Deployment 管理）
                                    ↑
                                 HPA 自动调整副本数
                                    ↑
                            ConfigMap/Secret 注入配置
```

---

## 第二阶段：核心资源

### 6. Workload（工作负载）总览

**定义**：Workload 是 K8S 中用于**管理 Pod 生命周期**的资源统称。

你不会直接创建 Pod，而是告诉 K8S "我需要什么样的 Pod，需要几个"，由 Workload 资源来帮你管理。

| Workload 类型 | 用途 | 类比 |
|---------------|------|------|
| **Deployment** | 无状态应用（最常用） | 快餐店服务员，谁来都行，可以随时换 |
| **StatefulSet** | 有状态应用（数据库等） | 银行柜台员，每个有固定编号和储物柜 |
| **DaemonSet** | 每个 Node 跑一个 | 每栋楼都有一个保安 |
| **Job** | 一次性任务 | 请了个搬家公司，搬完就走 |
| **CronJob** | 定时任务 | 定时闹钟，每天 3 点清理数据 |

> 本项目的 Go 应用是无状态的（所有状态存在数据库/Redis），所以用 **Deployment**。

---

### 7. Deployment（部署）

**定义**：Deployment 是 K8S 中最常用的 Workload 资源，用于管理无状态应用的 Pod，支持**滚动更新**、**回滚**和**扩缩容**。

> **类比**：Deployment 就像一个部门经理。你告诉它"我需要 3 个员工（Pod），技能要求如下"，它会自动招人、裁人、换人，始终保持 3 人在岗。

**Deployment → ReplicaSet → Pod 的层级关系**：

```
┌─── Deployment ─────────────────────────────────┐
│  "我要 3 个副本，镜像用 v2"                       │
│                                                 │
│  ┌─── ReplicaSet (v2, 当前) ────────────────┐   │
│  │  "维持 3 个 Pod"                          │   │
│  │                                          │   │
│  │  ┌─────┐  ┌─────┐  ┌─────┐              │   │
│  │  │Pod 1│  │Pod 2│  │Pod 3│              │   │
│  │  │ v2  │  │ v2  │  │ v2  │              │   │
│  │  └─────┘  └─────┘  └─────┘              │   │
│  └──────────────────────────────────────────┘   │
│                                                 │
│  ┌─── ReplicaSet (v1, 旧版, 0 副本) ────────┐   │
│  │  保留用于回滚                              │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

- **Deployment** 管理 ReplicaSet（你直接操作它）
- **ReplicaSet** 管理 Pod（你几乎不直接操作它）
- **Pod** 运行容器（你不直接创建它）

**滚动更新过程**（从 v1 升级到 v2）：

```
初始状态：3 个 v1 Pod

第1步：创建 1 个 v2 Pod（maxSurge=1）
  v1 ● ● ●
  v2 ●

第2步：v2 就绪后，终止 1 个 v1
  v1 ● ●
  v2 ● ●

第3步：继续替换
  v1 ●
  v2 ● ● ●

第4步：完成
  v2 ● ● ●

全程用户无感知，零停机！
```

**关键配置字段**：

```yaml
spec:
  replicas: 2                    # 副本数
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0          # 更新时不允许有不可用的 Pod
      maxSurge: 1                # 最多多创建 1 个 Pod
```

| 字段 | 含义 | 本项目设置 |
|------|------|-----------|
| `replicas` | 期望的 Pod 副本数 | 2（配合 HPA 自动调整） |
| `maxUnavailable` | 更新时最多几个 Pod 不可用 | 0（保证零停机） |
| `maxSurge` | 更新时最多多出几个 Pod | 1（临时多一个，逐步替换） |

**常用命令**：

```bash
# 查看 Deployment 状态
kubectl get deployment -n saas-shortener

# 查看滚动更新进度
kubectl rollout status deployment/saas-shortener -n saas-shortener

# 回滚到上一个版本
kubectl rollout undo deployment/saas-shortener -n saas-shortener

# 手动扩容到 5 个副本
kubectl scale deployment/saas-shortener --replicas=5 -n saas-shortener

# 查看历史版本
kubectl rollout history deployment/saas-shortener -n saas-shortener
```

---

### 8. Service（服务发现与负载均衡）

**定义**：Service 为一组 Pod 提供**稳定的访问地址**和**负载均衡**。

> **类比**：Pod 就像公司员工（会离职/入职），Service 就像公司的客服热线（号码不变）。不管背后是谁接电话，你打的号码始终相同。

**为什么需要 Service？**

```
问题：Pod IP 不固定

Pod 被重建 → IP 变了 → 其他服务访问不到

有了 Service：
┌──────────┐     ┌──────────────────────────────┐
│ 其他服务  │────►│ Service (saas-shortener-svc) │
│          │     │ ClusterIP: 10.96.100.1       │
│ 永远访问  │     │ DNS: saas-shortener-svc      │
│ 同一地址  │     └──────┬──────────┬────────────┘
└──────────┘            │          │
                   ┌────▼──┐  ┌───▼───┐
                   │ Pod 1 │  │ Pod 2 │   ← Pod IP 随便变
                   │10.0.1.5│  │10.0.2.8│     Service 帮你兜底
                   └───────┘  └───────┘
```

**Service 的四种类型**：

| 类型 | 作用 | 使用场景 |
|------|------|---------|
| **ClusterIP**（默认） | 只在集群内部可访问 | 微服务间调用（本项目用这个） |
| **NodePort** | 在每个节点上开放端口（30000-32767） | 开发/测试环境临时对外 |
| **LoadBalancer** | 使用云厂商的负载均衡器 | 云上生产环境直接对外 |
| **ExternalName** | 映射到外部 DNS 名称 | 访问集群外部的服务 |

**类型对比图**：

```
                       互联网
                         │
         ┌───────────────┼───────────────┐
         │               │               │
    LoadBalancer      NodePort      ClusterIP
    (云LB公网IP)    (节点IP:30080)   (仅集群内)
         │               │               │
         └───────┬───────┘               │
                 │                       │
            ┌────▼────┐            ┌─────▼────┐
            │ Service │            │ Service  │
            └────┬────┘            └────┬─────┘
                 │                      │
           ┌─────┼─────┐          ┌────┼────┐
           │     │     │          │    │    │
         Pod1  Pod2  Pod3       Pod4  Pod5  Pod6
```

**实际 YAML 示例**（本项目）：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: saas-shortener-service
  namespace: saas-shortener
spec:
  type: ClusterIP
  selector:
    app: saas-shortener         # 通过 Label 找到对应的 Pod
  ports:
    - name: http
      port: 80                  # Service 自身的端口
      targetPort: http          # 转发到 Pod 的端口（8080）
```

**DNS 自动解析**：

在同一个 Namespace 内，可以直接用 Service 名称访问：
```
curl http://saas-shortener-service    → 等价于访问 10.96.100.1:80
```

跨 Namespace 访问需要加上 Namespace：
```
curl http://saas-shortener-service.saas-shortener.svc.cluster.local
```

---

### 9. ConfigMap（配置映射）

**定义**：ConfigMap 用于存储**非敏感配置数据**，以键值对形式存储，可以作为环境变量或文件挂载到 Pod 中。

> **类比**：ConfigMap 就像公司的公告板——上面贴的是公开信息（部门电话、会议室编号），所有人都可以看。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: saas-shortener-config
  namespace: saas-shortener
data:
  APP_ENV: "production"
  SERVER_PORT: "8080"
  DB_HOST: "postgres-service"
  DB_PORT: "5432"
  DB_NAME: "saas_shortener"
  REDIS_ADDR: "redis-service:6379"
```

**注入方式**：

```yaml
# 方式1：整个 ConfigMap 作为环境变量
envFrom:
  - configMapRef:
      name: saas-shortener-config
# Pod 中就能读取: os.Getenv("DB_HOST") → "postgres-service"

# 方式2：挑选特定 key
env:
  - name: DATABASE_HOST
    valueFrom:
      configMapKeyRef:
        name: saas-shortener-config
        key: DB_HOST

# 方式3：挂载为文件
volumes:
  - name: config-volume
    configMap:
      name: saas-shortener-config
# 每个 key 变成一个文件，value 变成文件内容
```

---

### 10. Secret（密钥）

**定义**：Secret 用于存储**敏感信息**（密码、Token、证书等），值需要 Base64 编码。

> **类比**：Secret 就像公司的保险柜——存放重要文件（银行卡密码、合同），只有授权人员能访问。

**ConfigMap vs Secret 对比**：

| 特性 | ConfigMap | Secret |
|------|-----------|--------|
| 存储内容 | 普通配置 | 敏感信息 |
| 编码方式 | 明文 | Base64 编码 |
| 传输加密 | 否 | 是（etcd 中可加密） |
| 使用场景 | 端口号、服务地址 | 密码、API Key、证书 |

**实际 YAML 示例**（本项目）：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: saas-shortener-secret
  namespace: saas-shortener
type: Opaque
data:
  DB_USER: cG9zdGdyZXM=         # echo -n "postgres" | base64
  DB_PASSWORD: cG9zdGdyZXM=     # echo -n "postgres" | base64
```

**Base64 编码/解码**：

```bash
# 编码
echo -n "postgres" | base64
# 输出: cG9zdGdyZXM=

# 解码
echo "cG9zdGdyZXM=" | base64 -d
# 输出: postgres
```

> ⚠️ **注意**：Base64 不是加密！任何人都能解码。Secret 的安全性依赖 K8S 的 RBAC 权限控制和 etcd 加密。生产环境建议使用 External Secrets Operator 或 HashiCorp Vault 管理密钥。

---

## 第三阶段：生产级能力

### 11. Ingress（入口网关）

**定义**：Ingress 是 K8S 中管理集群**外部 HTTP/HTTPS 访问**的资源，工作在七层（应用层），支持域名路由、TLS 终止和路径分发。

> **类比**：如果 Service 是公司内部的分机号，Ingress 就是公司前台——外面的人打电话进来，前台根据"找哪个部门"转接到正确的分机。

**为什么需要 Ingress？**

没有 Ingress 时，每个 Service 要对外暴露都需要一个 LoadBalancer（一个公网 IP），成本高：

```
没有 Ingress（每个服务一个 LB，贵！）：
用户 ──► LB1（$$$）──► Service A
用户 ──► LB2（$$$）──► Service B
用户 ──► LB3（$$$）──► Service C

有 Ingress（一个入口，按域名/路径分发）：
                    ┌──► Service A（api.example.com）
用户 ──► Ingress ──►├──► Service B（app.example.com）
        (1个LB)    └──► Service C（admin.example.com）
```

**工作原理**：

```
互联网
  │
  ▼
┌─────────────────────────────────────────────┐
│         Ingress Controller (Nginx)           │
│                                             │
│  规则1: shortener.example.com → Service A   │
│  规则2: api.example.com/v1   → Service B   │
│  规则3: admin.example.com    → Service C   │
└─────────┬───────────┬───────────┬───────────┘
          │           │           │
     Service A    Service B   Service C
          │           │           │
       Pod Pod     Pod Pod     Pod Pod
```

> **重要**：Ingress 只是路由规则，需要配合 **Ingress Controller**（如 Nginx Ingress Controller）才能工作。Ingress Controller 是真正处理流量的组件。

**实际 YAML 示例**（本项目）：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: saas-shortener-ingress
  namespace: saas-shortener
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "50"       # 限流：每秒最多 50 个请求
    nginx.ingress.kubernetes.io/enable-cors: "true"    # 允许跨域
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
                name: saas-shortener-service   # 转发到哪个 Service
                port:
                  number: 80
```

**backend service**：

在 Ingress 的配置中，`backend.service` 指的是**后端服务**——即 Ingress 把外部请求转发到的目标 Service。上面的例子中，`saas-shortener-service:80` 就是 backend service。

---

### 12. HPA（水平自动扩缩容）

**定义**：HPA（Horizontal Pod Autoscaler）根据 CPU/内存等指标**自动调整 Pod 副本数**。

> **类比**：HPA 就像餐厅经理——午高峰客人多，自动叫更多服务员（扩容）；下午客人少，让多余的服务员下班（缩容）。

**工作流程**：

```
                    ┌──────────────┐
                    │ Metrics      │  ← 采集 Pod 的 CPU/内存
                    │ Server       │
                    └──────┬───────┘
                           │ 上报指标
                    ┌──────▼───────┐
                    │     HPA      │  ← 每 15 秒检查一次
                    │  Controller  │
                    └──────┬───────┘
                           │ 调整 replicas
                    ┌──────▼───────┐
                    │  Deployment  │
                    │ replicas: ?  │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
           ┌──▼──┐     ┌──▼──┐     ┌──▼──┐
           │Pod 1│     │Pod 2│     │Pod 3│  ← 自动增减
           └─────┘     └─────┘     └─────┘
```

**扩缩容计算公式**：

```
期望副本数 = 当前副本数 × (当前指标值 / 目标指标值)

例如：
当前 2 个 Pod，CPU 使用率 90%，目标 70%
期望副本数 = 2 × (90 / 70) = 2.57 → 向上取整 = 3

→ HPA 把 replicas 从 2 调整为 3
```

**实际 YAML 示例**（本项目）：

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: saas-shortener-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: saas-shortener         # 缩放哪个 Deployment
  minReplicas: 2                 # 最少 2 个（保证高可用）
  maxReplicas: 10                # 最多 10 个（控制成本）
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70   # CPU 超过 70% 触发扩容
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60    # 扩容冷却 60 秒
    scaleDown:
      stabilizationWindowSeconds: 300   # 缩容冷却 5 分钟
```

**为什么缩容冷却时间更长？**

- 扩容要快（用户在等），所以冷却 60 秒就够
- 缩容要慢（避免流量波动导致频繁扩缩），所以冷却 5 分钟

```
流量曲线示例：

请求量
 ▲
 │     ╱╲
 │    ╱  ╲    ╱╲
 │   ╱    ╲  ╱  ╲
 │  ╱      ╲╱    ╲
 │ ╱                ╲
 └──────────────────────► 时间

Pod 数变化：
 ▲
 │  ┌──┐
 │  │  │    ┌─┐
 │──┘  │    │ │
 │     └──┐ │ │
 │        └─┘ └───
 └──────────────────────► 时间
   快速扩容  缓慢缩容（避免抖动）
```

**常用命令**：

```bash
# 查看 HPA 状态
kubectl get hpa -n saas-shortener

# 查看 HPA 详细信息（包含当前指标和目标）
kubectl describe hpa saas-shortener-hpa -n saas-shortener
```

---

### 13. 健康检查（Probes）

**定义**：K8S 通过三种探针定期检查 Pod 的健康状态，决定是否重启或移除流量。

| 探针 | 失败后果 | 类比 | 检查什么 |
|------|---------|------|---------|
| **Startup Probe** | 继续等待，不启用其他探针 | 新员工入职培训 | 应用是否已完成启动 |
| **Liveness Probe** | **重启**容器 | 检查员工是否还活着 | 应用是否陷入死锁/卡死 |
| **Readiness Probe** | **摘除流量**（不重启） | 检查员工是否能接客 | 应用是否能处理请求 |

**探针生命周期**：

```
容器启动
   │
   ▼
┌──────────────┐
│ Startup Probe│  ← 等待启动完成（最多 60 秒）
│  /healthz    │     失败：继续等待
└──────┬───────┘     成功：开启下面两个探针
       │
       ▼
┌──────────────┐    ┌───────────────┐
│Liveness Probe│    │Readiness Probe│  ← 同时运行
│  /healthz    │    │  /readyz      │
│              │    │               │
│失败 → 重启   │    │失败 → 摘流量  │
│容器          │    │不接新请求     │
└──────────────┘    └───────────────┘
```

**为什么需要 Readiness 和 Liveness 两个？**

```
场景1：数据库临时断连
  → Readiness 失败，摘除流量（不把请求发给这个 Pod）
  → Liveness 仍然成功（应用没死，只是连不上 DB）
  → 数据库恢复后，Readiness 恢复，重新接收流量
  → 全程没有重启！

场景2：应用死锁，完全卡住
  → Liveness 失败（/healthz 无响应）
  → K8S 重启容器
  → 重启后恢复正常
```

**实际 YAML 示例**（本项目）：

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: http
  initialDelaySeconds: 10     # 启动后 10 秒才开始检查
  periodSeconds: 15            # 每 15 秒检查一次
  failureThreshold: 3          # 连续 3 次失败才重启

readinessProbe:
  httpGet:
    path: /readyz
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 3

startupProbe:
  httpGet:
    path: /healthz
    port: http
  periodSeconds: 5
  failureThreshold: 12         # 最多等 5×12=60 秒
```

---

### 14. 资源管理（Resources）

```yaml
resources:
  requests:
    cpu: "100m"          # 0.1 核
    memory: "128Mi"      # 128MB
  limits:
    cpu: "500m"          # 0.5 核
    memory: "256Mi"      # 256MB
```

**requests vs limits**：

| 配置 | 含义 | 影响 |
|------|------|------|
| `requests` | **最低保障**资源 | Scheduler 依据此值决定调度到哪个 Node |
| `limits` | **最大可用**资源 | 超过 CPU 会被节流（throttle），超过内存会被 OOM Kill |

> **类比**：`requests` 是你租办公室的最低面积要求（"至少 20 平米"），`limits` 是最大可使用面积（"最多 50 平米，超了就赶你走"）。

**CPU 单位**：

| 写法 | 含义 |
|------|------|
| `1` | 1 个 CPU 核心 |
| `500m` | 0.5 核（m = 千分之一核） |
| `100m` | 0.1 核 |

**内存单位**：

| 写法 | 含义 |
|------|------|
| `128Mi` | 128 MiB（1 MiB = 1024² 字节） |
| `1Gi` | 1 GiB |
| `128M` | 128 MB（1 MB = 1000² 字节） |

---

### 15. 监控（Prometheus + Grafana）

在 K8S 中，监控通常使用 **Prometheus + Grafana** 组合：

```
应用 Pod ──/metrics──► Prometheus ──查询──► Grafana
 (暴露指标)           (采集存储)           (可视化展示)
```

**ServiceMonitor（Prometheus Operator 专用）**：

在 K8S 中，用 ServiceMonitor 声明式地告诉 Prometheus "你应该采集哪些服务的指标"：

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: saas-shortener-monitor
spec:
  selector:
    matchLabels:
      app: saas-shortener      # 找到带这个标签的 Service
  endpoints:
    - port: http                # 从这个端口采集
      path: /metrics            # 采集路径
      interval: 15s             # 每 15 秒采集一次
```

> 比手动编辑 Prometheus 配置文件优雅得多——新增服务只需创建一个 ServiceMonitor，Prometheus Operator 自动更新配置。

---

### 16. 存储（PV / PVC）

虽然本项目的 K8S 配置中没有直接使用 PV/PVC（数据库在生产环境用云服务），但这是 K8S 存储的基础概念。

**定义**：

| 概念 | 全称 | 类比 | 说明 |
|------|------|------|------|
| **PV** | PersistentVolume | 实际的硬盘 | 集群管理员创建的存储资源 |
| **PVC** | PersistentVolumeClaim | 申请硬盘的请求单 | 用户声明"我需要 10GB 存储" |
| **StorageClass** | - | 硬盘型号目录 | 定义存储的类型（SSD/HDD/网络盘） |

```
用户（开发者）                   集群（管理员）
     │                              │
     │  "我需要 10GB SSD"            │  "这里有一块 10GB SSD"
     │                              │
  ┌──▼──┐                        ┌──▼──┐
  │ PVC │ ────── 自动绑定 ──────► │ PV  │
  │10GB │                        │10GB │
  │SSD  │                        │SSD  │
  └──┬──┘                        └──┬──┘
     │                              │
     ▼                              ▼
   Pod 挂载使用               实际存储（云盘/NFS/本地盘）
```

---

## 概念关系总图

```
                         互联网用户
                            │
                            ▼
┌─── Namespace: saas-shortener ──────────────────────────────┐
│                                                            │
│  ┌── Ingress ──────────────────────────────────┐           │
│  │  shortener.example.com → Service:80         │           │
│  └─────────────────────┬───────────────────────┘           │
│                        │                                   │
│  ┌── Service ──────────▼───────────────────────┐           │
│  │  ClusterIP, selector: app=saas-shortener    │           │
│  └──────────┬─────────────────┬────────────────┘           │
│             │   负载均衡       │                            │
│        ┌────▼───┐        ┌────▼───┐                        │
│        │ Pod 1  │        │ Pod 2  │   ← Deployment 管理     │
│        │ :8080  │        │ :8080  │   ← HPA 自动扩缩容      │
│        └────────┘        └────────┘                        │
│             │                 │                             │
│        ┌────▼─────────────────▼────┐                       │
│        │  envFrom:                 │                       │
│        │  - ConfigMap (普通配置)    │                       │
│        │  - Secret (敏感信息)       │                       │
│        └───────────────────────────┘                       │
│                                                            │
│  ┌── Prometheus ──► ServiceMonitor ──► Pod /metrics        │
│  └── Grafana ──► 查询 Prometheus 数据                       │
└────────────────────────────────────────────────────────────┘
```

---

## 常用 kubectl 命令速查

```bash
# ==================== 查看资源 ====================
kubectl get pods -n saas-shortener              # 查看 Pod
kubectl get svc -n saas-shortener               # 查看 Service
kubectl get deploy -n saas-shortener            # 查看 Deployment
kubectl get ingress -n saas-shortener           # 查看 Ingress
kubectl get hpa -n saas-shortener               # 查看 HPA
kubectl get all -n saas-shortener               # 查看所有资源

# ==================== 详细信息 ====================
kubectl describe pod <pod-name> -n saas-shortener
kubectl describe deploy saas-shortener -n saas-shortener

# ==================== 日志 ====================
kubectl logs <pod-name> -n saas-shortener       # 查看日志
kubectl logs -f <pod-name> -n saas-shortener    # 实时跟踪日志

# ==================== 调试 ====================
kubectl exec -it <pod-name> -n saas-shortener -- /bin/sh   # 进入容器

# ==================== 部署 ====================
kubectl apply -f deploy/k8s/                    # 应用所有配置
kubectl delete -f deploy/k8s/                   # 删除所有资源

# ==================== 回滚 ====================
kubectl rollout undo deployment/saas-shortener -n saas-shortener
kubectl rollout history deployment/saas-shortener -n saas-shortener
```

---

## 名词速查表

| 名词 | 英文 | 一句话定义 |
|------|------|-----------|
| 集群 | Cluster | 一组运行 K8S 的机器 |
| 节点 | Node | 集群中的一台机器 |
| Pod | Pod | 最小部署单元，包含一个或多个容器 |
| 命名空间 | Namespace | 虚拟隔离空间，资源分组 |
| 标签 | Label | 附加在资源上的键值对 |
| 选择器 | Selector | 根据标签筛选资源 |
| 部署 | Deployment | 管理无状态应用的 Pod，支持滚动更新 |
| 副本集 | ReplicaSet | 维持指定数量的 Pod 副本 |
| 服务 | Service | 为 Pod 提供稳定访问地址和负载均衡 |
| 入口 | Ingress | 集群对外暴露 HTTP 服务的统一入口 |
| 配置映射 | ConfigMap | 存储非敏感配置 |
| 密钥 | Secret | 存储敏感信息（密码等） |
| 水平扩缩容 | HPA | 根据负载自动调整 Pod 数量 |
| 工作负载 | Workload | 管理 Pod 生命周期的资源统称 |
| 后端服务 | Backend Service | Ingress 转发请求的目标 Service |
| 探针 | Probe | 定期检查 Pod 健康状态的机制 |
| 持久卷 | PV / PVC | 持久化存储资源和申请 |
| 服务监控 | ServiceMonitor | 告诉 Prometheus 采集哪些服务的指标 |
