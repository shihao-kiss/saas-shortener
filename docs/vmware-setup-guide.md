# VMware 虚拟机搭建指南（CentOS 7）

> 目标：在 Windows 上用 VMware 虚拟一台 4C8G 的 CentOS 7，用于部署本项目。
>
> 镜像：`CentOS-7-x86_64-Minimal-2009.iso`

### ⚠️ 关于 CentOS 7 的说明

CentOS 7 已于 **2024 年 6 月 30 日**停止官方维护（EOL）。这意味着：
- 官方 yum 源已不再更新，需要切换到归档镜像源
- 内核版本较老（3.10），但跑 Docker 没有问题
- 作为学习环境完全够用，生产环境建议考虑 Rocky Linux 9 / AlmaLinux 9

---

## 一、准备工作

### 1.1 下载 VMware Workstation Pro

VMware Workstation Pro 从 2024 年 5 月起对个人用户免费。

- 下载地址：https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware+Workstation+Pro
- 注册 Broadcom 账号 → 下载最新版（17.x）→ 安装时选择"用于个人用途"

安装完成后重启电脑。

### 1.2 准备 CentOS 7 镜像

你已经有了 `CentOS-7-x86_64-Minimal-2009.iso`，确认文件路径即可。

> Minimal 版没有图形界面，资源占用小，和真实的云服务器环境一致。

---

## 二、创建虚拟机

### 2.1 新建虚拟机

1. 打开 VMware Workstation → **文件 → 新建虚拟机**
2. 选择 **自定义（高级）** → 下一步
3. 硬件兼容性：保持默认 → 下一步
4. 安装来源：选择 **稍后安装操作系统** → 下一步
5. 操作系统：
   - 客户机操作系统：**Linux**
   - 版本：**CentOS 7 64 位**
   → 下一步
6. 虚拟机名称：
   - 名称：`saas-dev`
   - 位置：选一个磁盘空间充裕的目录（如 `D:\VMs\saas-dev`）
   → 下一步

### 2.2 配置硬件资源

按以下参数逐步配置：

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| **处理器** | 2 个处理器 × 2 核 = **4 核** | 处理器数量 2，每个处理器核心数 2 |
| **内存** | **8192 MB (8GB)** | 拖动滑块到 8GB |
| **网络** | **NAT** | 虚拟机通过宿主机上网，最简单 |
| **I/O 控制器** | LSI Logic（默认） | 保持默认 |
| **磁盘类型** | SCSI（默认） | 保持默认 |
| **磁盘** | **创建新虚拟磁盘** | |
| **磁盘大小** | **60 GB** | 勾选"将虚拟磁盘拆分成多个文件" |

7. 最后一步点击 **完成**

### 2.3 挂载 ISO 镜像

1. 在虚拟机列表中右键 `saas-dev` → **设置**
2. 选择 **CD/DVD (SATA)**
3. 选择 **使用 ISO 映像文件** → 浏览选择 `CentOS-7-x86_64-Minimal-2009.iso`
4. 勾选 **启动时连接**
5. 确定

---

## 三、安装 CentOS 7

### 3.1 启动安装

1. 点击 **开启此虚拟机**
2. 在启动菜单中选择 **Install CentOS 7** → 按 Enter

### 3.2 图形化安装向导

CentOS 7 的安装器是图形界面（Anaconda），用鼠标操作：

#### 第 1 步：语言选择

- 选择 **English → English (United States)** → Continue
- （生产环境统一用英文，避免乱码问题）

#### 第 2 步：安装概览页面（Installation Summary）

这个页面需要配置几个选项，带感叹号 ⚠️ 的必须点进去设置：

**DATE & TIME（日期和时间）**
- 地区：**Asia → Shanghai**
- 点击 Done

**INSTALLATION DESTINATION（安装位置）**
- 点击进入 → 选中 60GB 的虚拟磁盘（已默认选中）
- 分区方案保持 **Automatically configure partitioning**
- 点击 Done

