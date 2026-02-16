// Package service 业务逻辑层
// 职责：编排业务流程，不直接操作数据库
// SaaS 关键逻辑：配额检查、租户隔离验证、套餐限制等
package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/yourname/saas-shortener/internal/model"
	"github.com/yourname/saas-shortener/internal/repository"
)

var (
	ErrQuotaExceeded = errors.New("URL 配额已用完，请升级套餐")
	ErrRateLimited   = errors.New("请求频率超限，请稍后重试")
	ErrURLNotFound   = errors.New("短链接不存在")
	ErrURLExpired    = errors.New("短链接已过期")
)

// Service 业务逻辑服务
type Service struct {
	repo   *repository.Repository
	logger *zap.Logger
}

// New 创建 Service 实例
func New(repo *repository.Repository, logger *zap.Logger) *Service {
	return &Service{
		repo:   repo,
		logger: logger,
	}
}

// ==================== 租户管理 ====================

// CreateTenant 创建新租户
// SaaS 流程：用户注册 → 创建租户 → 分配 API Key → 选择套餐
func (s *Service) CreateTenant(ctx context.Context, req *model.CreateTenantRequest) (*model.CreateTenantResponse, error) {
	// 生成 API Key（生产环境建议使用更安全的方式，如 JWT）
	apiKey := generateAPIKey()

	plan := req.Plan
	if plan == "" {
		plan = "free"
	}

	// 根据套餐设置配额
	// SaaS 核心：不同套餐有不同的功能和配额限制
	rateLimit, maxURLs := getPlanLimits(plan)

	tenant := &model.Tenant{
		ID:        uuid.New(),
		Name:      req.Name,
		APIKey:    hashAPIKey(apiKey), // 存储哈希后的 API Key
		Plan:      plan,
		RateLimit: rateLimit,
		MaxURLs:   maxURLs,
		IsActive:  true,
	}

	if err := s.repo.CreateTenant(ctx, tenant); err != nil {
		return nil, fmt.Errorf("创建租户失败: %w", err)
	}

	s.logger.Info("新租户创建成功",
		zap.String("tenant_id", tenant.ID.String()),
		zap.String("name", tenant.Name),
		zap.String("plan", tenant.Plan),
	)

	return &model.CreateTenantResponse{
		ID:     tenant.ID,
		Name:   tenant.Name,
		APIKey: apiKey, // 明文 API Key 只在创建时返回一次！
		Plan:   tenant.Plan,
	}, nil
}

// AuthenticateTenant 认证租户（通过 API Key）
func (s *Service) AuthenticateTenant(ctx context.Context, apiKey string) (*model.Tenant, error) {
	hashedKey := hashAPIKey(apiKey)
	return s.repo.GetTenantByAPIKey(ctx, hashedKey)
}

// ==================== 短链接管理 ====================

// CreateShortURL 创建短链接
func (s *Service) CreateShortURL(ctx context.Context, tenantID uuid.UUID, req *model.CreateShortURLRequest) (*model.ShortURLResponse, error) {
	// 1. 检查租户配额
	// SaaS 关键：配额管理，免费用户有限制，付费用户配额更高
	tenant, err := s.repo.GetTenantByID(ctx, tenantID)
	if err != nil {
		return nil, fmt.Errorf("查询租户失败: %w", err)
	}

	count, err := s.repo.CountURLsByTenant(ctx, tenantID)
	if err != nil {
		return nil, fmt.Errorf("查询配额失败: %w", err)
	}

	if count >= int64(tenant.MaxURLs) {
		s.logger.Warn("租户 URL 配额已用完",
			zap.String("tenant_id", tenantID.String()),
			zap.Int64("current", count),
			zap.Int("max", tenant.MaxURLs),
		)
		return nil, ErrQuotaExceeded
	}

	// 2. 生成或使用自定义短码
	code := req.CustomCode
	if code == "" {
		code = generateShortCode(6)
	}

	// 3. 创建短链接记录
	shortURL := &model.ShortURL{
		ID:          uuid.New(),
		TenantID:    tenantID,
		Code:        code,
		OriginalURL: req.URL,
		IsActive:    true,
	}

	if err := s.repo.CreateShortURL(ctx, shortURL); err != nil {
		return nil, fmt.Errorf("创建短链接失败: %w", err)
	}

	s.logger.Info("短链接创建成功",
		zap.String("tenant_id", tenantID.String()),
		zap.String("code", code),
	)

	return &model.ShortURLResponse{
		ID:          shortURL.ID,
		Code:        shortURL.Code,
		ShortURL:    fmt.Sprintf("/%s", shortURL.Code),
		OriginalURL: shortURL.OriginalURL,
		Clicks:      0,
		CreatedAt:   shortURL.CreatedAt,
	}, nil
}

