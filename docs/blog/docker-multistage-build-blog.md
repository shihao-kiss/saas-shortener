# 一、Dockerfile 的作用

​    Docker 镜像是一个特殊的文件系统，除了提供容器运行时所需的程序、库、资源、配置等文件外，还包含了一些为运行时准备的一些配置参数（如匿名卷、环境变量、用户等）。镜像不包含任何动态数据，其内容在构建之后也不会被改变。

​    镜像的定制实际上就是定制每一层所添加的配置、文件。如果我们可以把每一层修改、安装、构建、操作的命令都写入一个脚本，用这个脚本来构建、定制镜像，那么之前提及的无法重复的问题、镜像构建透明性的问题、体积的问题就都会解决。这个脚本就是 Dockerfile。

​    Dockerfile 是一个文本文件，其内包含了一条条的指令(Instruction)，每一条指令构建一层，因此每一条指令的内容，就是描述该层应当如何构建。有了 Dockerfile，当我们需要定制自己额外的需求时，只需在 Dockerfile 上添加或者修改指令，重新生成 image 即可，省去了敲命令的麻烦。


# 二、多阶段构建

```
第一阶段：编译构建
↓
第二阶段：运行时环境
↓
最终产物：精简的生产镜像
```



# 三、源码解析

```
# ==================== 多阶段构建（Multi-Stage Build） ====================
# 云原生最佳实践：使用多阶段构建减小镜像体积
# 第一阶段（builder）：编译 Go 程序
# 第二阶段（runtime）：只包含编译后的二进制文件
# 最终镜像大小通常只有 10-20MB（对比传统方式 几百MB）

# ---------- 阶段1：编译 ----------
FROM golang:1.22-alpine AS builder

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
FROM alpine:3.19

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

```



# 四、Docker 多阶段构建为什么能压缩体积

## 核心原理

Docker 镜像是**分层叠加**的——每一条 `RUN`、`COPY` 指令都会新增一层，**所有层的内容都会保留在最终镜像中，即使后面删除了也不会真正减小体积**。

多阶段构建的本质：**用一个大而全的环境编译，然后只把编译产物复制到一个干净的小镜像里，构建环境的几百 MB "垃圾"不会进入最终镜像。**

---

## 单阶段 vs 多阶段对比

### 单阶段构建（传统方式）

```dockerfile
FROM golang:1.22-alpine

WORKDIR /app
COPY . .
RUN go mod download
RUN CGO_ENABLED=0 go build -o server ./cmd/server

ENTRYPOINT ["./server"]
```

最终镜像里包含了什么？

| 内容 | 大小（约） | 运行时需要？ |
|------|-----------|-------------|
| Alpine Linux 基础系统 | ~7 MB | ✅ |
| **Go 编译器 + 工具链** | **~500 MB** | ❌ |
| **Go 模块缓存（所有依赖源码）** | **~100 MB** | ❌ |
| **项目源代码（.go 文件）** | **~5 MB** | ❌ |
| **git 等构建工具** | **~20 MB** | ❌ |
| 编译好的二进制 `server` | ~15 MB | ✅ |
| **总计** | **~650 MB** | |

实际运行只需要那个 15MB 的二进制，但其余 600 多 MB 的"构建垃圾"全部被打进了镜像。

### 多阶段构建

```dockerfile
# 阶段1: builder —— 这个阶段的所有内容最终会被丢弃
FROM golang:1.22-alpine AS builder
RUN apk add --no-cache git ca-certificates
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /app/server ./cmd/server

# 阶段2: runtime —— 只有这个阶段的内容进入最终镜像
FROM alpine:3.19
RUN apk --no-cache add ca-certificates tzdata
COPY --from=builder /app/server .    # 只拿走编译好的二进制
ENTRYPOINT ["./server"]
```

最终镜像里包含什么？

| 内容 | 大小（约） | 运行时需要？ |
|------|-----------|-------------|
| Alpine Linux 基础系统 | ~7 MB | ✅ |
| ca-certificates + tzdata | ~2 MB | ✅ |
| 编译好的二进制 `server` | ~15 MB | ✅ |
| **总计** | **~24 MB** | |