**NETWORK & HOST NAME（网络和主机名）**
- 右上角把网卡（ens33）的开关切到 **ON**（⚠️ 这一步很重要，默认是关闭的！）
- 左下角 Host name 改为：`saas-dev`
- 点击 Apply → Done

其他选项（SOFTWARE SELECTION 等）保持默认即可。

#### 第 3 步：开始安装

点击 **Begin Installation**

#### 第 4 步：设置密码（安装过程中）

安装过程中需要设置：

**ROOT PASSWORD（root 密码）**
- 设置一个密码，如 `root123456`
- 如果密码太简单，点两次 Done 强制确认

**USER CREATION（创建用户）**
- Full name: `dev`
- User name: `dev`
- 勾选 **Make this user administrator**
- Password: `dev123456`
- 点击 Done（密码简单需点两次）

#### 第 5 步：等待安装完成

约 5-10 分钟，完成后点击 **Reboot**

### 3.3 首次登录

重启后看到登录提示：

```
saas-dev login: dev
Password: (输入密码，不会显示)
```

登录成功后会看到命令行提示符：`[dev@saas-dev ~]$`

---

## 四、基础环境配置

> 从这一步开始，建议通过 SSH 从 Windows 连接到虚拟机操作（复制粘贴更方便）

### 4.1 获取虚拟机 IP 地址

```bash
ip addr show | grep "inet " | grep -v 127.0.0.1
```

会看到类似 `inet 192.168.xxx.xxx/24`，记下这个 IP。

从 Windows 用 SSH 连接：

```powershell
# 在 Windows PowerShell 中
ssh dev@192.168.xxx.xxx
```

> 如果 ip addr 没有显示除 127.0.0.1 以外的 IP，说明网卡没有启用，参见下面 4.2 的说明。

### 4.2 确保网卡开机自启

CentOS 7 Minimal 安装后，网卡默认可能不会开机自启。检查并修复：

```bash
# 查看网卡配置
cat /etc/sysconfig/network-scripts/ifcfg-ens33
```

编辑网卡配置文件，确保内容正确（**删掉 HWADDR 和 UUID 行，否则容易冲突报错**）：

```bash
sudo vi /etc/sysconfig/network-scripts/ifcfg-ens33
```

文件内容应为：

```ini
TYPE="Ethernet"
PROXY_METHOD="none"
BROWSER_ONLY="no"
BOOTPROTO="dhcp"
DEFROUTE="yes"
IPV4_FAILURE_FATAL="no"
NAME="ens33"
DEVICE="ens33"
ONBOOT="yes"
# ⚠️ 如果有 HWADDR=xx:xx:xx:xx:xx:xx 这一行，删掉它
# ⚠️ 如果有 UUID=xxx 这一行，也删掉它
```

然后使用 **NetworkManager** 启动网络（不要用 `systemctl restart network`，容易报错）：

```bash
# 停掉老的 network 服务（避免与 NetworkManager 冲突）
sudo systemctl stop network
sudo systemctl disable network

# 用 NetworkManager 管理网络
sudo systemctl restart NetworkManager
sudo systemctl enable NetworkManager

# 如果网卡还没获取到 IP，手动激活：
sudo nmcli connection up ens33

# 验证 IP
ip addr show ens33

# 验证能上网
ping -c 3 baidu.com
```

> **常见报错**：如果执行 `systemctl restart network` 出现
> `Failed to start LSB: Bring up/down networking`，
> 这是 network 服务和 NetworkManager 冲突导致的。
> 按上面的步骤禁用 network 服务、改用 NetworkManager 即可解决。

#### 设置固定 IP — 桥接模式

如果你想切换到桥接模式：

##### 第 1 步：VMware 中切换网络模式

