# securex-app

`securex-app` 是 Secure X 的 Flutter 多端客户端，目标平台为：

- `macOS`
- `Windows`
- `Linux`
- `Android`
- `iOS`

不包含 Web 端。

## 当前能力

- 配置后端地址
- 注册
- 登录
- 登录密码修改
- 解锁密码解锁
- 解锁密码修改
- 密码库分类创建、选择、修改与删除
- 登录项创建、搜索、编辑与删除
- 随机密码生成
- 网盘式文件目录进入、返回、新建、编辑与删除
- 加密文件后台分片上传、进度展示、搜索、重命名与删除
- 密文文件下载后客户端解密落盘

## 运行方式

```bash
cd ..
./scripts/start-dev-all.sh
```

首次进入后，在登录页填写后端地址，例如 `http://127.0.0.1:8080`。

调试两个用户聊天时，可以启动多个隔离的前端实例：

```bash
APP_INSTANCE=user-a ./scripts/start-dev-app.sh
APP_INSTANCE=user-b ./scripts/start-dev-app.sh
```

每个 `APP_INSTANCE` 都会隔离本地配置、登录 token、主题与本机聊天密文队列，避免调试用户之间串数据。

## 应用图标

- 图标源图位于 `assets/brand/securex_app_icon_square.png`
- 修改图标设计后，可先运行 `python3 tool/generate_app_icons.py` 重新生成源图，再运行 `dart run flutter_launcher_icons` 生成平台图标

## macOS 调试说明

- macOS 本地 `Debug` 包会优先尝试使用系统 Keychain 保存认证 token
- 如果当前机器的本地签名环境不满足 Keychain 要求，客户端会在 `Debug` 模式下自动回退到本地调试存储，避免每次重启都重新登录
- 日常联调请优先使用根目录 `./scripts/start-dev-*.sh` 与 `./scripts/stop-dev-*.sh`
