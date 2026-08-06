# Deployment

[← README](../README.md) ｜ 觀念先修：[concepts.md](concepts.md) ｜ 詞彙：[CONTEXT.md](../CONTEXT.md)

部署 = 在某台主機上讓某個 environment 跑起來。兩個旋鈕：

| 旋鈕 | 決定什麼 | 值 |
|------|---------|----|
| `MODE` | **Topology**——怎麼對外曝露 | `separate-hosts` ｜ `same-host-by-port` ｜ `same-host-by-domain` |
| `ENV` | **Environment**——載入哪份設定 | `dev` ｜ `qas` ｜ `prod` |

兩個指令，差別只在 **image 從哪來**（見 [concepts.md](concepts.md#image-provenance-build-vs-registry)）：

```bash
make up     MODE=<mode> ENV=<env>                      # 用本機當前 code 現場 build
make deploy MODE=<mode> ENV=<env> IMAGE=… TAG=…        # 拉 CI 測過的映像，不重 build
make down   MODE=<mode> ENV=<env>                      # 停止（兩者共用）
```

有 CI pipeline 時用 `make deploy`（它保住 build-once 的保證）；還沒接 registry、或就是要跑本機這份 code 時用 `make up`。

## Choosing a topology

| Topology | 佈局 | 隔離 | 何時選 | 對外曝露檔 |
|----------|------|------|--------|-----------|
| **A. separate-hosts** | 每個 environment **獨佔一台主機**，前端綁標準 **80** 埠 | **完整**——不同機器 | 有多台機器 / 在意 prod 隔離 | `deploy/compose.separate-hosts.yaml` |
| **B. same-host-by-port** | 三個 environment **同機、不同 port** | **無** | 一台機器、想最快、能接受網址帶 port | `deploy/compose.same-host-by-port.yaml` |
| **C. same-host-by-domain** | 三個 environment **同機**，共用 Traefik 依 domain 導流 | **無** | 一台機器、要 domain、團隊要能連 | `deploy/compose.same-host-by-domain.yaml` |

**選一種用，不是同時跑。** A 是隔離最完整、最貼近真實世界的做法；B 最快上手；C 在同機方案裡最貼近真實 prod。

> B / C 三個環境同機，沒有故障與安全隔離——prod 若重要，用 A。

## Common steps

### 1. Create your repo from this template

GitHub 上按「Use this template」（或 clone 本 repo），改成你的 app。

### 2. Configure each environment

`env/.env.dev`、`env/.env.qas`、`env/.env.prod` 各放該 environment 的**非機密**設定
（`APP_ENV`、`LOG_LEVEL`、以及 topology B 用的 `HTTP_PORT`、topology C 用的 `DOMAIN`）。
真正的密鑰走 CI secrets 或部署時注入，別提交進 repo（見 [roadmap.md](roadmap.md)）。

### 3. Bring it up

見下方各 topology 小節。

---

## A. separate-hosts

每台主機只跑它自己那個 environment，前端佔標準 80 埠，不會與其他 environment 衝突。

```bash
# 在 dev 主機
make up MODE=separate-hosts ENV=dev
# qas 主機：ENV=qas；prod 主機：ENV=prod
```

**連上**：瀏覽器打該主機的位址 `http://<主機 IP 或域名>`。頁面會顯示 `Environment: dev`（前端打 `/api/message` 從後端拿到的）。

**改對外埠**：預設 80。要改成別的（例如 8080），編輯 `deploy/compose.separate-hosts.yaml` 的 `ports: "80:80"` → `"8080:80"`。

**上 production 前還需要**（見 [roadmap.md](roadmap.md)）：真實域名 + DNS 指到 prod 主機、TLS/HTTPS、防火牆強化。

---

## B. same-host-by-port

三個 environment 用不同的 host port 區分，可並存。

| Environment | `HTTP_PORT`（在 `env/.env.*`） | 網址 |
|------|------------------------------|------|
| dev  | 3000 | `http://<host>:3000` |
| qas  | 3001 | `http://<host>:3001` |
| prod | 3002 | `http://<host>:3002` |

三個埠**必須不同**（同機不能重複）。

```bash
make up ENV=dev      # MODE 預設就是 same-host-by-port
make up ENV=qas
make up ENV=prod
make ps              # 看狀態
```

每個 environment 是**獨立的 compose project**（`fullstack-dev` / `fullstack-qas` / `fullstack-prod`，
各自獨立的 network 與 container），dev 的前端只連 dev 的後端，互不干擾。

**連上**：
- 你自己：`http://localhost:3000` / `:3001` / `:3002`
- 團隊（同網路）：`http://<你的機器IP>:3000` 等——topology B 不需要 domain，直接 IP:port
  ```bash
  ipconfig getifaddr "$(route get default | awk '/interface:/{print $2}')"   # 查你的 IP
  ```

**改埠**：改 `env/.env.<env>` 的 `HTTP_PORT`，再重跑 `make up ENV=<env>`。

---

## C. same-host-by-domain

三個 environment 同機、共用同一個 80 埠，靠共用的 Traefik 依 Host 導流。

```
                        ┌─ dev.app.localhost  → dev  這組 container
瀏覽器 → Traefik(:80) ────┼─ qas.app.localhost  → qas  這組 container
                        └─ app.localhost      → prod 這組 container
```

### Prerequisite: a shared Traefik (once per machine)

Traefik **不在本 repo**。你需要另外準備一份整台機器共用的 reverse proxy：建立一個名為 `proxy` 的
external network、佔用 80 埠、並開啟 Docker provider 讓它讀取 container 的 Traefik label。
所有 app、所有 environment 共用這一份，不用每個專案各跑。

### Bring up all three

```bash
make up MODE=same-host-by-domain ENV=dev
make up MODE=same-host-by-domain ENV=qas
make up MODE=same-host-by-domain ENV=prod
make ps
```

每個 environment 靠 env 檔的 `DOMAIN` 註冊到 Traefik。停某一個：`make down MODE=same-host-by-domain ENV=dev`。

### How the domain resolves

網址由 env 檔的 `DOMAIN` 決定。依「誰要連」有三種寫法：

| 誰要連 | `DOMAIN` 寫法 | 要設定什麼 |
|--------|--------------|-----------|
| **只有你自己（本機）** | `dev.app.localhost` | 無——`*.localhost` 瀏覽器自動解析到 127.0.0.1 |
| **團隊（同網路、免 DNS）** | `dev.app.<你的IP>.nip.io` | 無——nip.io 自動解析到該 IP（需連得到外網） |
| **正式對外** | 你的真實域名 | 正規 DNS + TLS + 機器對外曝露 |

**只有你自己**：`env/.env.*` 預設就是 `.localhost`，直接開 `http://dev.app.localhost`、
`http://qas.app.localhost`、`http://app.localhost`。

> `*.localhost` 指的是「**執行瀏覽器那台機器自己**」（127.0.0.1）。**隊友用這個網址只會連到自己的電腦，連不到你。**

**團隊存取（nip.io）**：`任何字.<你的IP>.nip.io` 會自動解析到 `<你的IP>`，零 DNS 設定。先查你機器的對外 IP
（活躍介面**不一定**是 `en0`，別寫死）：

```bash
ipconfig getifaddr "$(route get default | awk '/interface:/{print $2}')"
```

假設是 `10.0.0.5`，**執行時傳入 `DOMAIN`**（**別改 `env/.env.*`**——那是被 git 追蹤的檔案，
IP 一旦 commit 就會進公開 repo，而且 IP 會變）：

```bash
DOMAIN=dev.app.10.0.0.5.nip.io make up MODE=same-host-by-domain ENV=dev
```

隊友（同網路、能連外網）就開 `http://dev.app.10.0.0.5.nip.io`。

**正式對外**：用你自己的真實域名 + 正規 DNS 指到機器 + TLS（見 [roadmap.md](roadmap.md)）。
nip.io 只是過渡方便，不是 production 做法。

---

## Troubleshooting

### `Bind for 0.0.0.0:<port> failed: port is already allocated`

```bash
lsof -nP -iTCP:<port> -sTCP:LISTEN     # 看什麼程式占用
docker ps --filter publish=<port>       # 或看是哪個 container
```

解法：停掉占用者（`docker stop <容器>`），或改埠——topology A 改
`deploy/compose.separate-hosts.yaml`，topology B 改 `env/.env.*` 的 `HTTP_PORT`。
topology C 常見原因是 topology A 也綁了 80，或別的 web server 佔住。

### Topology C 回 404

代表 nip.io / localhost **有解析成功**（請求有到 Traefik），只是 Traefik 沒有對應的路由。逐項檢查：

```bash
docker ps --filter name=traefik                              # 1. Traefik 有起來嗎？
docker ps --format '{{.Names}}\t{{.Networks}}' | grep fullstack   # 2. 環境有起來、且接上 proxy network？
curl -s http://localhost:8080/api/http/routers | grep -oE '"rule":"Host[^"]*"' | sort -u   # 3. 現有哪些 Host 路由
grep DOMAIN env/.env.dev                                     # 4. 打的網址跟 DOMAIN 一致嗎？
```

最常見原因：**`DOMAIN` 沒改**（還是 `.localhost`）卻用 nip.io 網址打——路由是 `Host(dev.app.localhost)`、
不 match nip.io → 404。解法：執行時傳入 `DOMAIN` 重跑。
