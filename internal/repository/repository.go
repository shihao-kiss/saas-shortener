// Package repository 数据访问层
// 云原生最佳实践：
// 1. 使用连接池管理数据库连接
// 2. 使用 Redis 作为缓存层，减少数据库压力
// 3. 所有查询都带有 TenantID 条件，确保多租户数据隔离
package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
	"gorm.io/gorm"

	"github.com/yourname/saas-shortener/internal/model"
)

// Repository 数据访问接口
// 使用接口便于测试（mock）和未来替换存储实现
type Repository struct {
	db     *gorm.DB
	rdb    *redis.Client
	logger *zap.Logger
}

// New 创建 Repository 实例
func New(db *gorm.DB, rdb *redis.Client, logger *zap.Logger) *Repository {
	return &Repository{
		db:     db,
		rdb:    rdb,
		logger: logger,
	}
}

// AutoMigrate 自动迁移数据库表结构
// 生产环境中建议使用专门的迁移工具（如 golang-migrate）
func (r *Repository) AutoMigrate() error {
	return r.db.AutoMigrate(
		&model.Tenant{},
		&model.ShortURL{},
		&model.ClickEvent{},
	)
}

// ==================== 租户相关操作 ====================

// CreateTenant 创建新租户
func (r *Repository) CreateTenant(ctx context.Context, tenant *model.Tenant) error {
	return r.db.WithContext(ctx).Create(tenant).Error
}

// GetTenantByAPIKey 通过 API Key 查询租户
// SaaS 认证核心：每个 API 请求都携带 API Key，系统据此识别租户
func (r *Repository) GetTenantByAPIKey(ctx context.Context, apiKey string) (*model.Tenant, error) {
	// 先尝试从 Redis 缓存获取（热路径优化）
	cacheKey := fmt.Sprintf("tenant:apikey:%s", apiKey)
	cached, err := r.rdb.Get(ctx, cacheKey).Result()
	if err == nil {
		var tenant model.Tenant
		if err := json.Unmarshal([]byte(cached), &tenant); err == nil {
			return &tenant, nil
		}
	}

	// 缓存未命中，查数据库
	var tenant model.Tenant
	if err := r.db.WithContext(ctx).Where("api_key = ? AND is_active = ?", apiKey, true).First(&tenant).Error; err != nil {
		return nil, err
	}

	// 写入缓存，TTL 5分钟
	if data, err := json.Marshal(tenant); err == nil {
		r.rdb.Set(ctx, cacheKey, data, 5*time.Minute)
	}

	return &tenant, nil
}

// GetTenantByID 通过 ID 查询租户
func (r *Repository) GetTenantByID(ctx context.Context, id uuid.UUID) (*model.Tenant, error) {
	var tenant model.Tenant
	if err := r.db.WithContext(ctx).First(&tenant, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &tenant, nil
}

// ==================== 短链接相关操作 ====================

// CreateShortURL 创建短链接
// 注意：所有数据操作都绑定 TenantID，这是 SaaS 多租户隔离的核心
func (r *Repository) CreateShortURL(ctx context.Context, shortURL *model.ShortURL) error {
	if err := r.db.WithContext(ctx).Create(shortURL).Error; err != nil {
		return err
	}

	// 同时写入 Redis 缓存（短码 -> 原始URL 的映射）
	// 这是短链接服务的热路径，必须快速响应
	cacheKey := fmt.Sprintf("url:%s", shortURL.Code)
	r.rdb.Set(ctx, cacheKey, shortURL.OriginalURL, 24*time.Hour)

	return nil
}

// GetShortURLByCode 通过短码查询（重定向时使用）
// 这是访问量最大的接口，优先走缓存
func (r *Repository) GetShortURLByCode(ctx context.Context, code string) (*model.ShortURL, error) {
	// 先查 Redis
	cacheKey := fmt.Sprintf("url:detail:%s", code)
	cached, err := r.rdb.Get(ctx, cacheKey).Result()
	if err == nil {
		var shortURL model.ShortURL
		if err := json.Unmarshal([]byte(cached), &shortURL); err == nil {
			return &shortURL, nil
		}
	}

	// 缓存未命中，查数据库
	var shortURL model.ShortURL
	if err := r.db.WithContext(ctx).Where("code = ? AND is_active = ?", code, true).First(&shortURL).Error; err != nil {
		return nil, err
	}

	// 写入缓存
	if data, err := json.Marshal(shortURL); err == nil {
		r.rdb.Set(ctx, cacheKey, data, 1*time.Hour)
	}

	return &shortURL, nil
}

// GetOriginalURL 快速获取原始 URL（仅用于重定向）
func (r *Repository) GetOriginalURL(ctx context.Context, code string) (string, error) {
	// 先查 Redis（最快路径）
	cacheKey := fmt.Sprintf("url:%s", code)
	url, err := r.rdb.Get(ctx, cacheKey).Result()
	if err == nil {
		return url, nil
	}

	// 缓存未命中，查数据库
	var shortURL model.ShortURL
	if err := r.db.WithContext(ctx).
		Select("original_url").
		Where("code = ? AND is_active = ?", code, true).
		First(&shortURL).Error; err != nil {
		return "", err
	}

	// 回填缓存
	r.rdb.Set(ctx, cacheKey, shortURL.OriginalURL, 24*time.Hour)

	return shortURL.OriginalURL, nil
}

// ListShortURLsByTenant 按租户查询短链接列表（分页）
// SaaS 关键：WHERE tenant_id = ? 确保租户只能看到自己的数据
func (r *Repository) ListShortURLsByTenant(ctx context.Context, tenantID uuid.UUID, offset, limit int) ([]model.ShortURL, int64, error) {
	var urls []model.ShortURL
	var total int64

	query := r.db.WithContext(ctx).Where("tenant_id = ?", tenantID)

	// 先查总数
	if err := query.Model(&model.ShortURL{}).Count(&total).Error; err != nil {
		return nil, 0, err
	}

	// 分页查询
	if err := query.Order("created_at DESC").Offset(offset).Limit(limit).Find(&urls).Error; err != nil {
		return nil, 0, err
	}

	return urls, total, nil
}

// IncrementClicks 增加点击次数
func (r *Repository) IncrementClicks(ctx context.Context, urlID uuid.UUID) error {
	return r.db.WithContext(ctx).
		Model(&model.ShortURL{}).
		Where("id = ?", urlID).
		UpdateColumn("clicks", gorm.Expr("clicks + 1")).Error
}

// CreateClickEvent 记录点击事件
func (r *Repository) CreateClickEvent(ctx context.Context, event *model.ClickEvent) error {
	return r.db.WithContext(ctx).Create(event).Error
}

// CountURLsByTenant 统计租户的 URL 数量（用于配额检查）
func (r *Repository) CountURLsByTenant(ctx context.Context, tenantID uuid.UUID) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Model(&model.ShortURL{}).
		Where("tenant_id = ?", tenantID).
		Count(&count).Error
	return count, err
}

