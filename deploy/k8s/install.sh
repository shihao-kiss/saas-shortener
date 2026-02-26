#!/usr/bin/env bash
# =============================================================================
# saas-shortener K8S 一键安装脚本
# 功能：预拉取镜像 → 构建应用 → 部署基础设施 → 部署应用 → 启用 Ingress/HPA
# 前置：minikube 已启动 (minikube start)，或已有可用的 K8S 集群
# 用法：make k8s-deploy 或 bash deploy/k8s/install.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
K8S_DIR="$SCRIPT_DIR"
APP_NAME="saas-shortener"
NAMESPACE="saas-shortener"

# 阿里云 K8S 镜像仓库（与 minikube --image-repository 一致）
K8S_IMG_REPO="registry.cn-hangzhou.aliyuncs.com/google_containers"

# 所有需要的第三方镜像（宿主机拉取 → minikube image load）
IMAGES=(
    "postgres:16-alpine"
    "redis:7-alpine"
    "${K8S_IMG_REPO}/nginx-ingress-controller:v1.10.0"
    "${K8S_IMG_REPO}/kube-webhook-certgen:v1.4.0"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "$1 未安装，请先安装"
        exit 1
    fi
}

check_k8s() {
    if ! kubectl cluster-info &>/dev/null; then
        log_error "无法连接 K8S 集群，请确保 minikube 已启动: minikube start"
        exit 1
    fi
}

is_minikube() {
    command -v minikube &>/dev/null && minikube status &>/dev/null 2>&1
}

# 使用宿主机 Docker 拉取所有镜像，再 load 到 Minikube
# Minikube 内部 Docker 无镜像加速配置，直连 Docker Hub 会超时
pre_pull_images() {
    if ! is_minikube; then
        return
    fi

    eval "$(minikube docker-env -u)"
    log_info "========== 预拉取镜像（宿主机 Docker → Minikube） =========="

    # 获取 Minikube 中已有的镜像列表（一次查询，避免重复调用）
    local minikube_images
    minikube_images=$(minikube image ls 2>/dev/null)

    for image in "${IMAGES[@]}"; do
        # 检查宿主机是否已有该镜像
        if docker image inspect "$image" &>/dev/null; then
            log_info "宿主机已存在，跳过拉取: $image"
        else
            log_info "拉取: $image"
            docker pull "$image"
        fi

        # 检查 Minikube 中是否已有该镜像
        if echo "$minikube_images" | grep -q "$image"; then
            log_info "Minikube 已存在，跳过加载: $image"
        else
            log_info "加载到 Minikube: $image"
            minikube image load "$image"
        fi
    done

    log_info "========== 镜像预拉取完成 =========="
}

# 在 Minikube 内部构建应用镜像
build_image() {
    log_info "构建应用镜像..."
    if is_minikube; then
        eval "$(minikube docker-env)"
        log_info "使用 Minikube 内部 Docker 构建"
    fi

    cd "$PROJECT_ROOT"
    docker build -t ${APP_NAME}:latest -f deploy/docker/Dockerfile .
    log_info "镜像构建完成: ${APP_NAME}:latest"

    # 切回宿主机 Docker
    if is_minikube; then
        eval "$(minikube docker-env -u)"
    fi
}

