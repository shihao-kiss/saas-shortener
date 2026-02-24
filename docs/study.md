# 概念
- K8S namespace workload pods
- HPA controlled
- Ingress Load Balance Pod
- 连接池配置
https://www.bilibili.com/video/BV1BH4y1g7ad/?spm_id_from=333.337.search-card.all.click&vd_source=818384c9f37f51ddc0e03f10297f1aa2
- Kubernetes ConfigMap/Secret
- 配置热加载
- 自动伸缩容
- kubelet
- ELK/Kibana 或 Loki/Grafana
- QPS
- HPA 通过扩展 pod 来维持可控的单 pod 每秒查询数 (QPS)
- Kubernetes 环境中的零配置日志收集
- 基于 Redis 有序集合的滑动窗口
  - 到期时间为什么两个安全窗口？
  - 分布式限流，假如：pod1 、pod2 同时检查999未到限速1000，通过之后都向redis ADD。是不是redis就到1001了
- 多租户
  - 目前采用共享数据库，表中添加tenant_id
  - todo 生成 API KEY 变为 `JWT`



# Docker 容器化

## docker-compose

### 网络

```
networks:
  saas-network:
    driver: bridge
```

```
各部分含义

networks:
作用：定义自定义网络
目的：让容器间能够安全通信

saas-network:
网络名称：创建名为 "saas-network" 的网络
作用域：仅在此 Docker Compose 项目内可见

driver: bridge
驱动类型：桥接网络驱动
特点：
    默认的网络驱动类型
    提供容器间的隔离通信
    支持端口映射和 DNS 解析
```

- 服务间通信示例：

```
services:
  api:
    networks:
      - saas-network
  
  database:
    networks:
      - saas-network
```

这样配置后：
    API 服务可以通过 database 主机名访问数据库
    数据库服务可以通过 api 主机名访问 API
    外部无法直接访问这些服务（除非明确暴露端口）

![image-20260224170034433](study.assets/image-20260224170034433.png)



### 健康检查

```
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U postgres"]
  interval: 5s
  timeout: 5s
  retries: 5
```

```
各参数详解
test: ["CMD-SHELL", "pg_isready -U postgres"]
执行方式：在容器内运行 shell 命令
检查命令：pg_isready -U postgres

功能：PostgreSQL 内置的健康检查工具
检查内容：验证 PostgreSQL 服务器是否接受连接

interval: 5s
检查频率：每 5 秒执行一次健康检查
平衡考虑：既及时发现问题又不过度消耗资源

timeout: 5s
超时时间：每次检查最多等待 5 秒
防止阻塞：避免长时间等待影响容器状态判断

retries: 5
重试次数：连续失败 5 次才标记为不健康
容错机制：避免临时网络波动导致误判

```

```
实际效果
成功时：
Docker 将容器状态标记为 healthy
允许依赖此服务的其他容器正常启动
负载均衡器可以将流量转发到此实例

失败时：
Docker 标记容器为 unhealthy
可触发自动重启机制
防止故障传播到整个系统

为什么重要？
服务依赖管理：确保数据库就绪后再启动应用
故障自动恢复：及时发现并处理数据库问题
系统可靠性：避免向不健康的数据库发送请求
运维自动化：减少人工监控需求

这是构建高可用微服务架构的重要配置，确保了服务间的健康依赖关系。
```



### Docker 网络自动分配机制

#### 1. 自定义网络创建

```
networks:
  saas-network:
    driver: bridge
```

#### 2. 容器加入网络

```
postgres:
  networks:
    - saas-network
```

#### 3. 自动 IP 分配过程

```
Docker Engine 自动处理：
1. 创建 saas-network 网络（通常是 172.x.x.0/16 网段）
2. 为每个容器分配唯一 IP 地址
3. 建立容器名到 IP 的 DNS 映射
```

#### 查看实际 IP 地址的方法

```
docker exec saas-postgres hostname -i
```

#### 为什么不需要手动指定？

```
Docker 的智能机制：
动态分配：IP 地址根据可用范围自动分配
DNS 解析：通过服务名 postgres 自动解析
避免冲突：防止手动配置导致的 IP 冲突

这就是为什么配置中只写 - DB_HOST=postgres 而不是具体 IP 地址的原因——Docker 的网络系统会自动处理这些底层细节，让开发者专注于业务逻辑。
```



### 停止 docker compose 环境