1. 关闭虚拟机
2. 虚拟机 → **设置** → **网络适配器**
3. 选择 **桥接模式（自动）** 或 **桥接模式（指定网卡）**
4. 如果选指定网卡，选你宿主机正在上网的那张网卡（WiFi 或有线网卡）
5. 勾选 **启动时连接**
6. 确定

##### 第 2 步：查看宿主机网络信息

在 **Windows PowerShell** 中查看你物理网络的参数：

```powershell
ipconfig
```

找到你正在上网的网卡（WiFi 或以太网），记下：

```
IPv4 地址 . . . . . . . . . . : 192.168.1.100    ← 宿主机 IP
子网掩码  . . . . . . . . . . : 255.255.255.0     ← 子网掩码
默认网关  . . . . . . . . . . : 192.168.1.1       ← 路由器网关
```

##### 第 3 步：在虚拟机中配置静态 IP

启动虚拟机，登录后：

```bash
sudo vi /etc/sysconfig/network-scripts/ifcfg-ens33
```

修改为：

```ini
TYPE=Ethernet
DEVICE=ens33
NAME=ens33
ONBOOT=yes
BOOTPROTO=static
IPADDR=192.168.1.200                # 与宿主机同网段，选一个没被占用的 IP
NETMASK=255.255.255.0               # 和宿主机一样
GATEWAY=192.168.1.1                 # 物理路由器网关（和宿主机一样）
DNS1=223.5.5.5                      # 阿里 DNS
DNS2=8.8.8.8                        # Google DNScat 
```

> **IP 选择要点**：
>
> - 必须与宿主机在同一网段（前三段相同，如 192.168.1.xxx）
> - 不能与局域网内其他设备冲突（建议用 200 以上的数字）
> - 网关就是你家路由器的 IP（通常是 192.168.1.1 或 192.168.0.1）

```bash
# 重启网络
sudo systemctl restart NetworkManager

# 验证
ip addr show ens33            # 应显示 192.168.1.200
ping -c 3 192.168.1.1         # ping 路由器
ping -c 3 192.168.1.100       # ping 宿主机
ping -c 3 baidu.com           # ping 外网
```

> **注意**：配置内容没问题，IP 没生效大概率是 NetworkManager 缓存了旧的连接配置。按顺序执行：
>
> *# 1. 让 NetworkManager 重新读取配置文件*
>
> sudo nmcli connection reload
>
> *# 2. 重新激活 ens33*
>
> sudo nmcli connection down ens33
>
> sudo nmcli connection up ens33
>
> *# 3. 验证*
>
> ip addr show ens33

### 4.3 配置 yum 国内镜像源

CentOS 7 已经 EOL，官方源不可用了，需要切换到归档源：

```bash
# 备份原有源
sudo mkdir -p /etc/yum.repos.d/backup
sudo mv /etc/yum.repos.d/CentOS-*.repo /etc/yum.repos.d/backup/

# 使用阿里云 CentOS 7 归档源
sudo tee /etc/yum.repos.d/CentOS-Base.repo << 'EOF'
[base]
name=CentOS-7 - Base - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/os/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS-7 - Updates - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/updates/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS-7 - Extras - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/extras/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF

# 清除缓存并验证
sudo yum clean all
sudo yum makecache
```

### 4.4 安装基础工具

```bash
sudo yum install -y curl wget git vim htop net-tools yum-utils lsof
```

---

## 五、安装 Docker

### 5.1 安装 Docker Engine

```bash
# 卸载可能存在的旧版本
sudo yum remove -y docker docker-client docker-client-latest \
    docker-common docker-latest docker-latest-logrotate \
    docker-logrotate docker-engine 2>/dev/null

# 安装依赖
sudo yum install -y yum-utils device-mapper-persistent-data lvm2

# 添加 Docker 官方 yum 源（使用阿里云镜像加速）
sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

# 安装 Docker CE + Docker Compose 插件
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 启动 Docker 并设置开机自启
sudo systemctl start docker
sudo systemctl enable docker
```

