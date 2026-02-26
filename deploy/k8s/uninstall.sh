#!/usr/bin/env bash
# =============================================================================
# saas-shortener K8S 一键卸载脚本
# 功能：删除 saas-shortener 命名空间及其下所有资源（应用、PostgreSQL、Redis、配置等）
# 用法：在项目根目录执行 make k8s-uninstall 或 ./deploy/k8s/uninstall.sh
# 免确认：K8S_UNINSTALL_FORCE=1 ./deploy/k8s/uninstall.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="saas-shortener"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

main() {
    log_info "========== saas-shortener K8S 一键卸载 =========="

    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl 未安装"
        exit 1
    fi

    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_warn "命名空间 $NAMESPACE 不存在，无需卸载"
        exit 0
    fi

    # 确认操作（除非设置了 K8S_UNINSTALL_FORCE）
    if [[ "${K8S_UNINSTALL_FORCE}" != "1" ]] && [[ -t 0 ]]; then
        echo ""
        log_warn "即将删除命名空间 $NAMESPACE 及其下所有资源："
        echo "  - 应用 Deployment、Service、Ingress、HPA"
        echo "  - PostgreSQL、Redis"
        echo "  - ConfigMap、Secret"
        echo ""
        read -p "确认卸载？(y/N): " -r
        if [[ ! "$REPLY" =~ ^[yY]$ ]]; then
            log_info "已取消"
            exit 0
        fi
    fi

    log_info "删除命名空间 $NAMESPACE..."
    kubectl delete namespace "$NAMESPACE" --timeout=120s --ignore-not-found

    log_info "========== 卸载完成 =========="
}

main "$@"