// GetTenantStats 获取租户统计信息
func (r *Repository) GetTenantStats(ctx context.Context, tenantID uuid.UUID) (*model.StatsResponse, error) {
	var stats model.StatsResponse

	// 总 URL 数
	r.db.WithContext(ctx).Model(&model.ShortURL{}).
		Where("tenant_id = ?", tenantID).
		Count(&stats.TotalURLs)

	// 活跃 URL 数
	r.db.WithContext(ctx).Model(&model.ShortURL{}).
		Where("tenant_id = ? AND is_active = ?", tenantID, true).
		Count(&stats.ActiveURLs)

	// 总点击数
	r.db.WithContext(ctx).Model(&model.ShortURL{}).
		Where("tenant_id = ?", tenantID).
		Select("COALESCE(SUM(clicks), 0)").
		Scan(&stats.TotalClicks)

	return &stats, nil
}

// ==================== 限流相关（Redis） ====================

// CheckRateLimit 检查租户是否超过限流
// SaaS 重要功能：不同套餐的租户有不同的 API 调用配额
// 使用 Redis 的滑动窗口计数器实现分布式限流
func (r *Repository) CheckRateLimit(ctx context.Context, tenantID uuid.UUID, limit int) (bool, error) {
	key := fmt.Sprintf("ratelimit:%s", tenantID.String())
	now := time.Now().Unix()
	windowStart := now - 60 // 1分钟滑动窗口

	pipe := r.rdb.Pipeline()

	// 移除窗口外的记录
	pipe.ZRemRangeByScore(ctx, key, "0", fmt.Sprintf("%d", windowStart))

	// 添加当前请求
	pipe.ZAdd(ctx, key, redis.Z{Score: float64(now), Member: fmt.Sprintf("%d-%d", now, time.Now().UnixNano())})

	// 获取窗口内的请求数
	countCmd := pipe.ZCard(ctx, key)

	// 设置 key 过期时间
	pipe.Expire(ctx, key, 2*time.Minute)

	if _, err := pipe.Exec(ctx); err != nil {
		return false, err
	}

	count := countCmd.Val()
	return count <= int64(limit), nil
}

// HealthCheck 健康检查 - 验证数据库和 Redis 连接
func (r *Repository) HealthCheck(ctx context.Context) error {
	// 检查数据库
	sqlDB, err := r.db.DB()
	if err != nil {
		return fmt.Errorf("获取数据库连接失败: %w", err)
	}
	if err := sqlDB.PingContext(ctx); err != nil {
		return fmt.Errorf("数据库 ping 失败: %w", err)
	}

	// 检查 Redis
	if err := r.rdb.Ping(ctx).Err(); err != nil {
		return fmt.Errorf("Redis ping 失败: %w", err)
	}

	return nil
}
