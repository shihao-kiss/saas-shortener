#!/usr/bin/env bash
# =============================================================================
# saas-shortener K8S 一键安装脚本
#
# 执行流程：
#   环境检查 → CoreDNS 修复 → 构建镜像 → 部署基础设施 → 部署应用 → 启用插件
#
# 前置条件：
#   - minikube 已启动且已配置代理（可访问 Docker Hub）
#   - kubectl、docker 已安装
#
# 用法：
#   make k8s-deploy
#   bash deploy/k8s/install.sh
# =============================================================================

set -e

# ==================== 常量 ====================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
K8S_DIR="$SCRIPT_DIR"

APP_NAME="saas-shortener"
NAMESPACE="saas-shortener"
DEPLOY_TIMEOUT="120s"

# ==================== 日志 ====================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${GREEN}[$1/$TOTAL_STEPS]${NC} $2"; }

# ==================== 前置检查 ====================

preflight_check() {
    local missing=0
    for cmd in kubectl docker; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "$cmd 未安装"
            missing=1
        fi
    done
    [[ $missing -eq 1 ]] && exit 1

    if ! kubectl cluster-info &>/dev/null; then
        log_error "无法连接 K8S 集群，请确保 minikube 已启动: minikube start"
        exit 1
    fi
}

is_minikube() {
    command -v minikube &>/dev/null && minikube status &>/dev/null 2>&1
}

# ==================== 环境修复 ====================

# CoreDNS 新版本以非 root 运行，可能缺少 NET_BIND_SERVICE 能力
# 导致无法绑定 53 端口 → 集群 DNS 不可用 → Pod 无法解析 Service 域名
fix_coredns_if_needed() {
    local running_count
    running_count=$(kubectl get pods -n kube-system -l k8s-app=kube-dns \
        --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)

    [[ "$running_count" -gt 0 ]] && return 0

    log_warn "CoreDNS 未就绪，尝试修复..."

    # 使用 JSON patch 精确替换（strategic merge 对数组字段和布尔值可能不生效）
    # 1. 允许特权提升 + 添加 NET_BIND_SERVICE 能力 + 清空 drop 列表
    # 2. 以 root 用户运行（非 root 用户即使有 NET_BIND_SERVICE 也可能无法绑定 53 端口）
    kubectl -n kube-system patch deployment coredns --type='json' -p='[
      {"op": "replace", "path": "/spec/template/spec/containers/0/securityContext/allowPrivilegeEscalation", "value": true},
      {"op": "replace", "path": "/spec/template/spec/containers/0/securityContext/capabilities/drop", "value": []},
      {"op": "add", "path": "/spec/template/spec/containers/0/securityContext/runAsUser", "value": 0},
      {"op": "add", "path": "/spec/template/spec/containers/0/securityContext/runAsNonRoot", "value": false}
    ]' 2>/dev/null || true

    kubectl rollout restart deployment/coredns -n kube-system 2>/dev/null || true
    kubectl rollout status deployment/coredns -n kube-system --timeout=60s 2>/dev/null \
        || log_warn "CoreDNS 未就绪，可能影响 DNS 解析"
}

# ==================== 镜像构建 ====================

# 在 Minikube 内部的 Docker 中构建，K8s Pod 可直接使用镜像
# 注意：BuildKit 的 FROM 解析不走 Docker daemon 代理，需要预拉取基础镜像
build_app_image() {
    if is_minikube; then
        eval "$(minikube docker-env)"
        log_info "已切换到 Minikube Docker 环境"
    fi

    cd "$PROJECT_ROOT"

    log_info "预拉取 Dockerfile 基础镜像（BuildKit 不走 daemon 代理）..."
    docker pull golang:1.22-alpine
    docker pull alpine:3.19

    log_info "构建 ${APP_NAME}:latest ..."
    docker build -t "${APP_NAME}:latest" -f deploy/docker/Dockerfile .

    if is_minikube; then
        eval "$(minikube docker-env -u)"
    fi
}

# ==================== K8S 资源部署 ====================

deploy_infra() {
    kubectl apply -f "$K8S_DIR/infra/postgres.yaml"
    kubectl apply -f "$K8S_DIR/infra/redis.yaml"

    log_info "等待 PostgreSQL 就绪..."
    kubectl wait --for=condition=Ready pod/postgres -n "$NAMESPACE" --timeout=180s
    log_info "等待 Redis 就绪..."
    kubectl wait --for=condition=Ready pod/redis -n "$NAMESPACE" --timeout=120s
}

deploy_app() {
    kubectl apply -f "$K8S_DIR/configmap.yaml"
    kubectl apply -f "$K8S_DIR/secret.yaml"
    kubectl apply -f "$K8S_DIR/deployment.yaml"
    kubectl apply -f "$K8S_DIR/service.yaml"
}

enable_addons() {
    if is_minikube; then
        minikube addons enable metrics-server 2>/dev/null || log_warn "metrics-server 启用失败"
        minikube addons enable ingress          2>/dev/null || log_warn "Ingress 插件启用失败"
    fi
    kubectl apply -f "$K8S_DIR/ingress.yaml" 2>/dev/null || log_warn "Ingress 配置跳过"
    kubectl apply -f "$K8S_DIR/hpa.yaml"     2>/dev/null || log_warn "HPA 配置跳过"
}

print_access_info() {
    echo ""
    echo "访问方式："
    echo "  1. 端口转发: kubectl port-forward svc/${APP_NAME}-service 8080:80 -n $NAMESPACE"
    echo "     然后访问 http://localhost:8080"
    echo "  2. Minikube: minikube service ${APP_NAME}-service -n $NAMESPACE"
    echo ""
    echo "查看状态: make k8s-status"
}

# ==================== 主流程 ====================

TOTAL_STEPS=7

main() {
    log_info "========== ${APP_NAME} K8S 一键安装 =========="

    preflight_check
    cd "$PROJECT_ROOT"

    fix_coredns_if_needed

    log_step 1 "创建 Namespace: $NAMESPACE"
    kubectl apply -f "$K8S_DIR/namespace.yaml"

    log_step 2 "构建应用镜像"
    build_app_image

    log_step 3 "部署 PostgreSQL 和 Redis"
    deploy_infra

    log_step 4 "部署应用"
    deploy_app

    log_step 5 "启用 Ingress 和 HPA"
    enable_addons

    log_step 6 "等待应用就绪"
    kubectl rollout status deployment/${APP_NAME} -n "$NAMESPACE" --timeout=${DEPLOY_TIMEOUT}

    log_step 7 "完成"
    log_info "========== 安装完成 =========="
    print_access_info
}

main "$@"
