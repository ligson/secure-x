# 发布与打包

本文记录 Secure X 的 GitHub Actions 发布约定，方便后续继续维护多端打包流程。

## 触发方式

- 推送 `v*` 标签时自动发布，例如 `v1.0.0`
- 也可以在 GitHub Actions 页面手动运行 `Release` workflow，并填写目标 tag
- 手工运行时只能选择“已经存在且已指向正确 release commit”的 tag，不能拿未来版本号直接空跑

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
- `securex-app-<version>-ios.ipa`，当已配置 iOS 签名密钥时生成
- `securex-app-<version>-ios-unsigned.zip`，当未配置 iOS 签名密钥时作为构建兜底产物

前端各平台应用显示名统一为 `secure-x`。

## 版本说明

- Release 标题使用 tag，例如 `Secure X v1.0.0`
- Release 内容从 `CHANGELOG.md` 中与当前 tag 对应的章节自动提取
- Flutter Release 构建时必须把 tag 中的语义版本注入 `--build-name`，并生成单调递增的 `--build-number`，避免安装包文件名已经升级、应用内部版本号却仍停留在旧值
- 发布章节必须使用 `## [vX.Y.Z] - YYYY-MM-DD` 格式，例如 `## [v1.0.1] - 2026-05-22`
- 每次准备发版前必须先更新 `CHANGELOG.md`
- 用户说“发版”时，默认基于当前最新 `v*` tag 自动递增 patch 版本；例如当前最新为 `v1.0.0`，下一次发版就是 `v1.0.1`
- 发版流程默认顺序为：整理代码与文档、更新对应版本 changelog、提交、打 tag、推送 main 与 tag
- 发版前默认先执行 `./scripts/release-preflight.sh <tag>`，或者用 `./scripts/release-preflight.sh --next` 让脚本给出下一个 patch 版本并校验当前状态
- 预检通过后再执行 `git tag <tag>`、`git push origin main`、`git push origin <tag>`；不要先 push tag 再补 release commit，也不要移动已有 tag
- workflow 已增加校验：手工或自动触发时，GitHub Actions 会检查当前检出的提交是否与目标 tag 指向完全一致，避免错误提交冒充某个版本发布

## 本地预检

发版前建议固定执行：

```bash
./scripts/release-preflight.sh --next
```

或显式检查目标版本：

```bash
./scripts/release-preflight.sh v1.0.7
```

脚本会检查：

- 当前工作区是否干净
- `CHANGELOG.md` 是否已经存在目标版本章节
- 当前 `HEAD` 是否已经包含该版本 changelog
- 目标 tag 是否已存在于本地或远程

## 移动端签名与蒲公英分发

Release workflow 支持在 GitHub Actions 中自动签名 Android / iOS 并上传蒲公英。签名材料和蒲公英 API Key 只允许放在 GitHub Secrets / Variables，不进入 Git 仓库。

Android 签名需要配置以下 GitHub Secrets：

- `ANDROID_KEYSTORE_BASE64`：release keystore 的 base64 文本
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

未配置 `ANDROID_KEYSTORE_BASE64` 时，workflow 会沿用 Flutter/Gradle 的本地 debug 签名兜底，仍可产出构建产物，但不应作为正式内测包使用。

iOS 签名需要配置以下 GitHub Secrets：

- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`：Apple Distribution `.p12` 的 base64 文本
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_BASE64`：Ad Hoc 或企业分发 `.mobileprovision` 的 base64 文本
- `IOS_TEAM_ID`
- `IOS_PROVISIONING_PROFILE_NAME`：可选；未配置时 workflow 会从 profile 中读取名称

iOS 签名还支持 GitHub Variable：

- `IOS_EXPORT_METHOD`：可选，默认 `ad-hoc`；企业分发可设为 `enterprise`

蒲公英上传需要配置以下 GitHub Secrets / Variables：

- Secret `PGYER_API_KEY`
- Secret `PGYER_BUILD_PASSWORD`：当安装方式为密码安装时必填
- Variable `PGYER_BUILD_INSTALL_TYPE`：可选，默认 `2`，表示密码安装

workflow 会上传 Android APK 和签名后的 iOS IPA 到蒲公英；AAB 仍只作为 GitHub Release 资产保留。未配置 `PGYER_API_KEY` 时会跳过蒲公英上传，不影响 GitHub Release。

本地把二进制签名材料转成 base64 时，建议使用：

```bash
base64 -i securex-release.jks | pbcopy
base64 -i ios_distribution.p12 | pbcopy
base64 -i securex.mobileprovision | pbcopy
```

## 安全注意

- 不要把生产 `config.yaml`、证书、私钥、Provisioning Profile 或 keystore 明文提交到仓库
- 后端包只包含二进制、`config.example.yaml` 与子工程 README
- Android/iOS 正式签名密钥必须放入 GitHub Secrets 或私有签名服务，不进入 Git 仓库
- 移动端生产环境建议配置 HTTPS 后端地址；当前 Android 仅为 localhost、`127.0.0.1`、Android 模拟器宿主地址开放明文 HTTP，iOS 仅允许本地网络 HTTP 访问

## 应用内更新

- 客户端设置页提供 `关于` -> `版本更新`，通过 GitHub Release 查询 `ligson/secure-x` 最新版本
- Android 会选择 `securex-app-<version>-android.apk` 下载，并调用系统安装器安装；用户仍需要授权“安装未知应用”
- macOS、Windows、Linux 会选择当前平台对应 release 资产下载，并交给系统打开安装包或压缩包
- iOS 系统不允许普通应用直接下载并安装自身更新，因此只能打开 Release 页面，后续正式分发应接入 TestFlight 或 App Store
