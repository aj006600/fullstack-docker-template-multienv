# fullstack-docker-template-multienv

前後端分離 + 多環境（dev / qas / prod）的容器範本：React(Vite) 前端 + FastAPI 後端，
用 docker compose 兜起來，CI/CD 遵循「build 一次、依序 promote」的業界最佳實踐。

> 核心原則（12-factor）：**一份程式碼、一組映像、設定隨環境變**。絕不複製程式碼，環境差異只在設定。

> 刻意留白、上 production 前依需要再加的項目（實裝部署、Secrets、TLS、DB、健康檢查、可觀測性、安全掃描、多架構）見 **[docs/roadmap.md](docs/roadmap.md)**。

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
└── .github/workflows/ci-cd.yml # merge→build+dev/qas 自動；打 v* tag→prod
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

**build 一次 → 兩個服務各打不可變的 git SHA 標籤 → 同一組映像 promote。** dev/qas 靠 merge 自動、prod 靠打 tag——
各環境跑的都是**同一組映像**（用 SHA 指定），不重 build、不靠 `latest`。

```
merge main ─▶ test ─▶ build(backend+frontend :sha) ─▶ deploy-dev ─▶ deploy-qas     （自動）
git tag v* ─▶ test ─▶ release(:sha→:v*) ─▶ deploy-prod                             （發版才觸發）
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

**映像自動清理**：`.github/workflows/cleanup.yml` 每週跑一次——兩個服務的 `:sha` 建置各**只留最近 10 個**、**保護 `latest` 與 `v*` 正式版**、刪 untagged。避免映像無限累積。

## 一次性設定（GitHub）

以下設定存在 GitHub、不在程式碼裡，各做一次即可。

### 1. prod 人工核准（Environments）

> **注意：prod 只在打 `v*` tag 時才部署（merge 不會碰 prod）。但即使打了 tag，若沒設 required reviewers，`production` 也不會擋——會直接上。**

到 **Settings → Environments** 建立 `dev`、`qas`、`production`，並在 `production` 加 **Required reviewers**（發版才會停下等人核准）。

### 2. 分支保護（require PR + CI 綠燈才能進 main）

到 **Settings → Branches** 對 `main` 加規則：

- **Require a pull request before merging**（禁止直接 push；單人可把 required approvals 設 0）
- **Require status checks to pass** → 勾 `test-backend` 和 `build-frontend`
- **Do not allow bypassing the above settings**（連 owner 也受限）

> 免費方案的**私有** repo 無法用分支保護，需 GitHub Pro 或改為 **public**。

## 開發流程（trunk-based）

只有一個長期分支 `main`。所有改動走「短命功能分支 → PR → 合併 main」。PR 觸發測試、merge 到 main 才 build + 部署 dev/qas、打 `v*` tag 才上 prod（純文件變更靠 `paths-ignore` 跳過）。

```bash
git checkout -b fix/xxx
# 改、commit、git push -u origin fix/xxx
gh pr create --fill
gh pr merge --squash    # CI 綠燈後自己就能 merge（approvals = 0）
```

## 部署流程：merge 到 dev/qas、打 tag 才上 prod

「合併程式碼」和「正式上 prod」分開——日常 merge 只碰 dev/qas，prod 只在你**刻意打 tag 發版**時才動。

```
merge main ─▶ build(:sha) ─▶ deploy dev ─▶ deploy qas          （自動，不含 prod）
git tag v1.2.0 ─▶ release(:sha→:v1.2.0) ─▶ deploy prod          （發版才觸發）
```

- **merge 到 `main`** → build 兩個映像（`:sha`）+ 自動部署 **dev、qas**
- **打 `v*` tag** → 部署 **prod**：把測試過的 `:sha` **加上版本標籤 `:v1.2.0`（不重 build）**再上

### 怎麼發版（操作教學）

```bash
git checkout main && git pull          # 1. 要發的 commit 已在 main、dev/qas 驗過（:sha 已 build）
git tag v1.2.0                         # 2. 打版本 tag
git push origin v1.2.0                 # 3. 推 tag → 觸發 prod 發版
```

> - prod 前的 `production` environment 若設了 required reviewers，發版會**停下等人核准**（見上方〈一次性設定〉）。
> - tag 要打在**已在 main、已 build** 的 commit（否則找不到對應的 `:sha` 映像）。

## 常用指令

### 開發（本機，不透過容器）

```bash
# 後端
cd backend && uv sync --dev
APP_ENV=dev uv run uvicorn app.main:app --reload   # :8000
uv run pytest -q

# 前端（另開終端機）
cd frontend && npm install && npm run dev           # :5173，/api 已代理到 :8000
```

### 查看「現在跑的是哪一版」

映像用 **git SHA** 當標籤，所以「哪個環境跑哪一版」= 「跑哪個 SHA」。

```bash
git log --oneline -10                 # 看最近的 commit 與其 SHA
git show <sha>                        # 看某個 SHA 改了什麼
git checkout <sha>                    # 切過去看該版 code（看完 git switch - 回來）

docker ps --format '{{.Image}}'       # 看正在跑的容器用哪個映像
```

> GitHub 網頁 → repo → **Environments**：可看每個環境「部署了哪個 SHA、何時、由誰」的完整歷史。不用開環境分支。

### 回溯（rollback）到舊版

映像不可變且都留在 registry，所以**回溯 = 重新部署上一組好的 SHA，不用重 build**（超快）。

```bash
git log --oneline                     # 1. 找出要回到的舊 SHA

# 2. 直接拉那組舊映像（真部署時把部署指令指向這個 tag 即可）
docker pull ghcr.io/<your-account>/fullstack-docker-template-multienv-backend:<old-sha>
docker pull ghcr.io/<your-account>/fullstack-docker-template-multienv-frontend:<old-sha>
```

### 版本標記（可選，讓紀錄更清楚）

```bash
git tag v1.0.0 && git push origin v1.0.0   # 發版時打 tag
git checkout v1.0.0                          # 之後要看該版 code
```

## 備註：雙邊託管 GitLab + GitHub（尚未實作，之後需要再加）

CI 設定檔是**平台專屬**的，兩份可並存、各讀各的；`backend/`、`frontend/`、`compose.yaml` 完全共用：

| 平台 | CI 設定檔 |
|------|----------|
| GitHub Actions | `.github/workflows/*.yml`（現有） |
| GitLab CI | `.gitlab-ci.yml`（放根目錄，之後再加） |

真的要做時，先決定三件事（不然容易踩雷）：

1. **選一邊當真相來源**，用倉庫鏡像（mirror）自動同步另一邊——避免兩邊各自 push 造成分岔。
2. **避免兩邊都跑 CI／都部署**（除非故意，例如各部署到不同雲）。
3. **secrets 與 registry 各平台各設**（GHCR vs GitLab Container Registry）。
