# fullstack-docker-template-multienv

前後端分離 + 多環境（dev / qas / prod）的容器範本：React(Vite) 前端 + FastAPI 後端，
用 docker compose 兜起來，CI/CD 遵循「build 一次、依序 promote」的業界最佳實踐。

> 核心原則（12-factor）：**一份程式碼、一組映像、設定隨環境變**。絕不複製程式碼，環境差異只在設定。

## 結構

```
.
├── backend/                    # FastAPI + uv（單階段、非 root）
│   ├── app/main.py             # /health、/api/message（回傳目前環境）
│   ├── app/config.py           # pydantic-settings：從環境變數讀設定
│   ├── tests/
│   ├── pyproject.toml · uv.lock
│   └── Dockerfile
├── frontend/                   # React + Vite（node→nginx 多階段）
│   ├── src/App.jsx             # 載入時打 /api/message 顯示結果
│   ├── nginx.conf              # 供靜態檔 + 反向代理 /api 到 backend
│   ├── package.json · package-lock.json
│   └── Dockerfile
├── compose.yaml                # base：只定義服務與內部接線（不決定對外曝露）
├── compose.dev.yaml            # 本機開發覆寫：開 localhost 埠 + 後端熱重載
├── deploy/                     # 三種部署模式（同一個 app、只差怎麼曝露）
│   ├── compose.separate-hosts.yaml    # A：每環境各自一台主機（最佳實踐）
│   ├── compose.same-host-by-port.yaml # B：同機、不同 port
│   └── compose.same-host-by-domain.yaml # C：同機、Traefik 依 domain
├── env/{.env.dev,.env.qas,.env.prod}   # 各環境設定 + HTTP_PORT(B) + DOMAIN(C)
├── Makefile                    # make dev / up-separate-hosts / up-port-* / up-domain-*
└── .github/workflows/ci-cd.yml # 測前後端 → build 兩映像各一次 → promote dev→qas→prod
```

> 同一個 app，**三種部署模式擇一使用**（不是同時跑）——差別只在「怎麼對外曝露」。
> C 模式用的共用 Traefik 不在本 repo，在獨立的 **[`traefik-proxy`](../traefik-proxy)** repo。

## 前後端怎麼溝通

瀏覽器只打 `frontend`，`/api/*` 由 frontend 的 nginx 反向代理到 `backend`（同源，後端免處理 CORS）。
`/api/message` 會回傳目前環境，所以切換 `APP_ENV` 時前端顯示的環境也會跟著變。

```
瀏覽器 → frontend(nginx:80) ──/api/──▶ backend(uvicorn:8000)
                          └─ 其他路徑 = SPA 靜態檔
```

## 快速開始（本機單環境開發）

```bash
make dev     # APP_ENV=dev：前後端起來，後端熱重載（不經 Traefik）
# 前端 → http://localhost:3000（會顯示 backend 回傳的環境）
# 後端 → http://localhost:8000/health
```

## 三種部署模式（擇一）

同一個 app，三種「怎麼把環境跑起來/曝露」的做法。**選一種用**，不是同時跑。

| 模式 | 拓撲 | 隔離/最佳實踐 | 何時選 |
|------|------|--------------|--------|
| **A. separate-hosts** | 每環境**各自一台主機**，標準 80 埠 | 最佳實踐、完整隔離 | 有多台機器 / 在意 prod 隔離 |
| **B. same-host-by-port** | 三環境**同機、不同 port** | 最簡妥協、無隔離 | 只有一台機器、想最快、能接受 `IP:port` |
| **C. same-host-by-domain** | 三環境**同機、Traefik 依 domain** | 同機但用 domain（貼近真實） | 只有一台機器、要 domain、團隊存取 |

### A. separate-hosts（最佳實踐）

在**每個環境自己的主機**上跑單一環境，前端佔標準 80 埠：

```bash
make up-separate-hosts ENV=dev    # 在 dev 主機
make up-separate-hosts ENV=qas    # 在 qas 主機
make up-separate-hosts ENV=prod   # 在 prod 主機
```
存取：`http://<該主機位址>`。各環境實體分離，互不影響。

### B. same-host-by-port（最簡妥協）

三環境擠一台機器，用不同 port 區分（埠由 env 檔的 `HTTP_PORT` 決定）：

```bash
make up-port-dev     # → http://<host>:3000
make up-port-qas     # → http://<host>:3001
make up-port-prod    # → http://<host>:3002
make down-port-dev   # 停 dev（其他不受影響）
```
最快上手，缺點是 URL 帶 port、沒 domain。

### C. same-host-by-domain（同機 + Traefik）

三環境擠一台機器，但用 **domain** 區分（同 port 80、靠 Traefik 導流），貼近真實 prod：

```bash
# 前置（整台機器一次）：到 traefik-proxy repo 啟動共用 Traefik
cd ../traefik-proxy && make up && cd -

make up-domain-dev   # → http://dev.app.localhost
make up-domain-qas   # → http://qas.app.localhost
make up-domain-prod  # → http://app.localhost
make down-domain-dev # 停 dev
```

**domain 怎麼被解析（重要）**——網址由 env 檔的 `DOMAIN` 決定：

| 誰要連 | `DOMAIN` 寫法 | 說明 |
|--------|--------------|------|
| **只有你自己（本機）** | `dev.app.localhost` | `*.localhost` 指的是**執行瀏覽器那台機器自己**（127.0.0.1）。**隊友打這個只會連到他自己的電腦、連不到你。** |
| **團隊（同網路、免 DNS）** | `dev.app.<你的IP>.nip.io` | nip.io 把 `*.<IP>.nip.io` 自動解析到該 IP。隊友需在同一網路、且能連外網。查你的 IP 見下方 |
| **正式對外** | 你的真實域名 | 正規 DNS + TLS + 機器對外曝露 |

