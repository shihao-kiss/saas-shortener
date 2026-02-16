package middleware

import (
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// StructuredLogging 结构化日志中间件
// 云原生可观测性三大支柱之二：Logging（日志）
//
// 为什么要用结构化日志（JSON 格式）？
// 1. 便于日志采集系统（如 ELK/Loki）解析和索引
// 2. 便于根据字段过滤和搜索（如按 tenant_id 过滤）
// 3. 在 Kubernetes 中，Pod 的标准输出会被日志系统自动采集
//
// 典型的云原生日志架构：
// Pod stdout → Fluentd/Filebeat → Elasticsearch/Loki → Kibana/Grafana
func StructuredLogging(logger *zap.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		query := c.Request.URL.RawQuery

		// 处理请求
		c.Next()

		// 请求完成后记录日志
		latency := time.Since(start)
		status := c.Writer.Status()

		// 构建日志字段
		fields := []zap.Field{
			zap.Int("status", status),
			zap.String("method", c.Request.Method),
			zap.String("path", path),
			zap.String("query", query),
			zap.String("ip", c.ClientIP()),
			zap.String("user_agent", c.Request.UserAgent()),
			zap.Duration("latency", latency),
			zap.Int("body_size", c.Writer.Size()),
		}

		// 如果有租户信息，添加到日志中
		// 这样可以在日志系统中按租户过滤日志
		if tenant := GetTenantFromContext(c); tenant != nil {
			fields = append(fields,
				zap.String("tenant_id", tenant.ID.String()),
				zap.String("tenant_name", tenant.Name),
				zap.String("plan", tenant.Plan),
			)
		}

		// 如果有错误，记录错误信息
		if len(c.Errors) > 0 {
			fields = append(fields, zap.String("errors", c.Errors.String()))
		}

		// 根据状态码选择日志级别
		switch {
		case status >= 500:
			logger.Error("服务器错误", fields...)
		case status >= 400:
			logger.Warn("客户端错误", fields...)
		default:
			logger.Info("请求完成", fields...)
		}
	}
}
