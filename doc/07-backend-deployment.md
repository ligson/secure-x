# 后端部署指南

本文说明如何把 Secure X 后端部署到一台普通 Linux 服务器上。文档只覆盖后端服务本身；客户端安装包、移动端签名和应用分发见 [06-release.md](06-release.md)。

## 部署目标

推荐的生产形态：

- 后端进程监听本机地址，例如 `127.0.0.1:8080`
- nginx、Caddy 或其他 HTTPS 反向代理对外提供域名访问
- 后端配置、数据库、密文文件和日志放在部署目录中
- 生产 `config.yaml`、证书、私钥和备份文件不提交到 Git 仓库

部署完成后，客户端后端地址填写你的 HTTPS 地址，例如：

```text
https://securex.example.com
```

## 准备条件

服务器建议：

- Linux x86_64 或 arm64
- 可访问公网 HTTPS 域名
- 已安装 `tar`、`curl`
- 如果使用 systemd 托管，需要有 `systemctl`
- 如果自行编译，需要安装 Go，使用 Release 包则不需要 Go

网络建议：

- 对外开放 `443/TCP`
- 后端实际监听端口只绑定本机，不直接暴露公网
- 如果要使用 Secure X 音视频通话，必须同时部署 LiveKit，并按 LiveKit 要求开放或转发媒体端口

## 获取后端包

从 GitHub Release 下载与你服务器架构匹配的后端包：

- `securex-be-<version>-linux-amd64.tar.gz`
- `securex-be-<version>-linux-arm64.tar.gz`

示例：

```bash
mkdir -p <deploy-dir>
tar -xzf securex-be-<version>-linux-amd64.tar.gz -C <deploy-dir> --strip-components=1
cd <deploy-dir>
```

解压后通常包含：

- `secure-x`：后端可执行文件
- `config.example.yaml`：示例配置
- `start.sh`、`stop.sh`、`status.sh`：目录脚本部署方式
- `secure-x.service`：systemd 参考配置
- `README.md`：后端子项目说明

## 编写配置

复制示例配置：

```bash
cp config.example.yaml config.yaml
chmod 600 config.yaml
```

最小可用配置示例：

```yaml
server:
  addr: "127.0.0.1:8080"
  publicBasePath: ""

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

关键配置说明：

- `server.addr`：后端监听地址。生产环境推荐绑定 `127.0.0.1:<port>`，由反向代理转发。
- `server.publicBasePath`：如果后端被挂在子路径下，例如 `/securex`，这里填写同样的前缀；如果反向代理传递 `X-Forwarded-Prefix`，后端会优先使用请求头。
- `database.dsn`：SQLite 数据库文件路径。生产环境必须持久化并纳入备份。
- `storage.fileDir`：密文文件保存目录。服务端保存的是客户端加密后的密文对象，也必须持久化并纳入备份。
- `logging.dir`：应用日志和访问日志目录。
- `auth.jwtSecret`：JWT 签名密钥。必须替换为高强度随机字符串，不能复用示例值，不能提交到仓库。
- `realtime.livekit`：音视频通话配置。未部署 LiveKit 时保持 `enabled: false`。

生成随机 `jwtSecret` 的示例：

```bash
openssl rand -base64 48
```

创建运行目录：

```bash
mkdir -p data/files logs run
chmod 700 data logs run
```

## 启动后端

目录脚本方式适合先快速验证：

```bash
chmod +x secure-x start.sh stop.sh status.sh
./start.sh
./status.sh
curl -fsS http://127.0.0.1:8080/healthz
```

期望健康检查返回：

```json
{"success":true,"message":"ok","httpCode":200,"data":{"status":"ok"}}
```

停止服务：

```bash
./stop.sh
```

查看日志：

```bash
tail -n 100 logs/secure-x.log
tail -n 100 logs/access.log
tail -n 100 logs/secure-x-console.log
```

## 使用 systemd 托管

Release 包内的 `secure-x.service` 是参考文件，默认示例使用 `/opt/secure-x`。如果你的部署目录不同，需要先替换 `WorkingDirectory`、`ExecStart` 和 `ReadWritePaths`。

典型流程：

```bash
sudo useradd --system --home <deploy-dir> --shell /usr/sbin/nologin securex
sudo chown -R securex:securex <deploy-dir>
sudo install -m 644 secure-x.service /etc/systemd/system/secure-x.service
sudo systemctl daemon-reload
sudo systemctl enable secure-x
sudo systemctl start secure-x
sudo systemctl status secure-x --no-pager
```

如果使用 systemd 托管，建议仍保留同目录下的 `config.yaml`、`data/`、`logs/`，并确保 service 的 `ReadWritePaths` 覆盖这些持久化目录。

## 配置 HTTPS 反向代理

后端需要支持 WebSocket 实时通道，因此反向代理必须传递 `Upgrade` 和 `Connection`。

nginx 示例：

```nginx
server {
    listen 443 ssl;
    server_name securex.example.com;

    ssl_certificate /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }
}
```

如果后端挂在子路径，例如 `https://example.com/securex`：

