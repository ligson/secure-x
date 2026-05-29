# Secure X

Secure X 是一个面向个人与小团队的安全敏感信息存储维护系统，目标是提供类似 Bitwarden 的账户与密钥管理体验，同时补充“加密文件存储”能力。

当前仓库阶段为 `第一版代码实现阶段`，仓库内已包含可运行的后端基线与 Flutter 客户端基线。

## 项目目标

- 提供跨平台客户端：`macOS`、`Windows`、`Linux`、`Android`、`iOS`
- 后端提供账号、同步、加密数据与加密文件的存储能力
- 所有敏感内容仅在客户端完成加密与解密，服务端只保存密文
- 支持密码库、登录信息、密码分类管理、网盘式加密文件目录、加密聊天、好友通讯录、随机密码生成
- 前端允许用户手动配置后端服务地址，兼容私有部署场景

## 建议技术栈

- 客户端：`Flutter`
- 服务端：`Golang`
- 元数据数据库：`SQLite`
- 文件对象存储：本地文件系统或后续兼容 S3 风格存储

## 当前实现

- `securex-be/`
  - Go 后端服务
  - 已实现健康检查、注册、登录、用户信息、登录密码修改、解锁密码配置更新、密码分类管理、文件目录、登录项、好友申请与通讯录、群聊元数据与成员关系存储、用户级加密聊天归档、设备级密文消息队列、实时服务配置、密文文件上传下载、分片上传、同步导出
- `securex-app/`
  - Flutter 多端客户端
  - 已实现后端地址配置、注册、登录、登录密码修改、解锁密码解锁与修改、密码分类管理、文件目录、登录项管理、服务端加密聊天归档优先加载、本地聊天缓存兜底、按会话增量归档同步、群聊快照同步、好友通讯录与申请处理、随机密码生成、加密文件后台分片上传与进度展示、重命名、删除与解密下载，以及面向移动网络的实时通道自动恢复

## 核心原则

- `Zero-knowledge`：服务端不接触明文
- `Client-side encryption`：敏感数据只在客户端加解密
- `E2EE by default`：涉及敏感数据同步、聊天、归档、密钥封装时，默认按端到端加密思路设计，服务端只接触不可解密密文和最小必要元数据
- `Per-user isolation`：每个用户的数据只能由自己解密，其他用户和服务端都不能解密看到
- `Strict ownership checks`：服务端所有读写接口都必须校验资源归属，禁止跨用户读取、下载、引用、修改或删除
- `Offline-friendly`：客户端优先维护本地缓存与解密态会话
- `Upgrade-safe`：协议、快照、数据库和本地缓存升级必须优先保证兼容读取与增量迁移，不允许因升级丢失用户已有数据
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
- 好友聊天入口、会话列表、发起群聊与服务端密文聊天归档
- 好友通讯录、好友申请与同意/拒绝
- 随机密码生成器
- 客户端后端地址配置
- 多端同步基础能力

## 架构摘要

系统分为两部分：

- `Flutter` 客户端：负责用户交互、本地安全缓存、密钥派生、数据加密解密、文件加密解密、随机密码生成
- `Go` 服务端：负责身份认证、密文元数据管理、密文文件存储、版本同步、访问控制、审计基础能力

建议采用“账号主密钥 + 数据项密钥 + 文件密钥”的分层加密结构，避免单一密钥承担全部数据范围，并为后续分享、密钥轮换与文件大对象处理预留空间。

好友关系当前仅作为通讯录和后续协作入口，不代表任何保险库授权；成为好友不会让对方读取、下载或解密你的密码库、文件密文或任何业务明文。

聊天能力当前收敛为“`WebSocket + 应用层端到端加密`”主链路：客户端通过 HTTP 配置接口获取实时服务信息，使用登录态建立 WebSocket 实时连接，并按目标用户设备逐个加密消息。图片、语音、视频和文件类聊天附件会先在客户端加密为密文对象，聊天消息只携带轻量引用和端到端加密后的解密参数。服务端只负责在线通知、短期待拉取的设备密文信封、聊天附件密文对象和“每个用户自己的加密聊天归档”，不保存可解密正文，也不持有会话密钥。

语音/视频通话媒体链路采用自托管 `LiveKit`：secure-x 后端从 YAML 配置读取 LiveKit 地址与 API 密钥，在校验好友关系或共同群成员关系后签发短期房间 token；客户端通过实时配置接口获取 RTC 服务信息并加入 LiveKit 房间。部署上可以选择 LiveKit 内置 TURN/TLS 与公网 `443/TCP` 复用的最简方案，减少移动网络和防火墙环境下的连通性问题。

登录解锁后，客户端会自动注册当前设备身份、公钥和协议版本，建立实时连接，并优先从服务端拉取属于当前账号的加密聊天归档恢复会话；本地文件只保留为性能缓存与故障兜底。如果本地缓存里存在尚未同步到服务端的新消息，客户端会在合并后重新回写加密归档。当前聊天归档已开始支持“清单 + 按会话分段”的增量同步模型，新版本会优先走更轻的按会话同步；客户端本地缓存也已拆成“摘要 + 单会话详情”两层密文结构，进入聊天页时只按需解密当前会话，降低手机端首屏压力。如果用户历史里仍是旧的整包密文快照，也会自动兼容读取并平滑迁移，避免升级时丢消息。应用回到前台、手机 Wi‑Fi/蜂窝网络切换、弱网恢复后，客户端会继续拉取属于当前设备的待同步密文、补发尚未同步的消息并发起历史对账。跨用户历史消息仍采用在线端到端同步补齐，服务端始终不保存可解密聊天正文。

