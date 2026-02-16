// Package model 定义了数据模型
// SaaS 核心概念：多租户（Multi-Tenancy）
// 这里采用"共享数据库，共享 Schema，TenantID 隔离"的模式
// 这是最常见的 SaaS 多租户模式，适合中小规模租户
//
// 多租户的三种常见模式：
// 1. 独立数据库（每个租户一个数据库）- 隔离性最好，成本最高
// 2. 共享数据库，独立 Schema - 中等隔离，中等成本
// 3. 共享数据库，共享 Schema，TenantID 区分 - 隔离性一般，成本最低 ← 本项目采用
package model

import (
	"time"

	"github.com/google/uuid"
)

// Tenant 租户模型
// SaaS 中的"租户"就是你的客户（通常是一家公司/组织）
type Tenant struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key" json:"id"`
	Name      string    `gorm:"size:255;not null" json:"name"`                // 租户名称（公司名）
	APIKey    string    `gorm:"size:64;uniqueIndex;not null" json:"-"`        // API 密钥，用于认证
	Plan      string    `gorm:"size:50;not null;default:'free'" json:"plan"`  // 订阅套餐: free/pro/enterprise
	RateLimit int       `gorm:"not null;default:100" json:"rate_limit"`       // 每分钟请求限制
	MaxURLs   int       `gorm:"not null;default:1000" json:"max_urls"`        // 最大 URL 数
	IsActive  bool      `gorm:"not null;default:true" json:"is_active"`       // 是否激活
	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

// ShortURL 短链接模型
// 注意 TenantID 字段 —— 这是多租户数据隔离的关键
type ShortURL struct {
	ID          uuid.UUID `gorm:"type:uuid;primary_key" json:"id"`
	TenantID    uuid.UUID `gorm:"type:uuid;index;not null" json:"tenant_id"`   // 所属租户 ← 多租户关键字段
	Code        string    `gorm:"size:10;uniqueIndex;not null" json:"code"`     // 短码，如 "abc123"
	OriginalURL string    `gorm:"type:text;not null" json:"original_url"`       // 原始长 URL
	Clicks      int64     `gorm:"not null;default:0" json:"clicks"`            // 点击次数
	IsActive    bool      `gorm:"not null;default:true" json:"is_active"`       // 是否启用
	ExpiresAt   *time.Time `json:"expires_at,omitempty"`                        // 过期时间（可选）
	CreatedAt   time.Time  `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt   time.Time  `gorm:"autoUpdateTime" json:"updated_at"`
}

// ClickEvent 点击事件模型（用于统计分析）
type ClickEvent struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key" json:"id"`
	ShortURLID uuid.UUID `gorm:"type:uuid;index;not null" json:"short_url_id"`
	TenantID  uuid.UUID `gorm:"type:uuid;index;not null" json:"tenant_id"`    // 冗余存储租户ID，方便按租户查询
	IP        string    `gorm:"size:45" json:"ip"`
	UserAgent string    `gorm:"type:text" json:"user_agent"`
	Referer   string    `gorm:"type:text" json:"referer"`
	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
}

// --- 请求/响应 DTO ---

// CreateShortURLRequest 创建短链接请求
type CreateShortURLRequest struct {
	URL       string `json:"url" binding:"required,url"` // 原始 URL
	CustomCode string `json:"custom_code,omitempty"`      // 自定义短码（可选）
}

// ShortURLResponse 短链接响应
type ShortURLResponse struct {
	ID          uuid.UUID  `json:"id"`
	Code        string     `json:"code"`
	ShortURL    string     `json:"short_url"`
	OriginalURL string     `json:"original_url"`
	Clicks      int64      `json:"clicks"`
	CreatedAt   time.Time  `json:"created_at"`
	ExpiresAt   *time.Time `json:"expires_at,omitempty"`
}

// StatsResponse 统计响应
type StatsResponse struct {
	TotalURLs   int64 `json:"total_urls"`
	TotalClicks int64 `json:"total_clicks"`
	ActiveURLs  int64 `json:"active_urls"`
}

// CreateTenantRequest 创建租户请求
type CreateTenantRequest struct {
	Name string `json:"name" binding:"required"`
	Plan string `json:"plan,omitempty"`
}

// CreateTenantResponse 创建租户响应
type CreateTenantResponse struct {
	ID     uuid.UUID `json:"id"`
	Name   string    `json:"name"`
	APIKey string    `json:"api_key"` // 只在创建时返回一次
	Plan   string    `json:"plan"`
}
