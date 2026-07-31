# fullstack-docker-template-multienv

前後端分離 + 多環境（dev / qas / prd）的容器範本：React(Vite) 前端 + FastAPI 後端，
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
├── compose.proxy.yaml          # 部署覆寫：走 Traefik 依 domain 導流
├── proxy/compose.yaml          # 共用 Traefik（整台機器跑一次）
├── env/{.env.dev,.env.qas,.env.prod}   # 各環境設定 + DOMAIN
├── Makefile                    # make dev / proxy-up / up-dev|qas|prod
└── .github/workflows/ci-cd.yml # 測前後端 → build 兩映像各一次 → promote dev→qas→prod
```

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

## 多環境同機部署（dev + qas + prod 並存，走 Traefik）

適用於「同一台機器同時跑多個環境、團隊用 domain 存取」。**用 domain 區分環境，不用 port**：
只有 Traefik 對外開 80，各環境容器不開 host 埠，所以不會撞埠。

```
                        ┌─ dev.myapp.internal  → dev  這組容器
團隊 → Traefik(:80) ─────┼─ qas.myapp.internal  → qas  這組容器
                        └─ myapp.internal      → prod 這組容器
```

每個環境是**獨立的 compose project**（獨立網路/容器），dev 的前端只連 dev 的後端，互不干擾。

```bash
make proxy-up    # 一次性：建立 proxy 網路 + 啟動共用 Traefik
make up-dev      # 起 dev（Host = dev.myapp.internal）
make up-qas      # 起 qas（可與 dev 同時存在）
make up-prod     # 起 prod
make ps          # 看 Traefik + 各環境狀態
make down-dev    # 停 dev（qas/prod 不受影響）
```

### 你需要準備的（repo 外）

- **內網 DNS**：把 `dev.myapp.internal`、`qas.myapp.internal`、`myapp.internal`（或 `*.myapp.internal` 萬用）指到這台機器的內網 IP，團隊才連得到。把 `env/.env.*` 裡的 `DOMAIN` 改成你的真實內網網域。
- **Traefik dashboard**：`http://<host>:8080` 可看導流狀況（正式環境請關閉或加保護）。

### 幾個此架構的重點

- **同 port、不同 domain**：跟真實 prod 一致；容器內部埠（前端 80、後端 8000）每個環境都一樣。
- **注意**：三環境同機沒有真正的故障/安全隔離——prod 若很重要，建議獨立一台機器。需要時可再加各環境的資源上限（`cpus` / `mem_limit`）避免互相拖垮。
- **TLS**：目前走 HTTP(80)；要 HTTPS 再於 Traefik 加內網憑證（內部 CA / mkcert），屬於需要再加。

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
