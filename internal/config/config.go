// Package config 实现了 12-Factor App 的配置管理
// 云原生最佳实践：所有配置通过环境变量注入，而非硬编码或配置文件
// 在 Kubernetes 中，这些环境变量通过 ConfigMap 和 Secret 注入到 Pod 中
package config

import (
	"os"
	"strconv"
	"time"
)

// Config 应用全局配置
// SaaS 关键点：配置中包含多租户相关配置（默认限流等）
type Config struct {
	// 服务基础配置
	Server ServerConfig

	// 数据库配置 - 云原生通常使用托管数据库（如 AWS RDS、阿里云 RDS）
	Database DatabaseConfig

	// Redis 配置 - 用于缓存和分布式限流
	Redis RedisConfig

	// SaaS 多租户配置
	Tenant TenantConfig
}

type ServerConfig struct {
	Port            string        // 服务监听端口
	ReadTimeout     time.Duration // 读取超时
	WriteTimeout    time.Duration // 写入超时
	ShutdownTimeout time.Duration // 优雅关闭超时
}

type DatabaseConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	DBName   string
	SSLMode  string
}

// DSN 返回 PostgreSQL 连接字符串
func (d DatabaseConfig) DSN() string {
	return "host=" + d.Host +
		" port=" + d.Port +
		" user=" + d.User +
		" password=" + d.Password +
		" dbname=" + d.DBName +
		" sslmode=" + d.SSLMode
}

type RedisConfig struct {
	Addr     string
	Password string
	DB       int
}

type TenantConfig struct {
	DefaultRateLimit int // 每个租户的默认限流（请求/分钟）
	MaxURLsPerTenant int // 每个租户最大 URL 数量（免费套餐）
}

// Load 从环境变量加载配置
// 云原生原则：配置与代码分离，通过环境变量或挂载卷注入
func Load() *Config {
	return &Config{
		Server: ServerConfig{
			Port:            getEnv("SERVER_PORT", "8080"),
			ReadTimeout:     getDurationEnv("SERVER_READ_TIMEOUT", 10*time.Second),
			WriteTimeout:    getDurationEnv("SERVER_WRITE_TIMEOUT", 10*time.Second),
			ShutdownTimeout: getDurationEnv("SERVER_SHUTDOWN_TIMEOUT", 30*time.Second),
		},
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getEnv("DB_PORT", "5432"),
			User:     getEnv("DB_USER", "postgres"),
			Password: getEnv("DB_PASSWORD", "postgres"),
			DBName:   getEnv("DB_NAME", "saas_shortener"),
			SSLMode:  getEnv("DB_SSLMODE", "disable"),
		},
		Redis: RedisConfig{
			Addr:     getEnv("REDIS_ADDR", "localhost:6379"),
			Password: getEnv("REDIS_PASSWORD", ""),
			DB:       getIntEnv("REDIS_DB", 0),
		},
		Tenant: TenantConfig{
			DefaultRateLimit: getIntEnv("TENANT_DEFAULT_RATE_LIMIT", 100),
			MaxURLsPerTenant: getIntEnv("TENANT_MAX_URLS", 1000),
		},
	}
}

// --- 辅助函数 ---

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}

func getIntEnv(key string, defaultValue int) int {
	if value, exists := os.LookupEnv(key); exists {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}

func getDurationEnv(key string, defaultValue time.Duration) time.Duration {
	if value, exists := os.LookupEnv(key); exists {
		if duration, err := time.ParseDuration(value); err == nil {
			return duration
		}
	}
	return defaultValue
}