```nginx
location /securex/ {
    proxy_pass http://127.0.0.1:8080/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Prefix /securex;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_buffering off;
}
```

反向代理配置完成后验证：

```bash
curl -fsS https://securex.example.com/healthz
```

## 客户端连接

客户端首次打开时，在登录页填写后端地址：

```text
https://securex.example.com
```

如果使用子路径部署，填写完整前缀：

```text
https://example.com/securex
```

不要在客户端硬编码 WebSocket、LiveKit、TURN 或其他实时服务端口。客户端会通过后端接口获取实时服务配置。

## 部署 LiveKit 音视频通话

Secure X 的音视频通话依赖自托管 LiveKit。对密码库、文件和普通加密聊天来说，LiveKit 不是必需项；但只要要使用语音或视频通话，LiveKit 就不是可选项。

Secure X 后端只负责：

- 校验发起方和接听方是否有权限通话
- 按通话房间签发短期 LiveKit token
- 通过 `/api/v1/realtime/config` 向客户端下发 LiveKit 地址

真正的音频、视频和 WebRTC ICE/TURN 媒体链路由 LiveKit 承载。客户端不应该硬编码 LiveKit、TURN 或 WebRTC 端口。

### 推荐拓扑

建议按下面的方式理解部署关系：

```text
Secure X client
  | HTTPS / WebSocket
  v
HTTPS reverse proxy
  | HTTP upstream
  v
secure-x backend
  | LiveKit API key / secret
  v
LiveKit server
  | WebRTC ICE / TURN
  v
Secure X client media transport
```

对外入口通常拆成两类：

- Secure X 后端 HTTPS：例如 `https://securex.example.com`
- LiveKit WebSocket：例如 `wss://rtc.example.com` 或 `wss://securex.example.com/livekit`

LiveKit 媒体端口不能只靠普通 HTTP 反向代理解决。WebSocket 信令可以走 nginx/Caddy 的 HTTP 反代，WebRTC ICE、TURN/UDP、TURN/TLS 则必须按四层 TCP/UDP 端口真实转发。

### 端口规划

