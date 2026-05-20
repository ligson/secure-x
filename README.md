# Secure X

Secure X 是一个面向个人与小团队的安全敏感信息存储维护系统，目标是提供类似 Bitwarden 的账户与密钥管理体验，同时补充“加密文件存储”能力。

当前仓库阶段为 `设计方案阶段`，本仓库优先沉淀产品边界、架构设计、加密模型、交付规划与协作约束，暂未进入业务代码实现。

## 项目目标

- 提供跨平台客户端：`macOS`、`Windows`、`Linux`、`Android`、`iOS`
- 后端提供账号、同步、加密数据与加密文件的存储能力
- 所有敏感内容仅在客户端完成加密与解密，服务端只保存密文
- 支持密码库、登录信息、个人文件夹、加密文件、随机密码生成
- 前端允许用户手动配置后端服务地址，兼容私有部署场景

## 建议技术栈

- 客户端：`Flutter`
- 服务端：`Golang`
- 元数据数据库：`SQLite`
- 文件对象存储：本地文件系统或后续兼容 S3 风格存储

## 核心原则

- `Zero-knowledge`：服务端不接触明文
- `Client-side encryption`：敏感数据只在客户端加解密
- `Offline-friendly`：客户端优先维护本地缓存与解密态会话
- `Self-hostable`：支持用户自部署后端
- `Document-first`：实现前先固化设计、边界与协作规范

## MVP 功能范围

- 注册
- 登录
- 主密码派生密钥
- 创建与管理个人文件夹
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

当前未开始：

- 服务端代码脚手架
- Flutter 客户端脚手架
- 数据模型与接口实现
- 加密库选型落地

## 协作约束

- 项目内每次改动都需要同步更新 `CHANGELOG.md`
- 重要设计决策优先写入 `doc/` 再进入实现
- 仓库级协作规范以 [AGENTS.md](/Users/ligson/workspace/work-org/github/secure-x/AGENTS.md) 为准