群聊当前采用“服务端保存最小必要元数据 + 每个用户自己的加密群聊归档”的模型：服务端保存群成员关系、群管理、当前用户自己的加密群快照，但不保存可解密群消息正文、不保存群会话密钥。后续若实现群历史同步与成员删除后的密钥轮换，需要继续保持客户端端到端加密边界。

当手机锁屏、切后台、切 Wi‑Fi/蜂窝或弱网恢复后，客户端会强制重建实时连接，并自动尝试补发尚未同步到服务端归档的消息、拉取属于当前设备的未处理密文、向在线好友或共同群成员请求历史消息。聊天协议实现要求接口化和版本化，后续升级只能增量迁移，不能让本地缓存或服务端已有聊天密文、群元数据和归档因为升级而丢失。

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

- 方案总览：[doc/README.md](doc/README.md)
- 产品需求：[doc/01-product-overview.md](doc/01-product-overview.md)
- 架构设计：[doc/02-architecture.md](doc/02-architecture.md)
- 加密与存储设计：[doc/03-crypto-storage.md](doc/03-crypto-storage.md)
- 迭代计划：[doc/04-roadmap.md](doc/04-roadmap.md)
- 待确认决策：[doc/05-open-questions.md](doc/05-open-questions.md)
- 发布打包：[doc/06-release.md](doc/06-release.md)
- 协作记忆：[AGENTS.md](AGENTS.md)
- 变更记录：[CHANGELOG.md](CHANGELOG.md)

## 发布打包

仓库已提供 GitHub Actions `Release` workflow。推送 `v*` 标签后会自动构建后端 Linux/macOS 包、Flutter Windows/macOS/Android/iOS 产物，并把产物上传到对应 GitHub Release。Release 说明从 `CHANGELOG.md` 中与当前 tag 匹配的版本章节读取。

建议发版前先执行 `./scripts/release-preflight.sh --next` 或 `./scripts/release-preflight.sh vX.Y.Z`。脚本会校验工作区、`CHANGELOG.md`、当前 `HEAD` 与目标 tag 的关系，避免把新版本 tag 误推到旧提交上。

iOS 当前输出未签名包，适合作为后续签名/TestFlight 流程输入；正式分发仍需要单独配置 Apple 证书和 Provisioning Profile。

后端发布包内的可执行文件统一命名为 `secure-x`，并附带生产环境 `start.sh`、`stop.sh`、`status.sh` 与 `secure-x.service` 示例。前端各平台应用显示名统一为 `secure-x`。

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

- `start-dev.sh` / `stop-dev.sh` 仍保留为兼容入口，实际转到 `start-dev-all.sh` / `stop-dev-all.sh`
- 后端单独启动：`./scripts/start-dev-be.sh`，单独停止：`./scripts/stop-dev-be.sh`
- 前端单独启动：`./scripts/start-dev-app.sh`，单独停止：`./scripts/stop-dev-app.sh`
- 同时启动/停止：`./scripts/start-dev-all.sh` 与 `./scripts/stop-dev-all.sh`
- `start-dev-app.sh` 支持重复执行，每次默认启动一个新的前端实例，方便两个用户聊天联调
- 多前端调试时建议显式指定实例名，例如 `APP_INSTANCE=user-a ./scripts/start-dev-app.sh` 与 `APP_INSTANCE=user-b ./scripts/start-dev-app.sh`
- 同一个 `APP_INSTANCE` 已运行时不会重复启动，避免两个进程共享同一本地数据命名空间
- 每个 `APP_INSTANCE` 会使用独立本地存储命名空间，隔离后端地址、token、主题、本地聊天缓存等数据
- 停止某个前端实例：`APP_INSTANCE=user-a ./scripts/stop-dev-app.sh`；不传 `APP_INSTANCE` 会停止所有脚本记录的前端实例
- macOS 本地调试若遇到系统安全存储不可用，客户端会自动回退到调试存储，优先保证联调连续性

常用可选变量：

- `FLUTTER_DEVICE=macos APP_INSTANCE=user-a ./scripts/start-dev-app.sh`
- `FLUTTER_DEVICE=ios APP_INSTANCE=user-a ./scripts/start-dev-app.sh`
- `BACKEND_ADDR=127.0.0.1:8081 ./scripts/start-dev-be.sh`，脚本会生成 `.dev/securex-be.yaml` 并通过 `--config` 启动后端

### 单独启动后端

```bash
cd securex-be
cp config.example.yaml config.yaml
chmod 600 config.yaml
go run ./cmd/server --config ./config.yaml
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
- 仓库级协作规范以 [AGENTS.md](AGENTS.md) 为准
