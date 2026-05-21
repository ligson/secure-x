# Secure X

Secure X 是一个面向个人与小团队的安全敏感信息存储维护系统，目标是提供类似 Bitwarden 的账户与密钥管理体验，同时补充“加密文件存储”能力。

当前仓库阶段为 `第一版代码实现阶段`，仓库内已包含可运行的后端基线与 Flutter 客户端基线。

## 项目目标

- 提供跨平台客户端：`macOS`、`Windows`、`Linux`、`Android`、`iOS`
- 后端提供账号、同步、加密数据与加密文件的存储能力
- 所有敏感内容仅在客户端完成加密与解密，服务端只保存密文
- 支持密码库、登录信息、密码分类管理、网盘式加密文件目录、随机密码生成
- 前端允许用户手动配置后端服务地址，兼容私有部署场景

## 建议技术栈

- 客户端：`Flutter`
- 服务端：`Golang`
- 元数据数据库：`SQLite`
- 文件对象存储：本地文件系统或后续兼容 S3 风格存储

## 当前实现

- `securex-be/`
  - Go 后端服务
  - 已实现健康检查、注册、登录、用户信息、登录密码修改、解锁密码配置更新、密码分类管理、文件目录、登录项、密文文件上传下载、分片上传、同步导出
- `securex-app/`
  - Flutter 多端客户端
  - 已实现后端地址配置、注册、登录、登录密码修改、解锁密码解锁与修改、密码分类管理、文件目录、登录项管理、随机密码生成、加密文件后台分片上传与进度展示、重命名、删除与解密下载

## 核心原则

- `Zero-knowledge`：服务端不接触明文
- `Client-side encryption`：敏感数据只在客户端加解密
- `Offline-friendly`：客户端优先维护本地缓存与解密态会话
- `Self-hostable`：支持用户自部署后端
- `Document-first`：实现前先固化设计、边界与协作规范

## MVP 功能范围

- 注册
- 登录
- 解锁密码派生密钥
- 创建与管理密码分类
- 创建与管理网盘式文件目录
- 创建与管理密码/登录信息
- 上传、下载与删除加密文件
- 随机密码生成器
- 客户端后端地址配置
- 多端同步基础能力

## 架构摘要

系统分为两部分：

- `Flutter` 客户端：负责用户交互、本地安全缓存、密钥派生、数据加密解密、文件加密解密、随机密码生成
- `Go` 服务端：负责身份认证、密文元数据管理、密文文件存储、版本同步、访问控制、审计基础能力

建议采用“账号主密钥 + 数据项密钥 + 文件密钥”的分层加密结构，避免单一密钥承担全部数据范围，并为后续分享、密钥轮换与文件大对象处理预留空间。

## 接口约定

后端 JSON 接口统一返回以下结构：

```json
{
  "success": true,
  "message": "",
  "httpCode": 200,
  "data": {}
}
```

字段说明：

- `success`：接口处理是否成功
- `message`：给前端显示的说明信息
- `httpCode`：与 HTTP 状态码保持一致
- `data`：业务数据主体，没有数据时返回空对象

## 文档导航

- 方案总览：[doc/README.md](/Users/ligson/workspace/work-org/github/secure-x/doc/README.md)
- 产品需求：[doc/01-product-overview.md](/Users/ligson/workspace/work-org/github/secure-x/doc/01-product-overview.md)
- 架构设计：[doc/02-architecture.md](/Users/ligson/workspace/work-org/github/secure-x/doc/02-architecture.md)
- 加密与存储设计：[doc/03-crypto-storage.md](/Users/ligson/workspace/work-org/github/secure-x/doc/03-crypto-storage.md)
- 迭代计划：[doc/04-roadmap.md](/Users/ligson/workspace/work-org/github/secure-x/doc/04-roadmap.md)
- 待确认决策：[doc/05-open-questions.md](/Users/ligson/workspace/work-org/github/secure-x/doc/05-open-questions.md)
- 协作记忆：[AGENTS.md](/Users/ligson/workspace/work-org/github/secure-x/AGENTS.md)
- 变更记录：[CHANGELOG.md](/Users/ligson/workspace/work-org/github/secure-x/CHANGELOG.md)

## 当前状态

当前已完成：

- 项目定位梳理
- 文档结构初始化
- 首版设计方案沉淀
- 协作与变更记录规范建立
- `securex-be` 后端工程初始化与基础 API 实现
- `securex-app` Flutter 工程初始化与基础界面实现

当前未开始：

- 更完整的文件夹层级可视化与拖拽整理
- 文件预览与更完整下载体验
- 更强的同步冲突处理
- 更强的 KDF 升级能力

## 快速启动

### 使用脚本联调

```bash
./scripts/start-dev.sh
./scripts/stop-dev.sh
```

说明：

- 日常联调统一使用这两个脚本，避免和手工执行 `flutter run`、`go run` 混用
- `start-dev.sh` 会尽量复用已记录实例，并清理本项目残留的旧进程，保证单实例启动
- 切换设备、端口或需要重启时，优先先执行一次 `./scripts/stop-dev.sh`
- `FLUTTER_DEVICE=macos` 时，脚本会先构建 `Debug` 桌面包，再启动单实例应用进程，优先保证脚本可控和停止一致性
- macOS 本地调试若遇到系统安全存储不可用，客户端会自动回退到调试存储，优先保证联调连续性

常用可选变量：

- `FLUTTER_DEVICE=macos ./scripts/start-dev.sh`
- `FLUTTER_DEVICE=ios ./scripts/start-dev.sh`
- `START_APP=0 ./scripts/start-dev.sh`
- `START_BACKEND=0 ./scripts/start-dev.sh`

### 单独启动后端

```bash
cd securex-be
go run ./cmd/server
```

默认监听 `http://127.0.0.1:8080`。

### 启动客户端

```bash
cd securex-app
flutter run -d macos
```

首次进入后，可在登录页填写后端地址，例如 `http://127.0.0.1:8080`。

## 协作约束

- 项目内每次改动都需要同步更新 `CHANGELOG.md`
- 重要设计决策优先写入 `doc/` 再进入实现
- 仓库级协作规范以 [AGENTS.md](/Users/ligson/workspace/work-org/github/secure-x/AGENTS.md) 为准
