# Changelog

All notable changes to this project will be documented in this file.

## 2026-05-20

### Added

- 初始化项目级 `README.md`，说明项目定位、技术方向、核心原则和文档入口
- 初始化项目级 `AGENTS.md`，记录长期协作记忆、产品约束和文档维护规则
- 初始化 `doc/README.md`，建立文档索引
- 新增 `doc/01-product-overview.md`，沉淀产品范围与 MVP 功能设计
- 新增 `doc/02-architecture.md`，沉淀客户端、服务端和存储层架构方案
- 新增 `doc/03-crypto-storage.md`，沉淀端到端加密与文件存储策略
- 新增 `doc/04-roadmap.md`，沉淀建议迭代路线与下一步计划
- 新增 `doc/05-open-questions.md`，集中整理需要用户拍板的关键设计决策

### Notes

- 本次仅完成设计文档初始化，尚未开始任何业务代码实现

### Updated

- 在 `AGENTS.md` 中补充开发约束：实现阶段优先复用成熟公共库，尽量少写自研通用能力，避免重复造轮子
- 新增 `.gitignore`，预先忽略 Go / Flutter 构建产物、编辑器文件、本地数据库与潜在敏感文件
- 更新文档中的工程目录命名约定：后端目录为 `securex-be`，前端目录为 `securex-app`
- 更新根目录 `.gitignore`，补充忽略 `securex-be/data/`
- 更新 `AGENTS.md`，将项目阶段同步为第一版代码实现阶段
- 更新 `README.md`，补充当前已实现能力与启动方式
- 更新 `doc/03-crypto-storage.md`，说明第一版实际采用 `PBKDF2-SHA256` 派生主密钥，并保留后续升级到 `Argon2id` 的空间
- 更新 `doc/04-roadmap.md`，将“下一步”从脚手架阶段调整为基于现有 V1 基线的迭代任务

### Added

- 新增 `securex-be/` Go 后端工程，接入 `Gin`、`GORM(SQLite)`、`JWT`、`bcrypt`
- 新增后端健康检查、注册、登录、用户信息、同步导出、文件夹、登录项、密文文件上传下载接口
- 新增 `securex-app/` Flutter 多端工程
- 新增客户端后端地址配置、注册、登录、主密码解锁、保险库同步、文件夹创建、登录项创建、随机密码生成、加密文件上传与解密下载能力
- 新增客户端加密实现，包含 `PBKDF2-SHA256` 主密钥派生、`AES-256-GCM` 文本加密与文件加密
- 新增 `securex-be/README.md` 与 `securex-app/README.md`，补充子工程说明与运行方式
- 新增第二轮交互能力：文件夹搜索/编辑/删除、登录项搜索/编辑/删除、文件搜索/重命名/删除
- 新增后端文件元数据更新接口，以及文件夹“非空不可删”保护
- 新增统一响应封装规则：后端 JSON 接口统一返回 `success`、`message`、`httpCode`、`data`
- 新增 `scripts/start-dev.sh`、`scripts/stop-dev.sh` 和 `scripts/dev-common.sh`，方便本地联调前后端

### Verified

- `securex-be`: `go build ./...`
- `securex-be`: `go test ./...`
- `securex-app`: `flutter analyze`
- `securex-app`: `flutter test`
- `securex-be`: 手动冒烟验证 `healthz`、`register`、`login`

### Updated

- 删除 `securex-app/web/`，与“不考虑网页端”的项目边界保持一致
- 重构 `securex-be` 所有 JSON 接口响应为统一结构，并同步适配 `securex-app` 的解析逻辑
- 更新 `README.md`、`AGENTS.md`、`doc/02-architecture.md`、`securex-be/README.md`，写入统一接口返回规范
- 更新 `.gitignore`，忽略本地调试产生的 `.dev/` 目录
- 重做 `securex-app` 桌面登录页视觉设计，修复品牌区溢出问题，并优化桌面端布局、输入区层级与品牌展示
- 调整 `securex-app` 登录页为真正的响应式布局，修复桌面端空白页问题，并让桌面与手机端共用同一套自适应代码
- 修复 `securex-app` 认证页运行时白屏问题：移除 `google_fonts` 在线字体依赖，并重写 `_HeroPanel` 指标区布局，避免桌面端触发无限高度约束异常
- 强化本地联调脚本：统一要求通过 `start-dev.sh` / `stop-dev.sh` 管理前后端，并在脚本中补充残留进程清理、macOS 客户端真实进程识别与单实例保障逻辑
