# 宝塔面板安装指南（CentOS 7）

> 目的：安装宝塔面板作为服务器可视化管理工具，方便查看资源、管理文件和防火墙。
>
> ⚠️ **只装面板本身，不要装它推荐的 LNMP/LAMP 套件**（Nginx、MySQL、PHP 等全部跳过）。
> 本项目的数据库、Redis 等全部运行在 Docker 容器中，装宝塔自带的软件会造成端口冲突。

---

## 一、安装前准备

确认已完成以下步骤（参考 `vmware-setup-guide.md`）：

- [x] CentOS 7 虚拟机已安装完成
- [x] 网络已配通，能从 Windows SSH 连接
- [x] yum 源已配置为阿里云归档源

---

## 二、安装宝塔面板

### 2.1 执行安装脚本

```bash
yum install -y wget && wget -O install.sh https://download.bt.cn/install/install_6.0.sh && sh install.sh ed8484bec
```

安装过程中提示 `Do you want to install Bt-Panel to the /www directory now?(y/n)`，输入 **y** 回车。

等待约 2-3 分钟，安装完成后会显示：

```
==================================================================
外网面板地址: http://xxx.xxx.xxx.xxx:8888/xxxxxxxx
内网面板地址: http://192.168.110.xxx:8888/xxxxxxxx
username: xxxxxxxx
password: xxxxxxxx
==================================================================
```

**⚠️ 请立即记下用户名和密码！** 之后找回比较麻烦。

### 2.2 开放防火墙端口

```bash
# 放行宝塔面板端口
sudo firewall-cmd --permanent --add-port=8888/tcp
sudo firewall-cmd --reload

# 验证
sudo firewall-cmd --list-ports
# 应包含 8888/tcp
```

### 2.3 访问面板

在 Windows 浏览器中打开安装完成时显示的内网面板地址：

```
http://192.168.110.xxx:8888/xxxxxxxx
```

输入安装时给出的用户名和密码登录。

---

## 三、首次登录配置

### 3.1 跳过软件推荐安装

登录后会弹出**推荐安装套件**的对话框，**直接关掉，一个都不要装**：

| 宝塔推荐   | 操作     | 原因                                           |
| ---------- | -------- | ---------------------------------------------- |
| Nginx      | **不装** | 项目通过 Docker 暴露端口，不需要额外的反向代理 |
| MySQL      | **不装** | 项目使用 Docker 中的 PostgreSQL                |
| PHP        | **不装** | Go 项目不需要 PHP                              |
| phpMyAdmin | **不装** | 不使用 MySQL                                   |
| Redis      | **不装** | 项目使用 Docker 中的 Redis                     |

### 3.2 绑定账号（可选）

宝塔会提示绑定宝塔官网账号，可以选择绑定也可以跳过。学习环境跳过即可。

---

## 四、宝塔面板的用途

在本项目中，宝塔面板主要用作轻量管理工具：

### 4.1 服务器监控

面板首页可以实时查看：

- CPU 使用率
- 内存使用率
- 磁盘使用率
- 网络流量

### 4.2 文件管理

左侧菜单 → **文件**：

- 可视化浏览服务器文件
- 上传/下载文件（比 scp 方便）
- 在线编辑文件
- 项目代码位于 `/home/dev/saas-shortener/`

### 4.3 终端

左侧菜单 → **终端**：

- 自带 Web 终端，不用单独开 SSH 客户端
- 可以直接在浏览器里执行命令

### 4.4 防火墙管理

左侧菜单 → **安全**：

- 可视化管理防火墙端口
- 比命令行 `firewall-cmd` 更直观

### 4.5 Docker 管理（需安装插件）

左侧菜单 → **Docker**：

- 宝塔自带 Docker 管理界面
- 可以可视化查看容器、镜像、网络、卷

详细安装和使用方法见下方 **第五章**。

---

## 五、安装 Docker 管理插件

宝塔的 Docker 管理插件可以在浏览器中可视化管理容器，比命令行直观很多。

> ⚠️ 这个插件只是**管理界面**，不会重新安装 Docker，不会影响你已有的 Docker 和容器。

### 5.1 安装插件

**方法一：通过面板安装（推荐）**

1. 登录宝塔面板
2. 左侧菜单 → **Docker**
3. 如果 Docker 插件未安装，页面会提示 **"您还没有安装 Docker 管理器，是否安装？"**
4. 点击 **安装**，等待约 1-2 分钟

如果左侧菜单没有 Docker 选项：

1. 左侧菜单 → **软件商店**
2. 搜索 **Docker管理器**
3. 找到 **Docker管理器** → 点击 **安装**
4. 等待安装完成

**方法二：通过命令行安装**

```bash
# 如果面板中找不到 Docker 选项，可以通过命令行安装
bt 16
# 输入对应的 Docker 管理器编号安装
```

### 5.2 首次配置

