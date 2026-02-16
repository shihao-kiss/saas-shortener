// Package middleware 实现 HTTP 中间件
// 云原生 SaaS 中间件是非常关键的组件，负责：
// 1. 租户识别与认证（从请求中提取租户信息）
// 2. 限流（根据租户套餐限制 API 调用频率）
// 3. 可观测性（记录指标、日志、链路追踪）
package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"

	"github.com/yourname/saas-shortener/internal/model"
	"github.com/yourname/saas-shortener/internal/service"
)

// 上下文 key 常量
const (
	TenantKey = "tenant" // Gin Context 中存储租户信息的 key
)

// TenantAuth 租户认证中间件
// SaaS 核心中间件：从请求 Header 中提取 API Key，识别并认证租户
// 每个 API 请求都必须携带 X-API-Key 头部
//
// 工作流程：
// 请求 → 提取 API Key → 查询租户 → 注入到 Context → 后续 Handler 使用
func TenantAuth(svc *service.Service, logger *zap.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		// 从 Header 中提取 API Key
		// 支持两种格式：
		// 1. X-API-Key: <key>
		// 2. Authorization: Bearer <key>
		apiKey := c.GetHeader("X-API-Key")
		if apiKey == "" {
			auth := c.GetHeader("Authorization")
			if strings.HasPrefix(auth, "Bearer ") {
				apiKey = strings.TrimPrefix(auth, "Bearer ")
			}
		}

		if apiKey == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error":   "未授权",
				"message": "请在 Header 中提供 X-API-Key 或 Authorization: Bearer <key>",
			})
			return
		}

		// 认证租户
		tenant, err := svc.AuthenticateTenant(c.Request.Context(), apiKey)
		if err != nil {
			logger.Warn("租户认证失败",
				zap.String("ip", c.ClientIP()),
				zap.Error(err),
			)
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error":   "认证失败",
				"message": "无效的 API Key",
			})
			return
		}

		// 将租户信息注入到 Gin Context 中
		// 后续 Handler 可通过 GetTenantFromContext() 获取
		c.Set(TenantKey, tenant)

		// 记录结构化日志
		logger.Debug("租户认证成功",
			zap.String("tenant_id", tenant.ID.String()),
			zap.String("tenant_name", tenant.Name),
			zap.String("plan", tenant.Plan),
		)

		c.Next()
	}
}

// GetTenantFromContext 从 Gin Context 中获取当前租户信息
// Handler 中使用此函数获取认证后的租户
func GetTenantFromContext(c *gin.Context) *model.Tenant {
	tenant, exists := c.Get(TenantKey)
	if !exists {
		return nil
	}
	return tenant.(*model.Tenant)
}
