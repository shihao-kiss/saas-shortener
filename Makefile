# Makefile - 项目构建和管理命令集
# 使用方式：make <target>
# 例如：make run（本地运行），make docker-up（启动完整环境）

APP_NAME := saas-shortener
DOCKER_IMAGE := $(APP_NAME):latest
DOCKER_COMPOSE_FILE := deploy/docker-compose/docker-compose.yaml
DOCKER_COMPOSE_LOCAL := deploy/docker-compose/docker-compose.local.yaml
K8S_DIR := deploy/k8s

# ==================== 本地开发 ====================

## 安装依赖
.PHONY: deps
deps:
	go mod download
	go mod tidy

## 本地运行（需要先启动 PostgreSQL 和 Redis）
.PHONY: run
run:
	go run ./cmd/server

## 运行测试
.PHONY: test
test:
	go test -v -race -cover ./...

## 代码检查
.PHONY: lint
lint:
	golangci-lint run ./...

## 编译
.PHONY: build
build:
	CGO_ENABLED=0 go build -ldflags="-s -w" -o bin/$(APP_NAME) ./cmd/server

# ==================== Docker ====================

## 构建 Docker 镜像
.PHONY: docker-build
docker-build:
	docker build -t $(DOCKER_IMAGE) -f deploy/docker/Dockerfile .

## 启动完整环境 - 云服务器版（带资源限制）
.PHONY: docker-up
docker-up:
	docker compose -f $(DOCKER_COMPOSE_FILE) up -d --build

## 启动完整环境 - 本地开发版（无资源限制，推荐本地使用）
.PHONY: local-up
local-up:
	docker compose -f $(DOCKER_COMPOSE_LOCAL) up -d --build

## 停止 Docker Compose 环境
.PHONY: docker-down
docker-down:
	docker compose -f $(DOCKER_COMPOSE_LOCAL) down

## 查看日志
.PHONY: docker-logs
docker-logs:
	docker compose -f $(DOCKER_COMPOSE_LOCAL) logs -f app

## 查看所有服务日志
.PHONY: docker-logs-all
docker-logs-all:
	docker compose -f $(DOCKER_COMPOSE_LOCAL) logs -f

## 只启动基础设施（数据库 + Redis + 监控，本地 go run 调试用）
.PHONY: infra-up
infra-up:
	docker compose -f $(DOCKER_COMPOSE_LOCAL) up -d postgres redis prometheus grafana

## 停止基础设施
.PHONY: infra-down
infra-down:
	docker compose -f $(DOCKER_COMPOSE_LOCAL) down

## 运行 API 测试脚本（PowerShell）
.PHONY: test-api
test-api:
	powershell -ExecutionPolicy Bypass -File scripts/test-api.ps1

# ==================== Kubernetes ====================

## 一键部署到 K8S/Minikube（含构建镜像、PostgreSQL、Redis、应用）
.PHONY: k8s-deploy
k8s-deploy:
	./deploy/k8s/install.sh

## 一键卸载（删除 saas-shortener 命名空间及所有资源）
.PHONY: k8s-uninstall
k8s-uninstall:
	./deploy/k8s/uninstall.sh

## 仅应用 K8S 配置（适用于已有 PostgreSQL/Redis 的环境）
.PHONY: k8s-apply
k8s-apply:
	kubectl apply -f $(K8S_DIR)/namespace.yaml
	kubectl apply -f $(K8S_DIR)/configmap.yaml
	kubectl apply -f $(K8S_DIR)/secret.yaml
	kubectl apply -f $(K8S_DIR)/deployment.yaml
	kubectl apply -f $(K8S_DIR)/service.yaml
	kubectl apply -f $(K8S_DIR)/ingress.yaml
	kubectl apply -f $(K8S_DIR)/hpa.yaml

## 删除 K8S 配置（仅删除 YAML 定义的资源，不含 namespace）
.PHONY: k8s-delete
k8s-delete:
	kubectl delete -f $(K8S_DIR)/infra/ --ignore-not-found
	kubectl delete -f $(K8S_DIR)/configmap.yaml --ignore-not-found
	kubectl delete -f $(K8S_DIR)/secret.yaml --ignore-not-found
	kubectl delete -f $(K8S_DIR)/deployment.yaml --ignore-not-found
	kubectl delete -f $(K8S_DIR)/service.yaml --ignore-not-found
	kubectl delete -f $(K8S_DIR)/ingress.yaml --ignore-not-found
	kubectl delete -f $(K8S_DIR)/hpa.yaml --ignore-not-found

## 查看 Kubernetes 资源状态
.PHONY: k8s-status
k8s-status:
	@echo "=== Pods ==="
	kubectl get pods -n saas-shortener
	@echo "\n=== Services ==="
	kubectl get svc -n saas-shortener
	@echo "\n=== HPA ==="
	kubectl get hpa -n saas-shortener
	@echo "\n=== Ingress ==="
	kubectl get ingress -n saas-shortener

# ==================== 测试 API ====================

## 创建测试租户
.PHONY: test-create-tenant
test-create-tenant:
	curl -s -X POST http://localhost:8080/api/v1/tenants \
		-H "Content-Type: application/json" \
		-d '{"name": "测试公司", "plan": "free"}' | python -m json.tool

## 创建短链接（需要替换 YOUR_API_KEY）
.PHONY: test-create-url
test-create-url:
	@echo "请先设置环境变量 API_KEY，例如：export API_KEY=your_api_key_here"
	curl -s -X POST http://localhost:8080/api/v1/urls \
		-H "Content-Type: application/json" \
		-H "X-API-Key: $(API_KEY)" \
		-d '{"url": "https://github.com"}' | python -m json.tool

## 查看 Prometheus 指标
.PHONY: test-metrics
test-metrics:
	curl -s http://localhost:8080/metrics | head -50

## 健康检查
.PHONY: test-health
test-health:
	curl -s http://localhost:8080/healthz | python -m json.tool
	curl -s http://localhost:8080/readyz | python -m json.tool

# ==================== 帮助 ====================

.PHONY: help
help:
	@echo "=== SaaS 短链接服务 - 可用命令 ==="
	@echo ""
	@echo "本地开发:"
	@echo "  make deps          - 安装依赖"
	@echo "  make run           - 本地运行"
	@echo "  make test          - 运行测试"
	@echo "  make build         - 编译"
	@echo ""
	@echo "Docker:"
	@echo "  make local-up      - 启动完整环境(本地开发，推荐)"
	@echo "  make docker-up     - 启动完整环境(云服务器，带资源限制)"
	@echo "  make docker-down   - 停止环境"
	@echo "  make docker-logs   - 查看应用日志"
	@echo "  make infra-up      - 只启动基础设施(配合 go run 调试)"
	@echo "  make test-api      - 运行 API 测试脚本"
	@echo ""
	@echo "Kubernetes:"
	@echo "  make k8s-deploy    - 一键部署到 Minikube（含镜像、数据库、应用）"
	@echo "  make k8s-uninstall - 一键卸载（删除命名空间及所有资源）"
	@echo "  make k8s-apply     - 仅应用 K8s 配置（已有数据库时用）"
	@echo "  make k8s-delete    - 删除 K8s 配置"
	@echo "  make k8s-status    - 查看 K8s 状态"
	@echo ""
	@echo "测试:"
	@echo "  make test-create-tenant  - 创建测试租户"
	@echo "  make test-create-url     - 创建短链接"
	@echo "  make test-metrics        - 查看指标"
	@echo "  make test-health         - 健康检查"

.DEFAULT_GOAL := help