main() {
    log_info "========== saas-shortener K8S 一键安装 =========="

    check_command kubectl
    check_command docker
    check_k8s
    cd "$PROJECT_ROOT"

    # 1. 创建 Namespace
    log_info "[1/8] 创建 Namespace: $NAMESPACE"
    kubectl apply -f "$K8S_DIR/namespace.yaml"

    # 2. 预拉取所有第三方镜像
    log_info "[2/8] 预拉取镜像"
    pre_pull_images

    # 3. 构建应用镜像
    log_info "[3/8] 构建应用镜像"
    build_image

    # 4. 部署 PostgreSQL 和 Redis
    log_info "[4/8] 部署 PostgreSQL 和 Redis"
    kubectl apply -f "$K8S_DIR/infra/postgres.yaml"
    kubectl apply -f "$K8S_DIR/infra/redis.yaml"

    # 5. 等待基础设施就绪
    log_info "[5/8] 等待基础设施就绪"
    kubectl wait --for=condition=Ready pod/postgres -n "$NAMESPACE" --timeout=120s
    kubectl wait --for=condition=Ready pod/redis -n "$NAMESPACE" --timeout=60s

    # 6. 部署应用
    log_info "[6/8] 部署应用"
    kubectl apply -f "$K8S_DIR/configmap.yaml"
    kubectl apply -f "$K8S_DIR/secret.yaml"
    kubectl apply -f "$K8S_DIR/deployment.yaml"
    kubectl apply -f "$K8S_DIR/service.yaml"

    # 7. 启用 Ingress 和 HPA
    log_info "[7/8] 启用 Ingress 和 HPA"
    if is_minikube; then
        minikube addons enable metrics-server 2>/dev/null || log_warn "metrics-server 启用失败"
        minikube addons enable ingress 2>/dev/null || log_warn "Ingress 插件启用失败"

        # Minikube Ingress 插件会给镜像加 @sha256 摘要引用，强制从远程拉取验证
        # 本地已有镜像时会因网络问题失败，去掉摘要后可直接使用本地镜像
        # Minikube 启用 Ingress 插件时，会给镜像引用追加 @sha256:xxxx 摘要
        # 例如: kube-webhook-certgen:v1.4.0@sha256:44d1d0e9...
        # 这会强制从远程仓库拉取验证摘要，即使本地已有镜像也会失败（国内网络问题）
        # 解决方案：导出资源 JSON → 去掉 @sha256 摘要 → 删除旧资源 → 重新创建
        log_info "修复 Ingress 镜像摘要引用..."
        # 等待 Ingress 插件资源创建完毕
        sleep 3
        # 遍历 job（admission-create/patch）和 deployment（controller）两种资源
        for resource in job deployment; do
            # 检查该类型资源是否存在
            if kubectl get "$resource" -n ingress-nginx -o name &>/dev/null 2>&1; then
                # 导出资源 JSON，用 sed 去掉所有 @sha256:xxx 摘要引用
                kubectl get "$resource" -n ingress-nginx -o json | \
                    sed 's/@sha256:[a-f0-9]*//g' > /tmp/ingress-${resource}.json
                # 强制删除旧资源（Job 不可变，必须删除重建）
                kubectl delete "$resource" --all -n ingress-nginx --force --grace-period=0 2>/dev/null || true
                # 用去掉摘要的 JSON 重新创建资源，此时会使用本地已有的镜像
                kubectl apply -f /tmp/ingress-${resource}.json 2>/dev/null || true
                # 清理临时文件
                rm -f /tmp/ingress-${resource}.json
            fi
        done

        log_info "等待 Ingress Controller 就绪..."
        kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=controller \
            -n ingress-nginx --timeout=180s 2>/dev/null \
            || log_warn "Ingress Controller 未就绪，可稍后检查: kubectl get pods -n ingress-nginx"
    fi
    kubectl apply -f "$K8S_DIR/ingress.yaml" 2>/dev/null || log_warn "Ingress 配置跳过"
    kubectl apply -f "$K8S_DIR/hpa.yaml" 2>/dev/null || log_warn "HPA 配置跳过"

    # 8. 等待应用就绪
    log_info "[8/8] 等待应用就绪"
    kubectl rollout status deployment/${APP_NAME} -n "$NAMESPACE" --timeout=120s

    log_info "========== 安装完成 =========="
    echo ""
    echo "访问方式："
    echo "  1. 端口转发: kubectl port-forward svc/${APP_NAME}-service 8080:80 -n $NAMESPACE"
    echo "     然后访问 http://localhost:8080"
    echo "  2. Minikube: minikube service ${APP_NAME}-service -n $NAMESPACE"
    echo ""
    echo "查看状态: make k8s-status"
}

main "$@"
