# 发布与打包

本文记录 Secure X 的 GitHub Actions 发布约定，方便后续继续维护多端打包流程。

## 触发方式

- 推送 `v*` 标签时自动发布，例如 `v1.0.0`
- 也可以在 GitHub Actions 页面手动运行 `Release` workflow，并填写目标 tag

## 发布内容

后端产物：

- `securex-be-<version>-linux-amd64.tar.gz`
- `securex-be-<version>-linux-arm64.tar.gz`
- `securex-be-<version>-macos-amd64.tar.gz`
- `securex-be-<version>-macos-arm64.tar.gz`

后端包内可执行文件固定命名为 `secure-x`，并附带生产启动脚本 `start.sh`、`stop.sh`、`status.sh` 与 systemd 参考文件 `secure-x.service`。

前端产物：

- `securex-app-<version>-windows-x64.zip`
- `securex-app-<version>-macos-x64.zip`
- `securex-app-<version>-macos-arm64.zip`
- `securex-app-<version>-android.apk`
- `securex-app-<version>-android.aab`
- `securex-app-<version>-ios-unsigned.zip`

前端各平台应用显示名统一为 `secure-x`。

## 版本说明

- Release 标题使用 tag，例如 `Secure X v1.0.0`
- Release 内容从 `CHANGELOG.md` 中与当前 tag 对应的章节自动提取
- 发布章节必须使用 `## [vX.Y.Z] - YYYY-MM-DD` 格式，例如 `## [v1.0.1] - 2026-05-22`
- 每次准备发版前必须先更新 `CHANGELOG.md`
- 用户说“发版”时，默认基于当前最新 `v*` tag 自动递增 patch 版本；例如当前最新为 `v1.0.0`，下一次发版就是 `v1.0.1`
- 发版流程默认顺序为：整理代码与文档、更新对应版本 changelog、提交、打 tag、推送 main 与 tag

## iOS 签名边界

当前 workflow 只生成未签名的 iOS `Runner.app` 压缩包，用于验证构建与后续签名流水线输入。正式安装、TestFlight 或 App Store 发布需要补充 Apple 开发者证书、Provisioning Profile 与签名密钥管理。

## 安全注意

- 不要把生产 `config.yaml`、证书、私钥、Provisioning Profile 或 keystore 明文提交到仓库
- 后端包只包含二进制、`config.example.yaml` 与子工程 README
- Android/iOS 正式签名密钥后续应放入 GitHub Secrets 或私有签名服务，不进入 Git 仓库
- 移动端生产环境建议配置 HTTPS 后端地址；当前 Android 仅为 localhost、`127.0.0.1`、Android 模拟器宿主地址开放明文 HTTP，iOS 仅允许本地网络 HTTP 访问

## 应用内更新

- 客户端设置页提供 `关于` -> `版本更新`，通过 GitHub Release 查询 `ligson/secure-x` 最新版本
- Android 会选择 `securex-app-<version>-android.apk` 下载，并调用系统安装器安装；用户仍需要授权“安装未知应用”
- macOS、Windows、Linux 会选择当前平台对应 release 资产下载，并交给系统打开安装包或压缩包
- iOS 系统不允许普通应用直接下载并安装自身更新，因此只能打开 Release 页面，后续正式分发应接入 TestFlight 或 App Store
