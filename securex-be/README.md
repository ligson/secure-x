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

logging:
  dir: "logs"
  appFile: "secure-x.log"
  accessFile: "access.log"

auth:
  jwtSecret: "replace-with-a-long-random-secret"

realtime:
  iceServers: []
  livekit:
    enabled: false
    url: ""
    apiKey: ""
    apiSecret: ""
    turnMode: ""
```

语音/视频通话建议部署自托管 LiveKit。开启后，后端会用 `apiKey/apiSecret` 为已授权的好友或共同群成员签发短期房间 token；客户端通过 `/api/v1/realtime/config` 获取 LiveKit 地址，不需要在 App 中硬编码 RTC 端口。

## 生产部署脚本

Release 后端包中的可执行文件名为 `secure-x`，并包含以下生产辅助文件：

- `start.sh`：使用当前目录下的 `secure-x` 与 `config.yaml` 后台启动服务
- `stop.sh`：根据 `run/secure-x.pid` 停止服务
- `status.sh`：查看当前服务进程状态
- `secure-x.service`：systemd 参考配置，默认路径为 `/opt/secure-x`

首次部署建议：

```bash
cp config.example.yaml config.yaml
chmod 600 config.yaml
./start.sh
./status.sh
```

默认日志：

- 应用日志：`logs/secure-x.log`
- 访问日志：`logs/access.log`
- 脚本启动兜底日志：`logs/secure-x-console.log`