// Redirect 处理短链接重定向
func (s *Service) Redirect(ctx context.Context, code, ip, userAgent, referer string) (string, error) {
	// 获取短链接信息
	shortURL, err := s.repo.GetShortURLByCode(ctx, code)
	if err != nil {
		return "", ErrURLNotFound
	}

	// 检查是否过期
	if shortURL.ExpiresAt != nil && shortURL.ExpiresAt.Before(time.Now()) {
		return "", ErrURLExpired
	}

	// 异步记录点击事件（不阻塞重定向响应）
	// 云原生最佳实践：非关键路径异步处理
	go func() {
		bgCtx := context.Background()
		// 增加点击计数
		if err := s.repo.IncrementClicks(bgCtx, shortURL.ID); err != nil {
			s.logger.Error("增加点击计数失败", zap.Error(err))
		}
		// 记录点击详情
		event := &model.ClickEvent{
			ID:         uuid.New(),
			ShortURLID: shortURL.ID,
			TenantID:   shortURL.TenantID,
			IP:         ip,
			UserAgent:  userAgent,
			Referer:    referer,
		}
		if err := s.repo.CreateClickEvent(bgCtx, event); err != nil {
			s.logger.Error("记录点击事件失败", zap.Error(err))
		}
	}()

	return shortURL.OriginalURL, nil
}

// ListShortURLs 查询租户的短链接列表
func (s *Service) ListShortURLs(ctx context.Context, tenantID uuid.UUID, page, pageSize int) ([]model.ShortURLResponse, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	offset := (page - 1) * pageSize
	urls, total, err := s.repo.ListShortURLsByTenant(ctx, tenantID, offset, pageSize)
	if err != nil {
		return nil, 0, err
	}

	// 转换为响应 DTO
	responses := make([]model.ShortURLResponse, len(urls))
	for i, u := range urls {
		responses[i] = model.ShortURLResponse{
			ID:          u.ID,
			Code:        u.Code,
			ShortURL:    fmt.Sprintf("/%s", u.Code),
			OriginalURL: u.OriginalURL,
			Clicks:      u.Clicks,
			CreatedAt:   u.CreatedAt,
			ExpiresAt:   u.ExpiresAt,
		}
	}

	return responses, total, nil
}

// GetStats 获取租户统计信息
func (s *Service) GetStats(ctx context.Context, tenantID uuid.UUID) (*model.StatsResponse, error) {
	return s.repo.GetTenantStats(ctx, tenantID)
}

// CheckRateLimit 检查限流
func (s *Service) CheckRateLimit(ctx context.Context, tenantID uuid.UUID, limit int) (bool, error) {
	return s.repo.CheckRateLimit(ctx, tenantID, limit)
}

// HealthCheck 健康检查
func (s *Service) HealthCheck(ctx context.Context) error {
	return s.repo.HealthCheck(ctx)
}

// ==================== 辅助函数 ====================

// generateShortCode 生成随机短码
func generateShortCode(length int) string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	result := make([]byte, length)
	for i := range result {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		result[i] = charset[n.Int64()]
	}
	return string(result)
}

// generateAPIKey 生成 API Key
func generateAPIKey() string {
	bytes := make([]byte, 32)
	rand.Read(bytes)
	return hex.EncodeToString(bytes)
}

// hashAPIKey 对 API Key 进行哈希（安全存储）
func hashAPIKey(key string) string {
	hash := sha256.Sum256([]byte(key))
	return hex.EncodeToString(hash[:])
}

// getPlanLimits 根据套餐返回配额
// SaaS 定价策略：不同套餐 → 不同功能/配额 → 不同价格
func getPlanLimits(plan string) (rateLimit int, maxURLs int) {
	switch plan {
	case "pro":
		return 500, 10000
	case "enterprise":
		return 5000, 100000
	default: // free
		return 100, 1000
	}
}