### 5.2 配置 Docker（免 sudo + 镜像加速）

```bash
# 将当前用户加入 docker 组（免 sudo 运行 docker 命令）
sudo usermod -aG docker $USER

# 配置 Docker 镜像加速器 + 日志限制
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ],
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

# ⚠️ 重要：退出并重新登录，使 docker 组生效
exit
```

### 5.3 重新 SSH 登录后验证

```bash
# 重新连接
ssh dev@192.168.xxx.xxx

# 验证 Docker（无需 sudo）
docker --version
# 期望输出: Docker version 2x.x.x

docker compose version
# 期望输出: Docker Compose version v2.x.x

# 运行测试容器
docker run hello-world
# 期望输出: Hello from Docker!
```

---

## 六、防火墙配置

CentOS 7 默认启用 firewalld 防火墙，需要开放端口，否则 Windows 无法访问虚拟机中的服务。

```bash
# 开放项目需要的端口
sudo firewall-cmd --permanent --add-port=8080/tcp    # 应用服务
sudo firewall-cmd --permanent --add-port=9090/tcp    # Prometheus
sudo firewall-cmd --permanent --add-port=3000/tcp    # Grafana
sudo firewall-cmd --permanent --add-port=5432/tcp    # PostgreSQL（调试用）
sudo firewall-cmd --permanent --add-port=6379/tcp    # Redis（调试用）

# 重新加载防火墙规则
sudo firewall-cmd --reload

# 验证已开放的端口
sudo firewall-cmd --list-ports
# 期望输出: 8080/tcp 9090/tcp 3000/tcp 5432/tcp 6379/tcp
```

> 也可以直接关闭防火墙（仅限学习环境，生产环境不要这样做）：
> ```bash
> sudo systemctl stop firewalld
> sudo systemctl disable firewalld
> ```

---

## 七、关闭 SELinux

SELinux 是 CentOS 的安全模块，可能会阻止 Docker 挂载卷。学习环境建议关闭：

```bash
# 临时关闭（立即生效，重启失效）
sudo setenforce 0

# 永久关闭（需重启生效）
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

# 验证
getenforce
# 期望输出: Permissive 或 Disabled
```

---

## 八、部署项目

### 8.1 上传项目代码到虚拟机

在 **Windows PowerShell** 中操作：

```powershell
# 方法一：用 scp 直接上传整个项目（将 IP 替换为你的虚拟机 IP）
scp -r "d:\project\study\saas-shortener" dev@192.168.xxx.xxx:~/

# 方法二（推荐）：如果项目已推送到 Git 仓库
# 在虚拟机中执行：
# git clone https://github.com/yourname/saas-shortener.git
```

### 8.2 在虚拟机中启动项目

SSH 连接到虚拟机后：

```
# 1. 给 Docker 配置国内 DNS
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ],
  "dns": ["223.5.5.5", "114.114.114.114"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# 2. 重启 Docker
sudo systemctl restart docker
```

```bash
cd ~/saas-shortener

# 一键启动所有服务（首次会拉取镜像 + 编译，约 5-10 分钟）
docker compose -f deploy/docker-compose/docker-compose.yaml up -d --build

# 查看服务状态（等待所有服务变为 healthy/running）
docker compose -f deploy/docker-compose/docker-compose.yaml ps

# 查看应用日志（Ctrl+C 退出日志跟踪）
docker compose -f deploy/docker-compose/docker-compose.yaml logs -f app
```

### 8.3 从 Windows 访问虚拟机中的服务

在 Windows 浏览器中打开（将 IP 替换为你的虚拟机 IP）：

| 服务 | 地址 | 说明 |
|------|------|------|
| 应用 API | `http://192.168.xxx.xxx:8080` | 短链接服务 |
| Prometheus | `http://192.168.xxx.xxx:9090` | 监控指标查询 |
| Grafana | `http://192.168.xxx.xxx:3000` | 可视化仪表盘 (admin/admin) |

