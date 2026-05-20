# AGENTS.md

本文件用于记录本仓库的长期协作约束、产品记忆与文档维护规则，帮助后续继续工作时保持一致。

## 当前阶段

- 当前阶段为 `方案设计阶段`
- 用户本轮明确要求：`先写设计与说明文档，不直接写业务代码`
- 后续只有在用户确认方案后，才进入脚手架或实现阶段

## 产品定位记忆

- 项目名称：`Secure X`
- 项目目标：安全敏感信息存储维护系统
- 对标参考：`Bitwarden`
- 差异点：除密码/登录信息外，还要支持 `加密文件存储`
- 部署方式：优先支持私有部署

## 技术方向记忆

- 后端建议使用：`Golang`
- 客户端建议使用：`Flutter`
- 客户端目标平台：`macOS`、`Windows`、`Linux`、`Android`、`iOS`
- 不考虑网页端
- 前端需要支持填写与切换后端地址
- 服务端数据库建议：`SQLite`
- 文件内容存到服务端文件存储中，但保存的是 `密文`

## 安全原则记忆

- 所有敏感数据必须 `客户端加密，客户端解密`
- 服务端只负责：
  - 账号与认证
  - 密文元数据管理
  - 密文文件存储
  - 同步与版本控制
- 服务端默认不可接触任何业务明文
- 文件、密码项、备注、登录信息都应以密文形式传输与存储

## 计划中的核心能力

- 注册
- 登录
- 主密码体系
- 个人文件夹
- 密码/登录信息管理
- 加密文件上传下载
- 随机密码生成器
- 多端同步

## 文档维护规则

- `README.md`：对外说明项目目标、范围、架构摘要与文档入口
- `doc/`：沉淀详细设计、边界、路线图与后续决策
- `CHANGELOG.md`：每次改动必须更新
- 如果设计发生变化，优先修改 `doc/` 与 `README.md`
- 如果协作方式或长期约束变化，必须同步更新本文件

## 本仓库执行约束

- 终端命令优先使用 `rtk` 前缀
- 读取仓库现状后再动手，不凭空假设已有实现
- 不写网页端相关方案，除非用户后续明确追加
- 设计优先考虑跨平台桌面与移动端复用
- 默认先做 `MVP`，再考虑团队分享、组织空间、自动填充等增强能力
- 写代码时优先复用成熟、流行、维护活跃的公共库，尽可能少写自研实现
- 除非公共库无法满足需求，或存在明确的安全、性能、许可、体积问题，否则不要动辄自行实现底层能力
- 对加密、认证、存储、状态管理、表单、网络请求等通用能力，优先做“可靠选型与合理封装”，而不是重复造轮子

## 当前文档清单

- [README.md](/Users/ligson/workspace/work-org/github/secure-x/README.md)
- [doc/README.md](/Users/ligson/workspace/work-org/github/secure-x/doc/README.md)
- [doc/01-product-overview.md](/Users/ligson/workspace/work-org/github/secure-x/doc/01-product-overview.md)
- [doc/02-architecture.md](/Users/ligson/workspace/work-org/github/secure-x/doc/02-architecture.md)
- [doc/03-crypto-storage.md](/Users/ligson/workspace/work-org/github/secure-x/doc/03-crypto-storage.md)
- [doc/04-roadmap.md](/Users/ligson/workspace/work-org/github/secure-x/doc/04-roadmap.md)
- [doc/05-open-questions.md](/Users/ligson/workspace/work-org/github/secure-x/doc/05-open-questions.md)
- [CHANGELOG.md](/Users/ligson/workspace/work-org/github/secure-x/CHANGELOG.md)

## 待确认事项

- 注册是否采用邮箱验证码，还是只做用户名 + 主密码
- 是否支持找回账号，但不支持找回主密码
- 初期是否只做单用户个人空间，不做共享保险库
- 文件大小上限、同步冲突策略、离线缓存策略的最终取舍