> **要給團隊連**：**執行時傳入** `DOMAIN`（**別改 `env/.env.*`**——它被 git 追蹤，IP 一旦 commit 就會進**公開 repo**，而且 IP 會變）：
>
> ```bash
> DOMAIN=dev.app.<你的IP>.nip.io make up-domain-dev   # qas/prod 同理
> ```
>
> 查本機對外 IP（活躍介面**不一定**是 `en0`，別寫死）：`ipconfig getifaddr "$(route get default | awk '/interface:/{print $2}')"`

### 共通提醒

- B、C 都是**三環境同機**，沒有真正的故障/安全隔離——prod 若很重要，選 A（獨立主機）。
- B、C 各環境是**獨立的 compose project**（獨立網路/容器），dev 的前端只連 dev 的後端。
- **對外正式 prod** 不管哪種模式都還需要：真實域名 + TLS + 對外曝露 + 安全強化，屬於需要再加。

## 疑難排解：埠衝突

各模式用到的 host 埠：

| 指令 | 綁的 host 埠 |
|------|------------|
| `make dev` | 3000（前端）+ 8000（後端） |
| A `make up-separate-hosts` | 80（前端） |
| B `make up-port-dev\|qas\|prod` | 3000 / 3001 / 3002（env 的 `HTTP_PORT`） |
| C `make up-domain-*` | 80（由 traefik-proxy 佔用） |

若看到 `Bind for 0.0.0.0:<port> failed: port is already allocated`，代表該埠被占用。排查：

```bash
lsof -nP -iTCP:<port> -sTCP:LISTEN     # 看什麼程式占用
docker ps --filter publish=<port>       # 或看是哪個容器占用
```

解法：
- 停掉占用者：`docker stop <容器>`（之後 `docker start <容器>` 可原樣復活）。
- **B 模式**：改 `env/.env.*` 的 `HTTP_PORT` 換一個沒被占的埠。
- **A / C**：改用別台主機，或先停掉占 80 的服務。
- **`make dev`**：後端 8000 常被占；停掉占用者，或改 `compose.dev.yaml` 的 `ports`。

## CI/CD promotion（最佳實踐核心）

**build 一次 → 兩個服務各打不可變的 git SHA 標籤 → 同一組 SHA 依序部署到 dev → qas → prod。**
各環境部署的是**同一組映像**（用 SHA 指定），不重 build、不靠 `latest`。

```
push main ─▶ test-backend + build-frontend ─▶ build(backend+frontend :sha) ─▶ deploy-dev ─▶ deploy-qas ─▶ deploy-prod
                                                                                                               ▲
                                                        GitHub Environment「production」設 required reviewers → 上 prod 需人工核准
```

映像位置（兩個）：

```
ghcr.io/<your-account>/fullstack-docker-template-multienv-backend:<git-sha>
ghcr.io/<your-account>/fullstack-docker-template-multienv-frontend:<git-sha>
```

> deploy 步驟目前是 placeholder（印出要部署的映像與環境）。promotion 結構與審核閘門已就緒，
> 把 `echo` 換成你的實際部署指令即可。

## 一次性設定（GitHub）

以下設定存在 GitHub、不在程式碼裡，各做一次即可。

### 1. prod 人工核准（Environments）

> **注意：預設行為是測試通過就一路直接部署到 prod，不會停下來等人核准。**

到 **Settings → Environments** 建立 `dev`、`qas`、`production`，並在 `production` 加 **Required reviewers**。

### 2. 分支保護（require PR + CI 綠燈才能進 main）

到 **Settings → Branches** 對 `main` 加規則：

- **Require a pull request before merging**（禁止直接 push；單人可把 required approvals 設 0）
- **Require status checks to pass** → 勾 `test-backend` 和 `build-frontend`
- **Do not allow bypassing the above settings**（連 owner 也受限）

> 免費方案的**私有** repo 無法用分支保護，需 GitHub Pro 或改為 **public**。

## 開發流程（trunk-based）

只有一個長期分支 `main`。所有改動走「短命功能分支 → PR → 合併 main」，PR 觸發測試、merge 到 main 才 build/部署（純文件變更靠 `paths-ignore` 跳過）。

```bash
git checkout -b fix/xxx
# 改、commit、git push -u origin fix/xxx
gh pr create --fill
gh pr merge --squash    # CI 綠燈後自己就能 merge（approvals = 0）
```

## 部署時機：merge 即部署 vs tag 才發版

目前是**「merge 即部署」**：每次 merge 到 main → 自動 build + 部署到各環境，prod 前用核准閘門把關。
這是精簡又正確的甜蜜點。等到「不想每次 merge 都上 prod」時，再加 **tag-based 發版**（merge 只部署 dev，prod 由 `git tag` 觸發）——屬於需要再加。

## 常用指令

### 本機開發

```bash
# 後端（不透過容器）
cd backend && uv sync --dev
APP_ENV=dev uv run uvicorn app.main:app --reload   # :8000
uv run pytest -q

# 前端（另開終端機）
cd frontend && npm install && npm run dev           # :5173，/api 已代理到 :8000
```

### 查看 / 回溯

```bash
git log --oneline -10                 # 看 commit 與 SHA
git checkout <sha>                    # 看某版 code
docker pull ghcr.io/<your-account>/fullstack-docker-template-multienv-backend:<sha>   # 回溯 = 跑舊 SHA 映像
```

> 追蹤「哪個環境跑哪一版」靠 **SHA 映像標籤** + GitHub Environments 部署歷史，不用開環境分支。
