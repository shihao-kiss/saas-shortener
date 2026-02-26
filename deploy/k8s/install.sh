#!/usr/bin/env bash
# =============================================================================
# saas-shortener K8S 一键安装脚本
# 功能：构建应用镜像 → 部署基础设施 → 部署应用 → 启用 Ingress/HPA
# 前置：minikube 已启动且已配置代理（可访问 Docker Hub）
# 用法：make k8s-deploy 或 bash deploy/k8s/install.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
K8S_DIR="$SCRIPT_DIR"
APP_NAME="saas-shortener"
NAMESPACE="saas-shortener"

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

# 在 Minikube 内部构建应用镜像
build_image() {
    log_info "构建应用镜像..."
    if is_minikube; then
        eval "$(minikube docker-env)"
        log_info "使用 Minikube 内部 Docker 构建"
    fi

    cd "$PROJECT_ROOT"

    # BuildKit 的 FROM 镜像解析不走 Docker daemon 代理，也不受 --build-arg 影响
    # 预拉取基础镜像，让 BuildKit 直接使用本地缓存
    log_info "预拉取 Dockerfile 基础镜像..."
    docker pull golang:1.22-alpine
    docker pull alpine:3.19

    docker build -t ${APP_NAME}:latest -f deploy/docker/Dockerfile .
    log_info "镜像构建完成: ${APP_NAME}:latest"

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
    log_info "[1/7] 创建 Namespace: $NAMESPACE"
    kubectl apply -f "$K8S_DIR/namespace.yaml"

    # 2. 构建应用镜像
    log_info "[2/7] 构建应用镜像"
    build_image

    # 3. 部署 PostgreSQL 和 Redis
    log_info "[3/7] 部署 PostgreSQL 和 Redis"
    kubectl apply -f "$K8S_DIR/infra/postgres.yaml"
    kubectl apply -f "$K8S_DIR/infra/redis.yaml"

    # 4. 等待基础设施就绪
    log_info "[4/7] 等待基础设施就绪"
    kubectl wait --for=condition=Ready pod/postgres -n "$NAMESPACE" --timeout=180s
    kubectl wait --for=condition=Ready pod/redis -n "$NAMESPACE" --timeout=120s

    # 5. 部署应用
    log_info "[5/7] 部署应用"
    kubectl apply -f "$K8S_DIR/configmap.yaml"
    kubectl apply -f "$K8S_DIR/secret.yaml"
    kubectl apply -f "$K8S_DIR/deployment.yaml"
    kubectl apply -f "$K8S_DIR/service.yaml"

    # 6. 启用 Ingress 和 HPA
    log_info "[6/7] 启用 Ingress 和 HPA"
    if is_minikube; then
        minikube addons enable metrics-server 2>/dev/null || log_warn "metrics-server 启用失败"
        minikube addons enable ingress || log_warn "Ingress 插件启用失败"
    fi
    kubectl apply -f "$K8S_DIR/ingress.yaml" 2>/dev/null || log_warn "Ingress 配置跳过"
    kubectl apply -f "$K8S_DIR/hpa.yaml" 2>/dev/null || log_warn "HPA 配置跳过"

    # 7. 等待应用就绪
    log_info "[7/7] 等待应用就绪"
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
