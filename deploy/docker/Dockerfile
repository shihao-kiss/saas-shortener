# ==================== 多阶段构建（Multi-Stage Build） ====================
# 云原生最佳实践：使用多阶段构建减小镜像体积
# 第一阶段（builder）：编译 Go 程序
# 第二阶段（runtime）：只包含编译后的二进制文件
# 最终镜像大小通常只有 10-20MB（对比传统方式 几百MB）

# 镜像仓库前缀，构建时可通过 --build-arg DOCKER_REGISTRY=xxx 覆盖
# 默认使用 Docker Hub，无代理时可改为: docker.m.daocloud.io / dockerpull.org
ARG DOCKER_REGISTRY=docker.io/library

# ---------- 阶段1：编译 ----------
FROM ${DOCKER_REGISTRY}/golang:1.22-alpine AS builder

# 替换 Alpine 软件源为阿里云镜像（国内环境必须，否则下载超时）
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

# 安装编译需要的工具
RUN apk add --no-cache git ca-certificates

# 设置工作目录
WORKDIR /app

# 设置 Go 模块代理（国内环境加速依赖下载）
ENV GOPROXY=https://goproxy.cn,direct

# 先复制依赖文件，利用 Docker 层缓存
# 只有 go.mod/go.sum 变化时才重新下载依赖
COPY go.mod go.sum ./
RUN go mod download

# 复制源代码
COPY . .

# 编译
# CGO_ENABLED=0: 禁用 CGO，生成静态链接的二进制（不依赖 C 库）
# -ldflags="-s -w": 去除调试信息，减小二进制体积
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w" \
    -o /app/server \
    ./cmd/server

# ---------- 阶段2：运行时 ----------
# 使用最小基础镜像 scratch 或 distroless
# scratch 是空镜像，distroless 包含基础运行时
FROM ${DOCKER_REGISTRY}/alpine:3.19

# 替换 Alpine 软件源为阿里云镜像
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

# 安装 CA 证书（HTTPS 请求需要）和时区数据
RUN apk --no-cache add ca-certificates tzdata

# 创建非 root 用户（安全最佳实践）
RUN adduser -D -g '' appuser

# 设置工作目录
WORKDIR /app

# 从 builder 阶段复制编译好的二进制
COPY --from=builder /app/server .

# 使用非 root 用户运行（安全最佳实践）
USER appuser

# 暴露端口（仅作文档用途，实际端口由运行时环境变量控制）
EXPOSE 8080

# 健康检查
# Docker 原生健康检查，Kubernetes 中通常使用 Probe 替代
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/healthz || exit 1

# 启动命令
ENTRYPOINT ["./server"]