### 8.4 测试 API

在 Windows PowerShell 中（将 IP 替换为你的虚拟机 IP）：

```powershell
$VM_IP = "192.168.xxx.xxx"    # ← 改成你的虚拟机 IP

# 1. 健康检查
Invoke-RestMethod -Uri "http://${VM_IP}:8080/healthz"

# 2. 创建租户
$body = '{"name": "test-company", "plan": "free"}'
$tenant = Invoke-RestMethod -Uri "http://${VM_IP}:8080/api/v1/tenants" -Method Post -Body $body -ContentType "application/json"
$tenant | ConvertTo-Json
# ⚠️ 记下返回的 api_key！

# 3. 创建短链接（把 <API_KEY> 替换为上一步的 api_key）
$urlBody = '{"url": "https://github.com"}'
Invoke-RestMethod -Uri "http://${VM_IP}:8080/api/v1/urls" -Method Post -Body $urlBody -ContentType "application/json" -Headers @{"X-API-Key" = "<API_KEY>"}
```

### 8.5 常用管理命令

```bash
# 查看所有容器状态
docker compose -f deploy/docker-compose/docker-compose.yaml ps

# 查看所有日志
docker compose -f deploy/docker-compose/docker-compose.yaml logs -f

# 停止所有服务
docker compose -f deploy/docker-compose/docker-compose.yaml down

# 停止并清除所有数据（重新开始）
docker compose -f deploy/docker-compose/docker-compose.yaml down -v

# 重新构建并启动应用（改了代码后）
docker compose -f deploy/docker-compose/docker-compose.yaml up -d --build app
```

---

## 九、VMware 实用技巧

### 9.1 拍摄快照（重要！）

在安装好 Docker、部署好项目后，**拍一个快照**。搞坏了随时恢复：

- VMware 菜单 → **虚拟机 → 快照 → 拍摄快照**
- 名称：`docker-ready`（或自定义名称）
- 恢复：**虚拟机 → 快照 → 恢复到快照**

建议拍两个快照：
1. `os-ready` — 系统安装完、基础配置做好后
2. `docker-ready` — Docker 安装好、项目部署好后

### 9.2 NAT 模式 vs 桥接模式

VMware 有两种常用的网络模式，区别很大：

```
NAT 模式：
┌──────────────────────────────────────────────────────┐
│  物理网络（家里/公司路由器 192.168.1.0/24）            │
│                                                       │
│  ┌─────────────┐                                     │
│  │ Windows 宿主 │ 192.168.1.100（物理网卡）           │
│  │              │ 192.168.110.1（VMnet8 虚拟网卡）    │
│  │  ┌────────┐  │                                     │
│  │  │ 虚拟机  │  │ 192.168.110.128（VMnet8 内部网段）  │
│  │  └────────┘  │                                     │
│  └─────────────┘                                     │
│  虚拟机通过 VMware NAT 服务转发上网                     │
│  虚拟机和宿主机不在同一网段                             │
│  局域网其他电脑无法直接访问虚拟机                       │
└──────────────────────────────────────────────────────┘

桥接模式：
┌──────────────────────────────────────────────────────┐
│  物理网络（家里/公司路由器 192.168.1.0/24）            │
│                                                       │
│  ┌─────────────┐    ┌────────┐                       │
│  │ Windows 宿主 │    │ 虚拟机  │                       │
│  │ 192.168.1.100│    │192.168.1.200│                  │
│  └─────────────┘    └────────┘                       │
│  虚拟机直接连在物理网络上，和宿主机平级                   │
│  虚拟机和宿主机在同一网段                               │
│  局域网其他电脑可以直接访问虚拟机                       │
└──────────────────────────────────────────────────────┘
```

