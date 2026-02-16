package middleware

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// Prometheus 指标定义
// 云原生可观测性的三大支柱之一：Metrics（指标）
// Prometheus 是 Kubernetes 生态中最主流的监控方案
//
// 指标类型说明：
// - Counter: 只增不减的计数器（如请求总数、错误总数）
// - Histogram: 直方图（如请求延迟分布）
// - Gauge: 可增可减的仪表盘（如当前活跃连接数）
var (
	// HTTP 请求总数 - 按方法、路径、状态码、租户分组
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "HTTP 请求总数",
		},
		[]string{"method", "path", "status", "tenant_id"},
	)

	// HTTP 请求延迟 - 直方图
	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP 请求延迟（秒）",
			Buckets: prometheus.DefBuckets, // 默认分桶: .005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10
		},
		[]string{"method", "path"},
	)

	// 短链接创建总数 - 按租户分组
	urlCreatedTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "shorturl_created_total",
			Help: "短链接创建总数",
		},
		[]string{"tenant_id", "plan"},
	)

	// 短链接重定向总数
	urlRedirectsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "shorturl_redirects_total",
			Help: "短链接重定向总数",
		},
		[]string{"tenant_id"},
	)

	// 限流触发次数
	rateLimitHitsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "rate_limit_hits_total",
			Help: "限流触发次数",
		},
		[]string{"tenant_id", "plan"},
	)
)

// PrometheusMetrics Prometheus 指标中间件
// 自动记录每个 HTTP 请求的指标
func PrometheusMetrics() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()

		// 处理请求
		c.Next()

		// 请求完成后记录指标
		duration := time.Since(start).Seconds()
		status := strconv.Itoa(c.Writer.Status())
		path := c.FullPath() // 使用路由模板路径，避免高基数（如 /abc123 → /:code）
		if path == "" {
			path = "unknown"
		}

		// 获取租户 ID（可能为空，公开接口没有租户信息）
		tenantID := ""
		if tenant := GetTenantFromContext(c); tenant != nil {
			tenantID = tenant.ID.String()
		}

		httpRequestsTotal.WithLabelValues(c.Request.Method, path, status, tenantID).Inc()
		httpRequestDuration.WithLabelValues(c.Request.Method, path).Observe(duration)
	}
}

// RecordURLCreated 记录短链接创建指标
func RecordURLCreated(tenantID, plan string) {
	urlCreatedTotal.WithLabelValues(tenantID, plan).Inc()
}

// RecordRedirect 记录重定向指标
func RecordRedirect(tenantID string) {
	urlRedirectsTotal.WithLabelValues(tenantID).Inc()
}

// RecordRateLimitHit 记录限流触发指标
func RecordRateLimitHit(tenantID, plan string) {
	rateLimitHitsTotal.WithLabelValues(tenantID, plan).Inc()
}
