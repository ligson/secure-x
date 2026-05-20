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