| 对比项 | NAT 模式 | 桥接模式 |
|--------|----------|----------|
| 虚拟机 IP 网段 | 独立网段（如 192.168.110.x） | 与宿主机同网段（如 192.168.1.x） |
| 宿主机能否访问虚拟机 | 能 | 能 |
| 局域网其他电脑能否访问 | **不能**（被 NAT 隔离） | **能**（和真实设备一样） |
| 虚拟机能否上外网 | 能（通过 NAT 转发） | 能（直接走物理网络） |
| 是否依赖物理网络 | **不依赖**（没有 WiFi 也能用） | **依赖**（必须有网络环境） |
| 更像生产环境 | 一般 | **更像**（独立 IP，和真机无异） |
| 配置复杂度 | 简单 | 需要知道物理网络的网关和网段 |

**选择建议**：
- 只在本机开发学习 → **NAT**（简单稳定，不受物理网络影响）
- 想让手机/其他电脑也能访问，或模拟真实服务器 → **桥接**

### 9.3 设置固定 IP — NAT 模式

DHCP 分配的 IP 重启后可能会变。设置静态 IP：

```bash
# 查看当前 IP 和网关信息
ip addr show ens33
ip route | grep default
# 记下网关地址，NAT 模式通常是 192.168.xxx.2
```

> 如何确定 NAT 网关？在 VMware 中点击 **编辑 → 虚拟网络编辑器 → 选择 VMnet8 → NAT 设置**，可以看到网关 IP。

```bash
# 编辑网卡配置
sudo vi /etc/sysconfig/network-scripts/ifcfg-ens33
```

修改/添加以下内容：

```ini
TYPE=Ethernet
DEVICE=ens33
NAME=ens33
ONBOOT=yes
BOOTPROTO=static                    # 改为 static（原来是 dhcp）
IPADDR=192.168.110.100              # 固定 IP（与 VMnet8 同网段，避开 .1 和 .2）
NETMASK=255.255.255.0               # 子网掩码
GATEWAY=192.168.110.2               # NAT 网关（从虚拟网络编辑器中确认）
DNS1=223.5.5.5                      # 阿里 DNS
DNS2=8.8.8.8                        # Google DNS
```

```bash
# 重启网络
sudo systemctl restart NetworkManager

# 验证
ip addr show ens33
ping -c 3 baidu.com
```

### 9.4 设置固定 IP — 桥接模式

如果你想切换到桥接模式：

#### 第 1 步：VMware 中切换网络模式

1. 关闭虚拟机
2. 虚拟机 → **设置** → **网络适配器**
3. 选择 **桥接模式（自动）** 或 **桥接模式（指定网卡）**
4. 如果选指定网卡，选你宿主机正在上网的那张网卡（WiFi 或有线网卡）
5. 勾选 **启动时连接**
6. 确定

#### 第 2 步：查看宿主机网络信息

在 **Windows PowerShell** 中查看你物理网络的参数：

```powershell
ipconfig
```

找到你正在上网的网卡（WiFi 或以太网），记下：

```
IPv4 地址 . . . . . . . . . . : 192.168.1.100    ← 宿主机 IP
子网掩码  . . . . . . . . . . : 255.255.255.0     ← 子网掩码
默认网关  . . . . . . . . . . : 192.168.1.1       ← 路由器网关
```

#### 第 3 步：在虚拟机中配置静态 IP

启动虚拟机，登录后：

```bash
sudo vi /etc/sysconfig/network-scripts/ifcfg-ens33
```

修改为：

```ini
TYPE=Ethernet
DEVICE=ens33
NAME=ens33
ONBOOT=yes
BOOTPROTO=static
IPADDR=192.168.1.200                # 与宿主机同网段，选一个没被占用的 IP
NETMASK=255.255.255.0               # 和宿主机一样
GATEWAY=192.168.1.1                 # 物理路由器网关（和宿主机一样）
DNS1=223.5.5.5
DNS2=8.8.8.8
```

> **IP 选择要点**：
>
> - 必须与宿主机在同一网段（前三段相同，如 192.168.1.xxx）
> - 不能与局域网内其他设备冲突（建议用 200 以上的数字）
> - 网关就是你家路由器的 IP（通常是 192.168.1.1 或 192.168.0.1）