安装完成后，点击左侧菜单 → **Docker**，会看到 Docker 管理主界面。

首次进入可能提示 **"检测到系统已安装 Docker"**（因为我们之前已经通过命令行装好了 Docker），直接点 **确定** 即可，不需要重新安装。

### 5.3 功能说明

Docker 管理插件提供以下功能：

#### 容器管理

菜单路径：**Docker → 容器**

| 功能 | 说明 |
|------|------|
| 查看容器列表 | 所有运行中/已停止的容器，包括状态、端口映射、资源占用 |
| 启动/停止/重启 | 点击对应按钮即可，不用敲 `docker start/stop` |
| 查看日志 | 点击容器 → **日志**，实时查看容器输出 |
| 进入终端 | 点击容器 → **终端**，等同于 `docker exec -it xxx sh` |
| 资源监控 | 查看每个容器的 CPU、内存、网络占用 |

启动项目后，你应该能看到以下容器：

| 容器名 | 镜像 | 端口 | 说明 |
|--------|------|------|------|
| saas-shortener | saas-shortener:latest | 8080 | 应用服务 |
| saas-postgres | postgres:16-alpine | 5432 | 数据库 |
| saas-redis | redis:7-alpine | 6379 | 缓存 |
| saas-prometheus | prom/prometheus:v2.51.0 | 9090 | 监控 |
| saas-grafana | grafana/grafana:10.4.0 | 3000 | 可视化 |

#### 镜像管理

菜单路径：**Docker → 镜像**

| 功能 | 说明 |
|------|------|
| 查看镜像列表 | 所有已拉取的镜像和占用空间 |
| 拉取镜像 | 输入镜像名拉取，如 `nginx:latest` |
| 删除镜像 | 清理不用的镜像释放磁盘空间 |

#### Compose 管理

菜单路径：**Docker → Compose**

| 功能 | 说明 |
|------|------|
| 查看 Compose 项目 | 显示通过 docker compose 启动的项目 |
| 启动/停止项目 | 可视化操作，等同于 `docker compose up/down` |
| 编辑配置 | 在线编辑 docker-compose.yaml |

> 本项目的 Compose 文件在 `/home/dev/saas-shortener/deploy/docker-compose/docker-compose.yaml`

#### 网络和存储卷

菜单路径：**Docker → 网络** / **Docker → 存储卷**

- 查看 Docker 创建的虚拟网络（如 `docker-compose_saas-network`）
- 查看持久化存储卷（如 `postgres_data`、`redis_data`）
- 可以手动创建/删除网络和存储卷

### 5.4 实用操作示例

#### 查看应用日志（替代 docker compose logs）

1. **Docker → 容器** → 找到 `saas-shortener`
2. 点击右侧 **日志** 按钮
3. 可以看到实时日志输出，支持搜索和过滤

#### 进入容器排查问题（替代 docker exec）

1. **Docker → 容器** → 找到 `saas-postgres`
2. 点击右侧 **终端** 按钮
3. 进入容器内部，可以直接执行 SQL：
   ```bash
   psql -U postgres -d saas_shortener
   \dt           -- 查看所有表
   SELECT * FROM tenants;  -- 查看租户数据
   \q            -- 退出
   ```

#### 重启单个容器（不影响其他服务）

1. **Docker → 容器** → 找到要重启的容器
2. 点击 **重启** 按钮
3. 等同于 `docker restart <容器名>`

#### 清理磁盘空间

1. **Docker → 镜像** → 删除不用的旧镜像
2. 或者在终端中执行：
   ```bash
   docker system prune -a
   # 会清理所有未使用的镜像、容器、网络
   ```

---

## 六、面板常用命令

```bash
# 查看面板信息（忘记用户名密码时用）
sudo bt default

# 重置面板密码
sudo bt 5

# 修改面板端口
sudo bt 8

# 重启面板
sudo bt restart

# 停止面板
sudo bt stop

# 启动面板
sudo bt start

# 查看面板状态
sudo bt status
```

---

## 七、安全建议

学习环境可以不用太在意，但养成好习惯：

1. **修改默认端口**：8888 是公认的宝塔端口，容易被扫描

   ```bash
   sudo bt 8
   # 输入新端口号，如 12345
   ```

2. **修改默认用户名和密码**：

   - 面板 → 设置 → 面板用户 / 面板密码

3. **绑定访问 IP**（可选）：

   - 面板 → 设置 → 面板 IP → 填写你 Windows 宿主机的 VMnet8 IP
   - 这样只有宿主机能访问面板

---

## 八、资源占用

| 组件           | 内存占用   | 说明                       |
| -------------- | ---------- | -------------------------- |
| 宝塔面板       | ~100-200MB | 仅面板服务（不装任何套件） |
| 8GB 虚拟机剩余 | ~6GB+      | 完全够用                   |

不装 LNMP/LAMP 套件的情况下，宝塔面板对系统资源的影响很小。