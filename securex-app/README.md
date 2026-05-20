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
- 主密码解锁
- 文件夹创建、搜索、编辑与删除
- 登录项创建、搜索、编辑与删除
- 随机密码生成
- 加密文件上传、重命名与删除
- 密文文件下载后客户端解密落盘

## 运行方式

```bash
flutter run -d macos
```

首次进入后，在登录页填写后端地址，例如 `http://127.0.0.1:8080`。
