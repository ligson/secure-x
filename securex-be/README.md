# securex-be

`securex-be` 是 Secure X 的 Go 后端服务。

## 当前能力

- 健康检查：`GET /healthz`
- 认证：注册、登录、获取当前用户、修改登录密码、更新解锁密码密文配置
- 保险库：密码分类增删改查、登录项增删改查、同步导出；非空分类会阻止删除
- 文件目录：网盘式目录增删改查，目录元数据由客户端加密
- 文件：密文文件普通上传、分片上传、元数据查询与更新、密文下载、删除

## 响应格式

除上传请求体和未来特殊流式场景外，后端 JSON 响应统一为：

```json
{
  "success": true,
  "message": "",
  "httpCode": 200,
  "data": {}
}
```

## 运行方式

```bash
go run ./cmd/server --config ./config.yaml
```

可先复制示例配置：

```bash
cp config.example.yaml config.yaml
chmod 600 config.yaml
```

## 配置文件

后端使用 YAML 配置文件，不再读取 `SECUREX_*` 环境变量。仓库只提交 `config.example.yaml`，真实 `config.yaml` 不应提交。

```yaml
server:
  addr: ":8080"

database:
  dsn: "data/securex.db"

storage:
  fileDir: "data/files"

auth:
  jwtSecret: "replace-with-a-long-random-secret"
```
