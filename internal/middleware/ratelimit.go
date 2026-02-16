package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"

	"github.com/yourname/saas-shortener/internal/service"
)

// RateLimit 租户级别限流中间件
// SaaS 重要功能：根据租户的套餐等级，限制 API 调用频率
// 这确保了：
// 1. 防止单个租户过度使用资源影响其他租户
// 2. 推动免费用户升级到付费套餐
// 3. 保护系统整体稳定性
//
// 实现原理：使用 Redis 的 Sorted Set 实现滑动窗口计数器
// 这是分布式限流的标准方案，适用于多实例部署的云原生环境
func RateLimit(svc *service.Service, logger *zap.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		tenant := GetTenantFromContext(c)
		if tenant == nil {
			c.Next()
			return
		}

		// 检查限流
		allowed, err := svc.CheckRateLimit(c.Request.Context(), tenant.ID, tenant.RateLimit)
		if err != nil {
			logger.Error("限流检查失败",
				zap.String("tenant_id", tenant.ID.String()),
				zap.Error(err),
			)
			// 限流检查失败时放行（fail-open），避免因 Redis 故障导致所有请求被拒绝
			c.Next()
			return
		}

		if !allowed {
			logger.Warn("租户触发限流",
				zap.String("tenant_id", tenant.ID.String()),
				zap.String("plan", tenant.Plan),
				zap.Int("rate_limit", tenant.RateLimit),
			)

			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error":   "请求过于频繁",
				"message": "已超过每分钟请求限制，请稍后重试或升级套餐",
				"plan":    tenant.Plan,
				"limit":   tenant.RateLimit,
			})
			return
		}

		c.Next()
	}
}