```bash
# 重启网络
sudo systemctl restart NetworkManager

# 验证
ip addr show ens33            # 应显示 192.168.1.200
ping -c 3 192.168.1.1         # ping 路由器
ping -c 3 192.168.1.100       # ping 宿主机
ping -c 3 baidu.com           # ping 外网
```

> **注意**：配置内容没问题，IP 没生效大概率是 NetworkManager 缓存了旧的连接配置。按顺序执行：
>
> *# 1. 让 NetworkManager 重新读取配置文件*
>
> sudo nmcli connection reload
>
> *# 2. 重新激活 ens33*
>
> sudo nmcli connection down ens33
>
> sudo nmcli connection up ens33
>
> *# 3. 验证*
>
> ip addr show ens33

#### 第 4 步：从 Windows 连接

```powershell
ssh dev@192.168.1.200
```

桥接模式下，局域网内的其他设备（手机、其他电脑）也可以直接通过 `192.168.1.200` 访问虚拟机中的服务。

> **注意**：桥接模式依赖物理网络环境。如果你换了 WiFi（比如从家到公司），宿主机网段可能变化，虚拟机的静态 IP 也需要相应修改。NAT 模式则不受影响。

### 9.3 设置虚拟机开机自启

如果不想每次开机都手动启动虚拟机：

1. VMware 菜单 → **编辑 → 首选项 → 工作区**
2. 勾选 **在主机启动时恢复工作区中的虚拟机**

### 9.4 VMware 与宿主机共享文件夹

除了 scp 之外，还可以用共享文件夹同步代码：

1. 在虚拟机中安装 VMware Tools：
   ```bash
   sudo yum install -y open-vm-tools
   sudo systemctl enable vmtoolsd
   sudo systemctl start vmtoolsd
   ```

2. 虚拟机设置 → **选项 → 共享文件夹**
3. 选择 **总是启用**
4. 添加共享路径：`D:\project\study\saas-shortener`
5. 虚拟机内挂载共享文件夹：
   ```bash
   # 创建挂载点
   sudo mkdir -p /mnt/hgfs
   
   # 挂载（手动）
   sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other
   
   # 开机自动挂载：在 /etc/fstab 末尾添加
   echo '.host:/ /mnt/hgfs fuse.vmhgfs-fuse allow_other,defaults 0 0' | sudo tee -a /etc/fstab
   ```
6. 访问路径：`/mnt/hgfs/saas-shortener`

---

## 十、常见问题

### Q: VMware 提示 "此主机支持 Intel VT-x，但 Intel VT-x 处于禁用状态"

需要在 BIOS 中开启 CPU 虚拟化：
1. 重启电脑 → 进入 BIOS（开机时按 F2/F10/Del，取决于主板品牌）
2. 找到 **Intel Virtualization Technology** 或 **AMD-V**
3. 设置为 **Enabled**
4. 保存并重启

### Q: VMware 和 Hyper-V/WSL2 冲突

如果你之前安装了 Docker Desktop（使用了 Hyper-V/WSL2），可能会和 VMware 冲突：

```powershell
# 以管理员身份运行 PowerShell
# 关闭 Hyper-V（需要重启）
bcdedit /set hypervisorlaunchtype off
```

> 注意：关闭 Hyper-V 后 Docker Desktop 将无法使用。
> 建议二选一：要么用 Docker Desktop（不需要 VMware），要么用 VMware + 虚拟机内的 Docker。

### Q: yum install 报错 "Could not resolve host" 或 "Cannot find a valid baseurl"

网络未连通，检查：

```bash
# 1. 检查网卡是否启用
ip addr show ens33
# 如果没有 IP，启用网卡：
sudo ifup ens33

# 2. 检查 DNS
ping -c 3 baidu.com
# 如果 ping 不通，手动设置 DNS：
echo "nameserver 223.5.5.5" | sudo tee /etc/resolv.conf

# 3. 检查 yum 源配置是否正确
sudo yum repolist
```

