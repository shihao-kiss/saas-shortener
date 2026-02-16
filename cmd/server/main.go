// 云原生 SaaS 短链接服务 - 主入口
//
// 本项目演示了以下云原生/SaaS 核心概念：
// 1. 多租户（Multi-Tenancy）: 共享基础设施，数据按 TenantID 隔离
// 2. 12-Factor App: 配置通过环境变量注入
// 3. 容器化（Docker）: 多阶段构建，最小化镜像体积
// 4. 编排（Kubernetes）: Deployment、Service、Ingress、HPA
// 5. 可观测性：Prometheus 指标 + 结构化日志 + 健康检查
// 6. 优雅关闭（Graceful Shutdown）: 收到信号后等待请求处理完毕再退出
// 7. API 版本管理: /api/v1/ 路径前缀
// 8. 限流（Rate Limiting）: 基于 Redis 的分布式限流
package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/yourname/saas-shortener/internal/config"
	"github.com/yourname/saas-shortener/internal/handler"
	"github.com/yourname/saas-shortener/internal/middleware"
	"github.com/yourname/saas-shortener/internal/repository"
	"github.com/yourname/saas-shortener/internal/service"
)

func main() {
	// ==================== 1. 初始化日志 ====================
	// 生产环境使用 JSON 格式，便于 ELK/Loki 采集
	logger := initLogger()
	defer logger.Sync()

	logger.Info("=== SaaS 短链接服务启动中 ===")

	// ==================== 2. 加载配置 ====================
	cfg := config.Load()
	logger.Info("配置加载完成",
		zap.String("port", cfg.Server.Port),
		zap.String("db_host", cfg.Database.Host),
		zap.String("redis_addr", cfg.Redis.Addr),
	)

	// ==================== 3. 初始化数据库连接 ====================
	db, err := initDatabase(cfg)
	if err != nil {
		logger.Fatal("数据库连接失败", zap.Error(err))
	}
	logger.Info("数据库连接成功")

	// ==================== 4. 初始化 Redis 连接 ====================
	rdb := initRedis(cfg)
	if err := rdb.Ping(context.Background()).Err(); err != nil {
		logger.Fatal("Redis 连接失败", zap.Error(err))
	}
	logger.Info("Redis 连接成功")

	// ==================== 5. 初始化各层组件 ====================
	repo := repository.New(db, rdb, logger)
	svc := service.New(repo, logger)
	h := handler.New(svc, logger)

	// 自动迁移数据库
	if err := repo.AutoMigrate(); err != nil {
		logger.Fatal("数据库迁移失败", zap.Error(err))
	}
	logger.Info("数据库迁移完成")

	// ==================== 6. 配置 HTTP 服务 ====================
	gin.SetMode(gin.ReleaseMode)
	router := gin.New()

	// 注册全局中间件
	router.Use(
		gin.Recovery(),                           // Panic 恢复
		middleware.StructuredLogging(logger),      // 结构化日志
		middleware.PrometheusMetrics(),            // Prometheus 指标
	)

	// 注册路由
	h.RegisterRoutes(router)

	// ==================== 7. 启动 HTTP 服务 ====================
	server := &http.Server{
		Addr:         fmt.Sprintf(":%s", cfg.Server.Port),
		Handler:      router,
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
	}

	// 在 goroutine 中启动服务
	go func() {
		logger.Info("HTTP 服务已启动", zap.String("addr", server.Addr))
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("HTTP 服务启动失败", zap.Error(err))
		}
	}()

	// ==================== 8. 优雅关闭 ====================
	// 云原生最佳实践：收到终止信号后，优雅地关闭服务
	// Kubernetes 在关闭 Pod 时会先发送 SIGTERM 信号，等待一段时间后发送 SIGKILL
	// 我们在收到 SIGTERM 后：
	// 1. 停止接收新请求
	// 2. 等待正在处理的请求完成
	// 3. 关闭数据库和 Redis 连接
	// 4. 退出
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit
	logger.Info("收到退出信号，开始优雅关闭...", zap.String("signal", sig.String()))

	// 创建超时 context
	ctx, cancel := context.WithTimeout(context.Background(), cfg.Server.ShutdownTimeout)
	defer cancel()

	// 关闭 HTTP 服务
	if err := server.Shutdown(ctx); err != nil {
		logger.Error("HTTP 服务关闭异常", zap.Error(err))
	}

	// 关闭 Redis
	if err := rdb.Close(); err != nil {
		logger.Error("Redis 连接关闭异常", zap.Error(err))
	}

	// 关闭数据库
	sqlDB, _ := db.DB()
	if err := sqlDB.Close(); err != nil {
		logger.Error("数据库连接关闭异常", zap.Error(err))
	}

	logger.Info("=== 服务已安全关闭 ===")
}

// initLogger 初始化结构化日志
func initLogger() *zap.Logger {
	// 判断环境，开发环境使用可读格式，生产环境使用 JSON
	env := os.Getenv("APP_ENV")

	var loggerConfig zap.Config
	if env == "production" {
		loggerConfig = zap.NewProductionConfig()
	} else {
		loggerConfig = zap.NewDevelopmentConfig()
		loggerConfig.EncoderConfig.EncodeLevel = zapcore.CapitalColorLevelEncoder
	}

	logger, err := loggerConfig.Build()
	if err != nil {
		panic(fmt.Sprintf("日志初始化失败: %v", err))
	}
	return logger
}

// initDatabase 初始化数据库连接
func initDatabase(cfg *config.Config) (*gorm.DB, error) {
	db, err := gorm.Open(postgres.Open(cfg.Database.DSN()), &gorm.Config{})
	if err != nil {
		return nil, fmt.Errorf("打开数据库连接失败: %w", err)
	}

	// 配置连接池
	// 云原生环境中，合理的连接池配置很重要
	// 过多连接会耗尽数据库资源，过少会导致请求排队
	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("获取底层 DB 失败: %w", err)
	}

	sqlDB.SetMaxOpenConns(25)    // 最大打开连接数
	sqlDB.SetMaxIdleConns(10)    // 最大空闲连接数
	sqlDB.SetConnMaxLifetime(0)  // 连接最大存活时间（0 = 不限制）

	return db, nil
}

// initRedis 初始化 Redis 连接
func initRedis(cfg *config.Config) *redis.Client {
	return redis.NewClient(&redis.Options{
		Addr:     cfg.Redis.Addr,
		Password: cfg.Redis.Password,
		DB:       cfg.Redis.DB,
		PoolSize: 20, // 连接池大小
	})
}