Go 编译器、源代码、依赖缓存、git 等全部**留在了 builder 阶段**，没有进入最终镜像。

---

## 关键机制图解

```
┌─────────────────────────────────────┐
│  阶段1: builder (golang:1.22-alpine)│
│                                     │
│  ├── Go 编译器        ~500 MB       │
│  ├── 依赖源码缓存     ~100 MB       │
│  ├── 项目源代码        ~5 MB        │
│  ├── git 等工具        ~20 MB       │
│  └── 编译产物 server   ~15 MB  ──────────┐
│                                     │    │
│  （整个阶段被丢弃，不进入最终镜像）    │    │
└─────────────────────────────────────┘    │
                                           │ COPY --from=builder
┌─────────────────────────────────────┐    │
│  阶段2: runtime (alpine:3.19)       │    │
│                                     │    │
│  ├── Alpine 基础系统   ~7 MB        │    │
│  ├── ca-certs + tzdata ~2 MB        │    │
│  └── server 二进制     ~15 MB  ◄─────────┘
│                                     │
│  最终镜像 = ~24 MB                  │
└─────────────────────────────────────┘
```

---

## 为什么单阶段删除也没用？

你可能会想：在单阶段里编译完后删掉 Go 编译器不行吗？

```dockerfile
FROM golang:1.22-alpine
WORKDIR /app
COPY . .
RUN go build -o server ./cmd/server
RUN rm -rf /usr/local/go    # 删掉 Go 编译器
```

**不行。** Docker 每条指令是一层，`rm` 只是在新层标记"删除"，但底层那 500MB 仍然存在于之前的层中。镜像体积 = 所有层之和，**删除操作不会减小已有层的大小**。

即使合并成一条 `RUN`：

```dockerfile
RUN go build -o server ./cmd/server && rm -rf /usr/local/go
```

虽然同一层内删除有效，但基础镜像 `golang:1.22-alpine` 本身就带了 500MB 的 Go 工具链，这部分在更底层，无论如何删不掉。

---

## 本项目 Dockerfile 中的其他优化技巧

除了多阶段构建，Dockerfile 还使用了以下优化：

### 1. 静态编译

```dockerfile
RUN CGO_ENABLED=0 GOOS=linux go build ...
```

- `CGO_ENABLED=0`：禁用 CGO，生成静态链接的二进制文件
- 不依赖任何 C 库，运行时镜像不需要安装 glibc
- 这也是为什么可以使用极简的 Alpine 甚至 scratch 镜像

### 2. 去除调试信息

```dockerfile
-ldflags="-s -w"
```

- `-s`：去除符号表
- `-w`：去除 DWARF 调试信息
- 二进制体积可减小约 **30%**

### 3. 依赖缓存分离

```dockerfile
COPY go.mod go.sum ./
RUN go mod download
COPY . .
```

- 先复制 `go.mod` 和 `go.sum`，单独下载依赖
- 只有依赖变化时才重新下载，源码变化不影响依赖缓存层
- 这是**构建速度优化**，不直接影响体积，但大幅减少重复构建时间

### 4. 最小运行时基础镜像

```dockerfile
FROM alpine:3.19
```

| 基础镜像 | 大小 |
|---------|------|
| `ubuntu:22.04` | ~77 MB |
| `debian:12-slim` | ~74 MB |
| `alpine:3.19` | **~7 MB** |
| `scratch`（空镜像） | **0 MB** |

Alpine 是目前最常用的轻量级基础镜像，比 Ubuntu 小 10 倍。

---

## 总结

| 优化手段 | 效果 |
|---------|------|
| 多阶段构建 | 650 MB → 24 MB，去除编译环境 |
| 静态编译 `CGO_ENABLED=0` | 不依赖 C 库，可用极简镜像 |
| 去调试信息 `-ldflags="-s -w"` | 二进制体积减小 ~30% |
| 依赖缓存分离 | 加速重复构建 |
| Alpine 基础镜像 | 比 Ubuntu 小 10 倍 |

> 一句话总结：**多阶段构建 = 大环境编译 + 小环境运行，编译垃圾不进最终镜像。**