LiveKit 官方端口说明见 [Ports and firewall](https://docs.livekit.io/transport/self-hosting/ports-firewall/)。常见端口包括：

- API / WebSocket：默认 `7880/TCP`，一般放到 HTTPS 反向代理后面
- ICE UDP 端口段：默认 `50000-60000/UDP`，可用 `rtc.port_range_start` / `rtc.port_range_end` 配置
- ICE UDP mux：可用 `rtc.udp_port` 固定为单个 UDP 端口
- TURN/UDP：默认 `3478/UDP`，可用 `turn.udp_port` 配置
- TURN/TLS：默认 `5349/TCP`，可用 `turn.tls_port` 配置

Secure X 当前客户端的音视频连接要求 TURN relay 链路可用。因此生产部署时不能只保证 `wss://...` 能打开，还必须保证 LiveKit 下发给客户端的 ICE/TURN 候选可从公网真实连通。

小规模私有部署可以采用下面两种模式之一。

### 模式 A：独立 LiveKit 域名 + 少量 UDP 端口

适合有公网服务器、能开放 UDP 端口的环境：

- `443/TCP`：HTTPS 反向代理到 Secure X 后端和 LiveKit WebSocket
- `5349/UDP`：LiveKit TURN/UDP
- `50000/UDP`：LiveKit RTC UDP mux
- `50001-50010/UDP`：LiveKit TURN relay 范围

端口数量可以继续按并发量调整。并发越高，relay 范围越需要放大。关键是不要让 `rtc.udp_port` 和 `turn.relay_range_start` 使用同一个端口。

### 模式 B：TURN/TLS 走 443

适合 UDP 经常被阻断，或希望提高移动网络穿透率的环境：

- LiveKit WebSocket 仍走 HTTPS 反向代理
- TURN/TLS 使用独立 TURN 域名
- 如果公网 `443/TCP` 已经承载普通 HTTPS，入口层必须做四层 SNI 分流

注意：HTTP `location` 规则不能处理 TURN/TLS。TURN/TLS 是四层 TLS 流量，不是 HTTP 请求。把 TURN/TLS 直接转到普通 HTTPS 反代入口，会导致客户端拿到不可用 TURN 端点，表现为入房失败或 ICE candidate pair 失败。

### LiveKit 配置示例

下面是小规模单节点部署示例。请替换域名、公网 IP、API key 和 secret。

```yaml
port: 7880
bind_addresses:
  - "0.0.0.0"

rtc:
  # NAT、Docker bridge、frp 或端口转发场景下，必须让客户端看到真实公网入口。
  # 如果服务器本机直接拥有公网 IP，也可以按实际情况使用 use_external_ip。
  node_ip: "<public-ip>"
  use_external_ip: false

  # 使用单个 UDP mux 端口，减少需要开放的公网端口数量。
  udp_port: 50000
  stun_servers: []
  allow_tcp_fallback: true

turn:
  enabled: true
  domain: "turn.example.com"

  # TURN/UDP 端口。也可以用 3478，关键是公网入口、LiveKit 配置和客户端收到的候选要一致。
  udp_port: 5349

  # 如果启用 TURN/TLS，需要使用受信任 CA 签发的证书；自签证书通常会被客户端拒绝。
  # tls_port: 5349
  # cert_file: /etc/livekit/certs/fullchain.pem
  # key_file: /etc/livekit/certs/privkey.pem

  # relay 端口范围不要和 rtc.udp_port 冲突。
  relay_range_start: 50001
  relay_range_end: 50010

keys:
  <livekit-api-key>: <livekit-api-secret>

logging:
  level: info
  pion_level: warn

room:
  auto_create: true
  empty_timeout: 300
  departure_timeout: 20
```

### Docker Compose 示例

如果使用 Docker bridge 网络，需要显式映射 LiveKit HTTP、TURN 和 UDP relay 端口：

```yaml
services:
  livekit:
    image: livekit/livekit-server:latest
    container_name: livekit
    restart: unless-stopped
    command: --config /etc/livekit/livekit.yaml
    volumes:
      - ./livekit.yaml:/etc/livekit/livekit.yaml:ro
      - ./certs:/etc/livekit/certs:ro
    ports:
      - "127.0.0.1:7880:7880/tcp"
      - "5349:5349/udp"
      - "50000:50000/udp"
      - "50001-50010:50001-50010/udp"
```

如果你的平台支持 host networking，LiveKit 官方更推荐在需要直接处理大量 UDP 媒体端口时使用 host networking，减少 Docker 端口映射和 NAT 带来的候选地址问题。无论用哪种方式，都要以客户端实际收到的 ICE/TURN 候选是否公网可达为准。

### 反向代理 LiveKit WebSocket

如果 LiveKit WebSocket 使用独立域名：

```nginx
server {
    listen 443 ssl;
    server_name rtc.example.com;

    ssl_certificate /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:7880;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }
}
```

如果 LiveKit WebSocket 挂在 Secure X 同域名子路径：

```nginx
location /livekit/ {
    proxy_pass http://127.0.0.1:7880/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_buffering off;
}
```

后端配置中的 `realtime.livekit.url` 必须和客户端能访问的 WebSocket 入口一致：

启用 LiveKit 的后端配置示例：

```yaml
realtime:
  iceServers: []
  livekit:
    enabled: true
    url: "wss://rtc.example.com"
    apiKey: "replace-with-livekit-api-key"
    apiSecret: "replace-with-livekit-api-secret"
    turnMode: "turn_tls_443"
```

### 关键经验

这部分是实际排障中最容易踩坑的地方：

- 后端能签发 LiveKit token，只代表鉴权和房间凭证正常，不代表媒体链路可用。
- `curl https://rtc.example.com/` 返回 `OK`，只代表 LiveKit WebSocket/HTTP 入口可达，不代表 WebRTC UDP/TURN 可用。
- LiveKit 日志出现 `starting RTC session` 后，如果随后是 `Failed to ping without candidate pair`、`failed to get server reflexive address`、`removing participant without connection`，通常是 ICE/TURN 端口、候选地址或证书链问题。
- 如果日志出现 `TLS handshake failed`、`unknown ca`，优先检查 TURN/TLS 证书是否由客户端信任的 CA 签发、证书链是否完整、TURN 域名是否和证书匹配。
- Docker、NAT、frp、端口转发环境下，不能只映射端口，还要确保 LiveKit 广告给客户端的地址就是公网入口。必要时显式配置 `rtc.node_ip` 或使用适合当前环境的外部 IP 配置。
- `rtc.udp_port` 和 `turn.relay_range_start` 不要冲突。一个端口不能同时承担 RTC UDP mux 和 TURN relay 起始端口。
- TURN relay 范围不能只在 LiveKit 容器里开放，还必须从公网入口一路转发到 LiveKit。
- 修改 LiveKit 配置后必须确认容器或进程已经重载。只改配置文件但旧进程没有重启，不会生效。
- 如果 Docker stop/restart 某个 LiveKit 容器异常卡住，不要反复堆积管理命令。可以先启动一个新 LiveKit 容器，用新端口验证后，再把 nginx/frp upstream 切到新容器，最后在维护窗口处理旧容器。
- 音视频通了以后，再逐步收紧端口范围和防火墙规则；不要一开始就把问题同时混在证书、SNI、frp、Docker、端口范围和客户端版本里。

### 验证顺序

建议按下面顺序排查，不要只看客户端提示：

1. 检查 Secure X 后端健康：

```bash
curl -fsS http://127.0.0.1:8080/healthz
```

2. 检查 LiveKit WebSocket/HTTP 入口：

```bash
curl -fsS https://rtc.example.com/
```

3. 发起一次通话，看后端是否签发 LiveKit token。

后端日志应能看到通话凭证签发记录。如果没有，先排查 Secure X 后端配置、LiveKit API key/secret、好友或群成员权限。

4. 看 LiveKit 是否开始 RTC session。

如果 LiveKit 没有任何入房日志，说明客户端没有真正进入 LiveKit 房间，优先排查后端下发的 `realtime.livekit.url`、反向代理路径、客户端版本和 token 请求。

5. 抓公网 UDP 包。

```bash
sudo tcpdump -ni any 'udp and (port 5349 or portrange 50000-50010)'
```

发起通话时如果公网入口完全没有 UDP 包，说明客户端没有打到该 TURN/ICE 入口，或者还没走到 ICE 阶段。如果公网有包但 LiveKit 侧没有包，排查 frp/NAT/防火墙转发。如果 LiveKit 侧有包但仍无 candidate pair，排查 LiveKit 候选地址、relay 范围、证书和端口冲突。

6. 观察 LiveKit 成功迹象。

成功时通常会看到参与者连接、candidate 选中、轨道发布/订阅等日志。失败时常见日志是 candidate pair 失败、DTLS/SCTP 未启动、participant without connection 被移除。

## 备份

必须备份：

- `config.yaml`
- SQLite 数据库文件，例如 `data/securex.db`
- SQLite WAL/SHM 文件，如果服务运行中备份，需要一并考虑
- 密文文件目录，例如 `data/files/`
- 生产日志，按需要保留

推荐先停止后端再做简单文件备份：

```bash
./stop.sh
tar -czf secure-x-backup-<date>.tar.gz config.yaml data logs
./start.sh
```

如果不能停机，建议使用 SQLite 在线备份能力或在业务低峰期做一致性快照。不要只复制单个 `.db` 文件而忽略运行中的 WAL 文件。

## 升级

升级前：

```bash
./status.sh
./stop.sh
tar -czf secure-x-before-upgrade-<date>.tar.gz config.yaml data logs secure-x
```

替换新版本：

```bash
tar -xzf securex-be-<new-version>-linux-amd64.tar.gz -C /tmp/secure-x-new
cp /tmp/secure-x-new/secure-x ./secure-x
cp /tmp/secure-x-new/start.sh ./start.sh
cp /tmp/secure-x-new/stop.sh ./stop.sh
cp /tmp/secure-x-new/status.sh ./status.sh
chmod +x secure-x start.sh stop.sh status.sh
```

保留现有的 `config.yaml`、`data/`、`logs/`，不要用示例配置覆盖生产配置。

启动并验证：

```bash
./start.sh
./status.sh
curl -fsS http://127.0.0.1:8080/healthz
```

如果使用 systemd：

```bash
sudo systemctl restart secure-x
sudo systemctl status secure-x --no-pager
```

## Docker 镜像部署

后端也可以构建为 Docker 镜像运行。镜像只包含后端二进制和示例配置，真实生产配置、SQLite 数据库、密文文件和日志必须通过挂载提供，不要打进镜像。

### 构建并推送多架构镜像

仓库脚本默认使用 `docker buildx` 构建 `linux/amd64` 与 `linux/arm64`，并推送到 `ligson/secure-x`：

```bash
scripts/build-image.sh v1.0.29
```

常用参数：

```bash
IMAGE_NAME=ligson/secure-x scripts/build-image.sh v1.0.29
TAG_LATEST=true scripts/build-image.sh v1.0.29
PLATFORMS=linux/amd64,linux/arm64 scripts/build-image.sh v1.0.29
```

本地只验证单平台构建时，可关闭推送：

```bash
PUSH=false PLATFORMS=linux/amd64 scripts/build-image.sh dev-local
```

推送前需要先完成 Docker Hub 登录：

```bash
docker login
```

### 运行容器

准备生产配置：

```bash
mkdir -p data logs
cp securex-be/config.example.yaml config.yaml
chmod 640 config.yaml
sudo chown -R 10001:10001 config.yaml data logs
```

镜像内后端进程使用非 root 用户 `10001:10001` 运行。Linux bind mount 部署时，需要确保 `config.yaml` 可读，`data/` 和 `logs/` 可写。

至少修改：

- `auth.jwtSecret`：替换为高强度随机值
- `database.dsn`：容器内建议使用 `/app/data/securex.db`
- `storage.fileDir`：容器内建议使用 `/app/data/files`
- `logging.dir`：容器内建议使用 `/app/logs`
- `server.addr`：容器内建议保持 `:8080`
- `realtime.livekit`：如需语音/视频通话，按自托管 LiveKit 实际入口填写

示例运行命令：

```bash
docker run -d \
  --name secure-x \
  --restart unless-stopped \
  -p 127.0.0.1:8080:8080 \
  -v ./config.yaml:/app/config.yaml:ro \
  -v ./data:/app/data \
  -v ./logs:/app/logs \
  ligson/secure-x:v1.0.29
```

验证：

```bash
docker logs --tail 100 secure-x
curl -fsS http://127.0.0.1:8080/healthz
```

容器前面仍建议放 HTTPS 反向代理，并确保 WebSocket 代理可用。LiveKit/TURN 的公网入口继续按本文 LiveKit 部署章节处理，不能把 TURN/TLS 当作普通 HTTP location 转发。

## 安全检查清单

上线前至少确认：

- `config.yaml` 权限为 `600` 或同等限制
- `auth.jwtSecret` 已替换为高强度随机值
- 后端监听本机地址，不直接暴露明文 HTTP 到公网
- 对外访问使用 HTTPS
- 反向代理已支持 WebSocket
- 数据库和密文文件目录已纳入备份
- 生产证书、私钥、配置、备份包没有提交到 Git
- 日志中不记录 token、密钥、密文 payload、生产配置内容或其他敏感信息

## 常见问题

### 健康检查不通

先在服务器本机检查：

```bash
./status.sh
curl -v http://127.0.0.1:8080/healthz
tail -n 100 logs/secure-x.log
```

本机通、公网不通时，优先排查 HTTPS 证书、DNS、反向代理 upstream 和防火墙。

### 客户端无法实时收发聊天

确认反向代理包含 WebSocket 相关配置：

- `proxy_http_version 1.1`
- `proxy_set_header Upgrade $http_upgrade`
- `proxy_set_header Connection "upgrade"`
- 较长的 `proxy_read_timeout`

### 音视频通话进入房间失败

先区分是后端凭证问题还是媒体 ICE/TURN 问题：

- 后端日志如果没有 LiveKit token 签发记录，排查好友关系、共同群成员关系、LiveKit 配置和 API key/secret。
- 后端能签发 token，但 LiveKit 日志出现 candidate pair 失败时，排查 LiveKit 公网候选、TURN 域名、UDP/TCP 端口、Docker/NAT/frp 转发和证书信任链。
- 客户端不要硬编码 LiveKit 或 TURN 端口，应由后端实时配置接口下发。

### SQLite 数据库无法写入

检查部署目录权限：

```bash
ls -la data
ls -la data/securex.db*
```

如果使用 systemd，确认 `User`、`Group` 和 `ReadWritePaths` 允许写入数据库、文件目录和日志目录。
