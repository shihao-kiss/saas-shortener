# Docker 环境配置（CentOS 7）

> 目标：在虚拟机上安装 docker，并开镜像加速
>
> 虚拟机：Linux saas-dev 3.10.0-1160.el7.x86_64

## 一、安装 Docker Engine

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

## 二、配置 Docker（免 sudo + 镜像加速）

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

# ⚠️ 重要：退出并重新登录，使 docker 组生效
exit
```

## 三、重新 SSH 登录后验证

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

## 四、关闭 SELinux

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



