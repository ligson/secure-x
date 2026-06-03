# Secure X Docker Compose 部署模板

本目录提供在同一台服务器上部署 Secure X 后端和 LiveKit 的 Docker Compose 模板。

## 文件说明

- `docker-compose.yml`：后端和 LiveKit 服务
- `.env.example`：Compose 变量示例
- `securex/config.example.yaml`：后端配置模板
- `livekit/livekit.example.yaml`：LiveKit 配置模板
- `nginx/securex.conf.example`：HTTPS 反向代理示例

## 快速开始

```bash
cp .env.example .env
cp securex/config.example.yaml securex/config.yaml
cp livekit/livekit.example.yaml livekit/livekit.yaml
mkdir -p securex/data securex/logs livekit/certs
chmod 600 .env securex/config.yaml livekit/livekit.yaml
# Linux bind mount 部署时需要让后端容器用户可写数据和日志目录。
sudo chown -R 10001:10001 securex/data securex/logs
```

编辑复制出来的文件，并替换所有占位值：

- 后端公开访问地址和 LiveKit URL
- `auth.jwtSecret`
- LiveKit API key and secret
- LiveKit 公网 `node_ip`
- TURN 域名；如启用 TURN/TLS，还要配置证书路径
- 如果不使用 `50001-50010`，需要同时修改 `docker-compose.yml` 和 `livekit/livekit.yaml` 中的 relay 端口范围

启动服务：

```bash
docker compose up -d
docker compose ps
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS http://127.0.0.1:7880/
```

然后参考 `nginx/securex.conf.example` 配置 HTTPS 反向代理。