```
## 停止 Docker Compose 环境
.PHONY: docker-down
docker-down:
	docker compose -f $(DOCKER_COMPOSE_LOCAL) down
```

```
执行命令：停止 Docker Compose 环境
参数说明：
    -f $(DOCKER_COMPOSE_LOCAL)：指定 Compose 文件路径
    down：停止并移除容器、网络、卷等
    
清理资源：
    停止所有容器
    移除网络
    保留命名卷（数据持久化）
    移除默认的 anonymous volumes
```

#### 容器停止的顺序是怎样的

```
默认停止顺序：
1. 发送 SIGTERM 信号给所有容器
2. 等待超时时间（默认 10 秒）
3. 发送 SIGKILL 强制终止仍运行的容器
```

```
并行停止：
    所有容器几乎同时收到停止信号
    不会按照 depends_on 的顺序反向停止
    这是为了快速关闭整个环境
```

```
自定义超时：
# docker-compose.yml
services:
  app:
    stop_grace_period: 30s  # 自定义优雅停止时间
```

#### 保留命名卷的含义

```
命名卷（Named Volumes）：
volumes:
  postgres_data:    # 这就是命名卷

保留意味着：
✅ 数据持久化保存
✅ 卷本身不会被删除
✅ 下次 docker-compose up 时数据依然存在
✅ 可以在不同容器间共享
```

```
查看命名卷：
docker volume ls
docker volume inspect saas-shortener_postgres_data
```

####  匿名卷 vs 非匿名卷的区别

```
匿名卷（Anonymous Volumes）
services:
  app:
    volumes:
      - /app/data  # 匿名卷：只有容器内路径

特点：
❌ 没有显式名称
❌ docker-compose down 时默认会被删除
❌ 难以管理和备份
⚠️ 容易造成数据丢失
```

```
命名卷（Named Volumes）
volumes:
  postgres_data:    # 顶层声明

services:
  postgres:
    volumes:
      - postgres_data:/var/lib/postgresql/data  # 引用命名卷

特点：
✅ 有明确名称
✅ docker-compose down 时默认保留
✅ 易于管理和备份
✅ 可在多个服务间共享
```

![image-20260224174702048](study.assets/image-20260224174702048.png)

#### 控制删除行为的选项

```
# 保留所有卷（默认行为）
docker-compose down

# 删除所有卷（包括命名卷）
docker-compose down -v

# 只删除匿名卷，保留命名卷
docker-compose down --remove-orphans

这就是为什么在生产环境中强烈推荐使用命名卷的原因——确保重要数据的安全持久化。
```

## Redis

```
redis-server --maxmemory 64mb --maxmemory-policy allkeys-lru
```

```
我来为您解释这个 Redis 启动命令中的参数：

## 参数详解

### `redis-server`
Redis 服务器的可执行文件

### `--maxmemory 64mb`
- **作用**：设置 Redis 实例的最大内存使用量为 64MB
- **说明**：
  - 当 Redis 使用的内存达到 64MB 时，会根据配置的淘汰策略开始删除数据
  - 支持多种单位：b(字节)、kb、mb、gb
  - 这对于控制内存使用和防止系统内存耗尽很重要

### `--maxmemory-policy allkeys-lru`
- **作用**：设置内存淘汰策略为 ALLKEYS-LRU
- **详细说明**：
  - **LRU** = Least Recently Used（最近最少使用）
  - **ALLKEYS** = 对所有键都适用此策略
  - 当内存不足时，Redis 会删除最近最少被访问的键

## 内存淘汰策略选项对比

常见的 `maxmemory-policy` 选项包括：

1. **allkeys-lru** - 在所有键中删除最近最少使用的键 ✅ 您当前的选择
2. **allkeys-lfu** - 在所有键中删除最不经常使用的键
3. **allkeys-random** - 随机删除键
4. **volatile-lru** - 只在设置了过期时间的键中删除最近最少使用的键
5. **volatile-lfu** - 只在设置了过期时间的键中删除最不经常使用的键
6. **volatile-random** - 只在设置了过期时间的键中随机删除
7. **volatile-ttl** - 删除即将过期的键
8. **noeviction** - 不删除任何数据，内存满时返回错误

## 适用场景

您选择的 `allkeys-lru` 策略特别适合：
- 缓存系统
- 需要自动清理旧数据的应用
- 对数据持久性要求不高的场景

这种配置确保了 Redis 在有限的 64MB 内存中始终保存最有价值的数据。
```

- RDB 快照文件、AOF 日志文件