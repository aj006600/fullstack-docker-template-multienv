# Deployment

[← README](../README.md) ｜ 觀念先修：[concepts.md](concepts.md) ｜ 詞彙：[CONTEXT.md](../CONTEXT.md)

部署 = 在某台主機上讓某個 environment 跑起來。兩個旋鈕：

| 旋鈕 | 決定什麼 | 值 |
|------|---------|----|
| `MODE` | **Topology**——怎麼對外曝露 | `separate-hosts` ｜ `same-host-by-port` ｜ `same-host-by-domain` |
| `ENV` | **Environment**——載入哪份設定 | `dev` ｜ `qas` ｜ `prod` |

部署在**目標主機**上執行，拉 CI 測過的不可變映像，不重 build：

```bash
make deploy MODE=<mode> ENV=<env> IMAGE=… TAG=…        # 拉指定版本並啟動
make down   MODE=<mode> ENV=<env>                      # 停止
```

`TAG` 是 `:sha`（dev/qas）或 `vX.Y.Z`（prod），由 promotion 流程決定；rollback 就換回舊的 sha。
見 [cicd.md](cicd.md)。

> **主機必須是 amd64 Linux。** CI 只建 amd64——在 Apple Silicon 的開發機上 `make deploy` 會失敗
> （`no matching manifest for linux/arm64`）。開發機請用 `make dev`；理由與例外見 [roadmap.md](roadmap.md)
> 與本文最後一節。

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

### 3. Push and let CI build

`make deploy` 拉的是 registry 裡的映像，所以要先 merge 到 `main`、讓 CI 建出該 commit 的 `:sha`。
之後在主機上帶那個 sha 部署。

### 4. Deploy

見下方各 topology 小節。

---

## A. separate-hosts

每台主機只跑它自己那個 environment，前端佔標準 80 埠，不會與其他 environment 衝突。

```bash
# 在 dev 主機
make deploy MODE=separate-hosts ENV=dev \
    IMAGE=ghcr.io/<your-account>/<repo> TAG=<git-sha>
# qas 主機：ENV=qas；prod 主機：ENV=prod TAG=vX.Y.Z
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
# MODE 預設就是 same-host-by-port
make deploy ENV=dev  IMAGE=ghcr.io/<your-account>/<repo> TAG=<git-sha>
make deploy ENV=qas  IMAGE=… TAG=…
make deploy ENV=prod IMAGE=… TAG=vX.Y.Z
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

**改埠**：改 `env/.env.<env>` 的 `HTTP_PORT`，再重跑 `make deploy ENV=<env> …`。
（env 檔是主機上的本機檔案，不在映像裡，所以改完不需要重新 build。）

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
make deploy MODE=same-host-by-domain ENV=dev  IMAGE=ghcr.io/<your-account>/<repo> TAG=<git-sha>
make deploy MODE=same-host-by-domain ENV=qas  IMAGE=… TAG=…
make deploy MODE=same-host-by-domain ENV=prod IMAGE=… TAG=vX.Y.Z
make ps
```

每個 environment 靠 env 檔的 `DOMAIN` 註冊到 Traefik。停某一個：`make down MODE=same-host-by-domain ENV=dev`。

### How the domain resolves

網址由 env 檔的 `DOMAIN` 決定。依「誰要連」有三種寫法：

| 情境 | `DOMAIN` 寫法 | 要設定什麼 |
|--------|--------------|-----------|
| **在主機上自己驗證** | `dev.app.localhost` | 無——`*.localhost` 瀏覽器自動解析到 127.0.0.1 |
| **內網、免 DNS** | `dev.app.<主機IP>.nip.io` | 無——nip.io 自動解析到該 IP（需連得到外網） |
| **正式對外** | 你的真實域名 | 正規 DNS + TLS + 機器對外曝露 |

**`.localhost`（預設）**：只在**主機自己**上開瀏覽器時有效——`*.localhost` 永遠指向 127.0.0.1，
所以從別台機器打這個網址只會連到那台機器自己。適合部署後在主機上 `curl` 驗證。

**`.nip.io`（內網存取）**：`任何字.<IP>.nip.io` 會自動解析到 `<IP>`，零 DNS 設定。先查主機的對外 IP
（活躍介面**不一定**是 `en0`，別寫死）：

```bash
ipconfig getifaddr "$(route get default | awk '/interface:/{print $2}')"   # macOS
hostname -I | awk '{print $1}'                                            # Linux
```

假設是 `10.0.0.5`，**執行時傳入 `DOMAIN`**（**別改 `env/.env.*`**——那是被 git 追蹤的檔案，
IP 一旦 commit 就會進公開 repo，而且 IP 會變）：

```bash
DOMAIN=dev.app.10.0.0.5.nip.io make deploy MODE=same-host-by-domain ENV=dev IMAGE=… TAG=…
```

同網路、能連外網的人就能開 `http://dev.app.10.0.0.5.nip.io`。

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

---

## Running an environment on your dev machine

日常開發用 `make dev` 就好。但偶爾你會想在開發機上看某個 environment 的完整部署形態——
例如驗證 topology 設定、或 debug「dev stage 正常、runtime stage 壞掉」這種只在非 root 下出現的問題。

**這個 template 刻意不提供對應的 `make` target**，因為同一個指令在正式主機上執行就是反模式
（在主機重 build 會破壞 build-once 的保證，見 [concepts.md](concepts.md#two-commands-two-places)）。
真的需要時手動執行：

```bash
COMPOSE_PROJECT_NAME=fullstack-qas docker compose \
  -f compose.yaml -f deploy/compose.same-host-by-port.yaml \
  --env-file env/.env.qas up -d --build

make down MODE=same-host-by-port ENV=qas      # 停止
```

`COMPOSE_PROJECT_NAME` 不能省——省了會用資料夾名當 project 名，跟 `make dev` 的 container 互相覆蓋。

注意這樣跑起來的東西：**沒有經過 CI 把關，image 名是 `fullstack-backend:latest`、追不到版本**。
它是臨時檢查手段，不是部署方式——不要讓別人長期連它。
