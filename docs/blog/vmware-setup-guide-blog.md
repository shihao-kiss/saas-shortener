# VMware 虚拟机搭建指南（CentOS 7）

> 目标：在 Windows 上用 VMware 虚拟一台 4C8G 的 CentOS 7，用于部署本项目。
>
> 镜像：`CentOS-7-x86_64-Minimal-2009.iso`

## ⚠️ 关于 CentOS 7 的说明

CentOS 7 已于 **2024 年 6 月 30 日**停止官方维护（EOL）。这意味着：

- 官方 yum 源已不再更新，需要切换到归档镜像源
- 内核版本较老（3.10），但跑 Docker 没有问题
- 作为学习环境完全够用，生产环境建议考虑 Rocky Linux 9 / AlmaLinux 9

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

| 配置项         | 推荐值                       | 说明                             |
| -------------- | ---------------------------- | -------------------------------- |
| **处理器**     | 2 个处理器 × 2 核 = **4 核** | 处理器数量 2，每个处理器核心数 2 |
| **内存**       | **8192 MB (8GB)**            | 拖动滑块到 8GB                   |
| **网络**       | **NAT**                      | 虚拟机通过宿主机上网，最简单     |
| **I/O 控制器** | LSI Logic（默认）            | 保持默认                         |
| **磁盘类型**   | SCSI（默认）                 | 保持默认                         |
| **磁盘**       | **创建新虚拟磁盘**           |                                  |
| **磁盘大小**   | **60 GB**                    | 勾选"将虚拟磁盘拆分成多个文件"   |

7. 最后一步点击 **完成**

### 2.3 挂载 ISO 镜像

1. 在虚拟机列表中右键 `saas-dev` → **设置**
2. 选择 **CD/DVD (SATA)**
3. 选择 **使用 ISO 映像文件** → 浏览选择 `CentOS-7-x86_64-Minimal-2009.iso`
4. 勾选 **启动时连接**
5. 确定

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

### 4.1 配置网络

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
TYPE="Ethernet"
DEVICE="ens33"
NAME="ens33"
ONBOOT="yes"
BOOTPROTO="static"
IPADDR="192.168.1.200"                # 与宿主机同网段，选一个没被占用的 IP
NETMASK="255.255.255.0"               # 和宿主机一样
GATEWAY="192.168.1.1"                 # 物理路由器网关（和宿主机一样）
DNS1="223.5.5.5"                      # 阿里 DNS
DNS2="8.8.8.8"                        # Google DNScat 
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

### 4.2 配置 yum 国内镜像源

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

### 4.3 安装基础工具

```bash
sudo yum install -y curl wget git vim htop net-tools yum-utils lsof
```

## 五、VMware 实用技巧

### 5.1 拍摄快照（重要！）

系统安装完，**拍一个快照**。搞坏了随时恢复：

- VMware 菜单 → **虚拟机 → 快照 → 拍摄快照**
- 名称：`docker-ready`（或自定义名称）
- 恢复：**虚拟机 → 快照 → 恢复到快照**

建议拍快照：

1. `os-ready` — 系统安装完、基础配置做好后

### 5.2 NAT 模式 vs 桥接模式

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

| 对比项                 | NAT 模式                       | 桥接模式                         |
| ---------------------- | ------------------------------ | -------------------------------- |
| 虚拟机 IP 网段         | 独立网段（如 192.168.110.x）   | 与宿主机同网段（如 192.168.1.x） |
| 宿主机能否访问虚拟机   | 能                             | 能                               |
| 局域网其他电脑能否访问 | **不能**（被 NAT 隔离）        | **能**（和真实设备一样）         |
| 虚拟机能否上外网       | 能（通过 NAT 转发）            | 能（直接走物理网络）             |
| 是否依赖物理网络       | **不依赖**（没有 WiFi 也能用） | **依赖**（必须有网络环境）       |
| 更像生产环境           | 一般                           | **更像**（独立 IP，和真机无异）  |
| 配置复杂度             | 简单                           | 需要知道物理网络的网关和网段     |

**选择建议**：

- 只在本机开发学习 → **NAT**（简单稳定，不受物理网络影响）
- 想让手机/其他电脑也能访问，或模拟真实服务器 → **桥接**

### 5.3 设置虚拟机开机自启

如果不想每次开机都手动启动虚拟机：

1. VMware 菜单 → **编辑 → 首选项 → 工作区**
2. 勾选 **在主机启动时恢复工作区中的虚拟机**

































