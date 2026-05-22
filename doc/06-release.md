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

前端产物：

- `securex-app-<version>-windows-x64.zip`
- `securex-app-<version>-macos-x64.zip`
- `securex-app-<version>-macos-arm64.zip`
- `securex-app-<version>-android.apk`
- `securex-app-<version>-android.aab`
- `securex-app-<version>-ios-unsigned.zip`

## 版本说明

- Release 标题使用 tag，例如 `Secure X v1.0.0`
- Release 内容从 `CHANGELOG.md` 的最新 `##` 章节自动提取
- 每次准备发版前必须先更新 `CHANGELOG.md`

## iOS 签名边界

当前 workflow 只生成未签名的 iOS `Runner.app` 压缩包，用于验证构建与后续签名流水线输入。正式安装、TestFlight 或 App Store 发布需要补充 Apple 开发者证书、Provisioning Profile 与签名密钥管理。

## 安全注意

- 不要把生产 `config.yaml`、证书、私钥、Provisioning Profile 或 keystore 明文提交到仓库
- 后端包只包含二进制、`config.example.yaml` 与子工程 README
- Android/iOS 正式签名密钥后续应放入 GitHub Secrets 或私有签名服务，不进入 Git 仓库
