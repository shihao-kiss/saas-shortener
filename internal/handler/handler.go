// Package handler HTTP 请求处理器
// 职责：接收 HTTP 请求，调用 Service 层处理业务逻辑，返回 HTTP 响应
// 遵循 RESTful API 设计规范
package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/zap"

	"github.com/yourname/saas-shortener/internal/middleware"
	"github.com/yourname/saas-shortener/internal/model"
	"github.com/yourname/saas-shortener/internal/service"
)

// Handler HTTP 处理器
type Handler struct {
	svc    *service.Service
	logger *zap.Logger
}

// New 创建 Handler 实例
func New(svc *service.Service, logger *zap.Logger) *Handler {
	return &Handler{
		svc:    svc,
		logger: logger,
	}
}

// RegisterRoutes 注册路由
// 云原生 API 设计要点：
// 1. /healthz - Kubernetes 存活探针（Liveness Probe）
// 2. /readyz  - Kubernetes 就绪探针（Readiness Probe）
// 3. /metrics - Prometheus 指标采集端点
// 4. /api/v1/ - 版本化的 API（SaaS 最佳实践：API 版本管理）
func (h *Handler) RegisterRoutes(r *gin.Engine) {
	// ==================== 基础设施端点（无需认证）====================

	// Kubernetes 健康检查探针
	// Liveness Probe: 判断容器是否存活，失败则重启容器
	r.GET("/healthz", h.HealthCheck)

	// Readiness Probe: 判断容器是否就绪（能否接收流量），失败则从 Service 中移除
	r.GET("/readyz", h.ReadinessCheck)

	// Prometheus 指标端点 - Prometheus 会定期拉取这个端点的数据
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// ==================== 公开端点（无需认证）====================

	// 短链接重定向（这是访问量最大的端点）
	r.GET("/:code", h.Redirect)

	// 租户注册（创建新租户获取 API Key）
	r.POST("/api/v1/tenants", h.CreateTenant)

	// ==================== 需要认证的 API ====================
	// 使用中间件链：认证 → 限流 → 处理请求
	api := r.Group("/api/v1")
	api.Use(
		middleware.TenantAuth(h.svc, h.logger),   // 第1步：认证租户
		middleware.RateLimit(h.svc, h.logger),     // 第2步：检查限流
	)
	{
		// 短链接 CRUD
		api.POST("/urls", h.CreateShortURL)       // 创建短链接
		api.GET("/urls", h.ListShortURLs)          // 查询短链接列表
		api.GET("/stats", h.GetStats)              // 获取统计信息
	}
}

// ==================== 健康检查处理器 ====================

// HealthCheck 存活探针
// Kubernetes Liveness Probe 会定期调用此接口
// 如果返回非 200，K8s 会重启 Pod
func (h *Handler) HealthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status": "ok",
		"service": "saas-shortener",
	})
}

// ReadinessCheck 就绪探针
// Kubernetes Readiness Probe 会定期调用此接口
// 如果返回非 200，K8s 不会将流量路由到该 Pod
// 与 Liveness 的区别：Readiness 检查依赖服务（DB、Redis）是否可用
func (h *Handler) ReadinessCheck(c *gin.Context) {
	if err := h.svc.HealthCheck(c.Request.Context()); err != nil {
		h.logger.Error("就绪检查失败", zap.Error(err))
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "not ready",
			"error":  err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"status": "ready",
	})
}

// ==================== 租户管理处理器 ====================

// CreateTenant 创建租户（注册）
// POST /api/v1/tenants
func (h *Handler) CreateTenant(c *gin.Context) {
	var req model.CreateTenantRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "参数错误",
			"message": err.Error(),
		})
		return
	}

	resp, err := h.svc.CreateTenant(c.Request.Context(), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "创建失败",
			"message": err.Error(),
		})
		return
	}

	c.JSON(http.StatusCreated, resp)
}

// ==================== 短链接处理器 ====================

// CreateShortURL 创建短链接
// POST /api/v1/urls
func (h *Handler) CreateShortURL(c *gin.Context) {
	tenant := middleware.GetTenantFromContext(c)
	if tenant == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "未认证"})
		return
	}

	var req model.CreateShortURLRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "参数错误",
			"message": err.Error(),
		})
		return
	}

	resp, err := h.svc.CreateShortURL(c.Request.Context(), tenant.ID, &req)
	if err != nil {
		if err == service.ErrQuotaExceeded {
			c.JSON(http.StatusForbidden, gin.H{
				"error":   "配额不足",
				"message": err.Error(),
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "创建失败",
			"message": err.Error(),
		})
		return
	}

	// 记录 Prometheus 指标
	middleware.RecordURLCreated(tenant.ID.String(), tenant.Plan)

	c.JSON(http.StatusCreated, resp)
}

// ListShortURLs 查询短链接列表
// GET /api/v1/urls?page=1&page_size=20
func (h *Handler) ListShortURLs(c *gin.Context) {
	tenant := middleware.GetTenantFromContext(c)
	if tenant == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "未认证"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	urls, total, err := h.svc.ListShortURLs(c.Request.Context(), tenant.ID, page, pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "查询失败",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data":      urls,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// GetStats 获取统计信息
// GET /api/v1/stats
func (h *Handler) GetStats(c *gin.Context) {
	tenant := middleware.GetTenantFromContext(c)
	if tenant == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "未认证"})
		return
	}

	stats, err := h.svc.GetStats(c.Request.Context(), tenant.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "查询失败",
		})
		return
	}

	c.JSON(http.StatusOK, stats)
}

// Redirect 短链接重定向
// GET /:code
func (h *Handler) Redirect(c *gin.Context) {
	code := c.Param("code")

	// 排除基础设施路径
	if code == "healthz" || code == "readyz" || code == "metrics" || code == "api" {
		c.Next()
		return
	}

	originalURL, err := h.svc.Redirect(
		c.Request.Context(),
		code,
		c.ClientIP(),
		c.Request.UserAgent(),
		c.Request.Referer(),
	)
	if err != nil {
		if err == service.ErrURLNotFound || err == service.ErrURLExpired {
			c.JSON(http.StatusNotFound, gin.H{
				"error": "链接不存在或已过期",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "服务器错误",
		})
		return
	}

	// 302 临时重定向（也可以用 301 永久重定向，但 302 更灵活）
	c.Redirect(http.StatusFound, originalURL)
}
