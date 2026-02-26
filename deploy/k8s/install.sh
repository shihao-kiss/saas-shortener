#!/usr/bin/env bash
# =============================================================================
# saas-shortener K8S 一键安装脚本
# 功能：构建镜像 → 创建 Namespace → 部署 PostgreSQL/Redis → 部署应用 → 启用 Ingress/HPA
# 前置：minikube 已启动 (minikube start)，或已有可用的 K8S 集群
# 用法：在项目根目录执行 make k8s-deploy 或 ./deploy/k8s/install.sh
# =============================================================================

set -e

# 获取脚本所在目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
K8S_DIR="$SCRIPT_DIR"
APP_NAME="saas-shortener"
NAMESPACE="saas-shortener"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "$1 未安装，请先安装"
        exit 1
    fi
}

# 检查 kubectl 连接
check_k8s() {
    if ! kubectl cluster-info &>/dev/null; then
        log_error "无法连接 K8S 集群，请确保 minikube 已启动: minikube start"
        exit 1
    fi
}

# 构建 Docker 镜像（Minikube 环境）
build_image() {
    log_info "构建应用镜像..."
    if command -v minikube &>/dev/null && minikube status &>/dev/null 2>&1; then
        eval "$(minikube docker-env)"
        log_info "使用 Minikube 内部 Docker 构建镜像"
    fi

    cd "$PROJECT_ROOT"
    docker build -t ${APP_NAME}:latest -f deploy/docker/Dockerfile .
    log_info "镜像构建完成: ${APP_NAME}:latest"
}

# 部署 PostgreSQL 和 Redis
deploy_infra() {
    log_info "部署 PostgreSQL 和 Redis..."
    kubectl apply -f "$K8S_DIR/infra/postgres.yaml"
    kubectl apply -f "$K8S_DIR/infra/redis.yaml"
}

# 主流程
main() {
    log_info "========== saas-shortener K8S 一键安装 =========="

    check_command kubectl
    check_command docker
    check_k8s

    cd "$PROJECT_ROOT"

    # 1. 创建 Namespace
    log_info "创建 Namespace: $NAMESPACE"
    kubectl apply -f "$K8S_DIR/namespace.yaml"

    # 2. 构建镜像
    build_image

    # 3. 部署 PostgreSQL 和 Redis
    deploy_infra

    # 4. 等待数据库就绪
    log_info "等待 PostgreSQL 就绪..."
    kubectl wait --for=condition=Ready pod/postgres -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
    log_info "等待 Redis 就绪..."
    kubectl wait --for=condition=Ready pod/redis -n "$NAMESPACE" --timeout=60s 2>/dev/null || true

    # 5. 应用 K8S 配置
    log_info "应用 ConfigMap 和 Secret..."
    kubectl apply -f "$K8S_DIR/configmap.yaml"
    kubectl apply -f "$K8S_DIR/secret.yaml"

    log_info "部署应用..."
    kubectl apply -f "$K8S_DIR/deployment.yaml"
    kubectl apply -f "$K8S_DIR/service.yaml"

    # 6. 启用 Minikube 插件并应用 Ingress/HPA
    if command -v minikube &>/dev/null && minikube status &>/dev/null 2>&1; then
        log_info "启用 Minikube Ingress 插件..."
        minikube addons enable ingress 2>/dev/null || true
        log_info "启用 Minikube metrics-server 插件..."
        minikube addons enable metrics-server 2>/dev/null || true
    fi

    kubectl apply -f "$K8S_DIR/ingress.yaml"
    kubectl apply -f "$K8S_DIR/hpa.yaml"

    # 7. 等待应用就绪
    log_info "等待应用 Pod 就绪..."
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