### Q: Docker 拉取镜像很慢或超时

确认镜像加速器已配置：

```bash
# 查看 Docker 配置
cat /etc/docker/daemon.json

# 如果没有或配置不对，重新配置（参见第 5.2 步）
# 配置后重启 Docker
sudo systemctl restart docker
```

### Q: docker compose up 报错 "permission denied"

```bash
# 确认当前用户在 docker 组中
groups
# 如果没有 docker，重新添加：
sudo usermod -aG docker $USER
# 然后退出重新登录
exit
```

### Q: 从 Windows 无法访问虚拟机服务

按顺序排查：

```bash
# 1. 虚拟机中确认服务在运行
docker compose -f deploy/docker-compose/docker-compose.yaml ps

# 2. 虚拟机中确认端口在监听
ss -tlnp | grep -E "8080|3000|9090"

# 3. 确认防火墙已放行端口
sudo firewall-cmd --list-ports
# 如果没有，参见第六章防火墙配置

# 4. 从虚拟机内部测试
curl http://localhost:8080/healthz
```

如果虚拟机内部能访问但 Windows 不行，问题在 VMware 网络配置：
- 确认虚拟机网络模式是 **NAT**
- 检查 Windows 防火墙是否阻止了 VMware 的网络

### Q: CentOS 7 yum 源报 404 错误

CentOS 7 已 EOL，官方 mirror 已下线。确保使用归档源（参见第 4.3 步）。

---

## 十一、环境架构图

```
┌──────────────────────────────────────────────────────────┐
│  Windows 宿主机 (12C 32G)                                 │
│                                                           │
│  ┌──────────────────────────────────────────────────┐    │
│  │  VMware 虚拟机: saas-dev (4C 8G 60GB)             │    │
│  │  CentOS 7 Minimal                                 │    │
│  │                                                    │    │
│  │  ┌──────────────────────────────────────────┐    │    │
│  │  │  Docker                                    │    │    │
│  │  │                                            │    │    │
│  │  │  ┌─────────┐  ┌───────┐  ┌─────────┐    │    │    │
│  │  │  │   App   │  │  PG   │  │  Redis  │    │    │    │
│  │  │  │  :8080  │  │ :5432 │  │  :6379  │    │    │    │
│  │  │  └─────────┘  └───────┘  └─────────┘    │    │    │
│  │  │                                            │    │    │
│  │  │  ┌───────────┐  ┌──────────┐             │    │    │
│  │  │  │Prometheus │  │ Grafana  │             │    │    │
│  │  │  │   :9090   │  │  :3000   │             │    │    │
│  │  │  └───────────┘  └──────────┘             │    │    │
│  │  └──────────────────────────────────────────┘    │    │
│  └──────────────────────────────────────────────────┘    │
│                                                           │
│  浏览器访问: http://192.168.xxx.xxx:8080                   │
│  SSH 连接:   ssh dev@192.168.xxx.xxx                       │
└──────────────────────────────────────────────────────────┘
```

---

## 十二、操作速查表

一切就绪后的日常操作：

```bash
# === 从 Windows SSH 连入 ===
ssh dev@192.168.xxx.xxx

# === 启动项目 ===
cd ~/saas-shortener
docker compose -f deploy/docker-compose/docker-compose.yaml up -d --build

# === 查看状态 ===
docker compose -f deploy/docker-compose/docker-compose.yaml ps

# === 查看日志 ===
docker compose -f deploy/docker-compose/docker-compose.yaml logs -f app

# === 停止项目 ===
docker compose -f deploy/docker-compose/docker-compose.yaml down

# === 查看系统资源占用 ===
htop           # CPU 和内存
df -h          # 磁盘
docker stats   # 各容器资源占用
```
