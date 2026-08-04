# 本機開發

[← 回 README](../README.md)

## 前後端怎麼溝通

瀏覽器只打 `frontend`，`/api/*` 由 frontend 的 nginx 反向代理到 `backend`（同源，後端免處理 CORS）。
`/api/message` 會回傳目前環境，所以切換 `APP_ENV` 時前端顯示的環境也會跟著變。

```
瀏覽器 → frontend(nginx:80) ──/api/──▶ backend(uvicorn:8000)
                          └─ 其他路徑 = SPA 靜態檔
```

## 快速開始（本機開發、單環境）

`make dev` 用於**本機開發**：起前後端、掛載後端原始碼並開啟熱重載，直接連 `localhost`，不經任何 proxy。

```bash
make dev          # APP_ENV=dev：前後端起來、後端熱重載（前景執行，佔住終端機）
# 前端 → http://localhost:3000（會顯示 backend 回傳的環境）
# 後端 → http://localhost:8000/health

make dev-down     # 停止並清理：移除本機開發的容器與網路
```

`make dev` 用 `compose.dev.yaml`：前端開 3000、後端開 8000，並掛載後端原始碼 + 熱重載。

> 收工用 **`make dev-down`** 停止並清理。`make dev` 是前景執行，也可直接按 **`Ctrl+C`** 停止——但 `Ctrl+C` 只是停止容器（仍殘留為 exited 狀態），`make dev-down` 會進一步**移除**殘留的容器與網路。

## `make dev` 與部署模式（`make up-*`）的差別

兩者的 dev 目的完全不同——只是寫 code，用 `make dev` 就好；要把 dev/qas/prod 環境實際跑起來（給團隊連、模擬部署）才用 `make up-*`。

| | `make dev` | `make up-separate-hosts` / `up-port-*` / `up-domain-*` |
|---|-----------|--------------------------------------------------------|
| 目的 | **本機開發**（寫 code） | **部署環境**（跑起來給人用 / 模擬部署） |
| 環境數 | 只有 **dev 一個** | **dev / qas / prod** 可同時並存 |
| 跑什麼 | 掛載原始碼 + **熱重載** | **建好的映像**（改 code 不反映，需重建） |
| 執行方式 | 前景（`Ctrl+C` 停、`make dev-down` 清） | 背景 `-d`（**一定要 `make down-*`** 才會停） |
| 怎麼連 | `localhost:3000/8000` | 依模式（80 埠 / `IP:port` / domain） |

## dev / qas / prod 怎麼區分——靠 env 檔，不是不同 image

**三個環境跑的是同一個映像**（同一份 source `build:` 出來的），差別只在**載入哪份 `env/.env.<env>` 設定**。這正是 12-factor 核心：一份 code、一個 image、設定隨環境變。

接線（以 qas 為例）：

```bash
make up-domain-qas
#  = COMPOSE_PROJECT_NAME=fullstack-qas docker compose … --env-file env/.env.qas up -d --build
```

1. `--env-file env/.env.qas` 讀進 `env/.env.qas` → 其中 `APP_ENV=qas`
2. `compose.yaml` 的 `env_file: env/.env.${APP_ENV:-dev}` 用這個 `APP_ENV` 解析成 `env/.env.qas`
3. 容器載入 `env/.env.qas`（`APP_ENV`、`LOG_LEVEL`、`DOMAIN`、`HTTP_PORT`…）

> 「是哪個環境」= **哪份 env 檔被載入**，不是哪個 image。CI/CD 部署時也一樣：build 一次打 `:sha`，dev/qas/prod promote **同一顆** `:sha`——這才保證「dev 測過的就是上 prod 的那顆」。

## 讓環境「變成最新」——分清楚該用哪個指令

同樣叫 dev/qas/prod，但**「本機自己跑」和「CI/CD 部署」是兩個不相干的世界**，更新方式完全不同。常見誤解是「merge 一下、本機 `make up-*` 的環境就變新」——不會。

### 本機（你這台機器）→ 靠**重跑 `make up-*`**

`make up-*` 用你**當下的本機 code** 現場 `--build`。**merge PR 不會更新它們**；改了 code 想讓本機環境變新，就自己重跑：

```bash
make up-domain-dev        # 用目前本機 code 建 + 跑 dev
# …改了 code…
make up-domain-dev        # 再跑一次即可，不用先 down（見下）
make down-domain-dev      # 收工要停時
```

> **改完 code 直接重跑 `make up-*` 就好，不用先 `make down-*`**——`up -d --build` 會重建映像、並自動把舊容器換成新的（recreate，僅幾秒短暫中斷）。只有改了 **compose 結構**（網路 / volume / service）或想全新乾淨重來時，才先 `make down-*` 再 up。

> 這些容器跟 GitHub / CI **無關**，不會因為你 merge 就自動變新。

> **本機這顆映像 ≠ 最近 merge 那顆 `:sha`。** `make up-*` 建的是**你本機當前工作區的 code**（連未 commit 的改動都算），不會去 registry 拉 CI 建的映像。所以它跟「最近 merge 那顆」的關係全看你本機狀態：`git pull` 且無本機改動 → 內容相同（但仍是本機另建的一顆）；有未 commit 改動 → 比它新；本機落後 main → 比它舊。要真的跑「最近 merge 的那顆」，用拉取式部署指令 **`make deploy`**（拉 CI 建好的 `:sha`、不重 build，見下方）。

### 遠端（CI/CD 部署）→ 靠 **merge / 打 tag**

推到 GitHub 後由 CI 自動建映像並部署（詳見 [cicd.md](cicd.md)）：

```bash
gh pr merge --squash                        # 部署 dev + qas（merge 到 main 自動觸發，不含 prod）
git tag v1.2.0 && git push origin v1.2.0    # 部署 prod（只有打 v* tag 才觸發，需人工核准）
```

### 一眼看哪個指令更新哪裡

| 指令 | 更新哪裡 | 更新哪個環境 |
|------|---------|-------------|
| `make up-*`（**重跑**） | 你**本機** | 你指定的那一個 |
| `gh pr merge`（merge main） | **遠端 CI 部署** | **dev + qas**（不含 prod） |
| `git tag v* && git push` | **遠端 CI 部署** | **prod**（需核准） |

> 目前 CI 的 deploy 步驟只會**印出「該在主機上執行的 `make deploy` 指令」**，尚未真的連線主機——接上 SSH / docker context 後（見 [roadmap.md](roadmap.md)），上表「遠端」那兩列才會真的部署到伺服器。

## 本機 `make up-*` 是「預覽」，真部署用 `make deploy`

**在你機器上跑 `make up-*` ≠ 部署。** 它 `--build` 用你當前 code 現場建，用途是**預覽/測試「該環境的 `env/.env.*` 設定 + 曝露拓撲」**。三種拓撲的預覽能力不同：

- **B（port）/ C（domain）**：可在本機**同時起三個環境**，驗證各環境設定與導流（埠配置、Traefik 路由）。
- **A（separate-hosts）**：多機拓撲**無法單機模擬**；本機跑 `up-separate-hosts` 只能**一次預覽一個環境**（都綁 80）。

用詞澄清：`deploy/compose.*.yaml` 是**曝露拓撲**（部署時用哪種對外方式）；**在本機跑它們是預覽，不等於部署**。

真部署 = 在**目標主機**上拉 **CI 測過的那顆 `:sha`** 跑（不重 build），用 `make deploy`：

```bash
make deploy MODE=same-host-by-domain ENV=dev \
    IMAGE=ghcr.io/<your-account>/fullstack-docker-template-multienv TAG=<git-sha>
# MODE = separate-hosts | same-host-by-port | same-host-by-domain
# TAG  = <git-sha>（dev/qas）或 vX.Y.Z（prod）
```

| 指令 | 職責 | 映像來源 |
|------|------|---------|
| `make dev` | 開發（熱重載） | 本機 code（掛載） |
| `make up-*` | **本機預覽** env 設定 / 拓撲 | 本機 code 現場 build |
| `make deploy` | **部署執行**（目標主機上跑；CI 與人工共用同一條） | **拉 CI 測過的 `:sha`**，不重 build |

> 環境不「知道」自己該用哪顆映像——**版本（`TAG`）是傳入的**，由 promotion 流程決定：merge → CI 以該 commit 的 sha 部署 dev+qas；打 `v*` tag → prod（見 [cicd.md](cicd.md)）。人工部署 / 回溯就自己指定 `TAG`。「哪個環境跑哪顆」的紀錄 = GitHub Environments 部署歷史 + `docker ps` 的 image tag。

## 查看現在起了哪些東西（容器 / 專案）

```bash
docker compose ls        # 有哪些 compose 專案在跑（一眼看出起了哪些環境/模式）
make ps                  # 模板內建：正在跑的容器（名稱 / 狀態 / 埠）
docker ps                # 同上，未美化
```

看更完整（含停掉殘留、網路）：

```bash
docker ps -a             # 連「停掉但殘留」的容器也列（exited 狀態）
docker compose ls -a     # 連停掉的 compose 專案也列
docker network ls        # 有哪些網路（proxy、各專案網路）
```

> 每個部署環境是獨立的 compose 專案（`fullstack-dev` / `fullstack-qas` / `fullstack-prod`）；`make dev` 則以資料夾名當專案名。用 `docker compose ls` 對照專案名，就知道哪個模式/環境正開著。

## 改程式碼怎麼測（後端熱重載）

`make dev` 已掛載後端原始碼並開啟 `uvicorn --reload`，所以測試一個改動**不需進容器、也不需重建**：

1. 在**本機**編輯 `backend/app/*.py`（用你的編輯器）。
2. 容器內的 uvicorn 偵測到變更、**自動重載**。
3. 直接打 API 驗證：

```bash
curl http://localhost:8000/api/message      # 或開瀏覽器 http://localhost:3000
```

注意：

- **自動重載只適用「後端 + `make dev`」**（只有這個組合掛載了原始碼 + `--reload`）。
- **前端在 `make dev` 不會熱重載**（它是建好的 nginx 映像）；前端要即時開發請用下方「不透過容器」的 `npm run dev`（Vite，`:5173`）。
- **部署模式（`make up-*`）不掛載原始碼**，跑的是建好的映像——改本機程式碼不會反映，需重建。

## 進到容器裡（`docker exec`）

承上，改程式碼靠熱重載即可、**不需進容器**。進容器是為了「在容器內執行指令 / 檢查 / 除錯」——例如查看環境變數、執行一次性腳本、確認相依安裝，或在容器的環境裡跑測試（`docker exec -it <後端容器名> uv run pytest`）。

用 compose 的**服務名**進入（免查容器名，在專案根目錄執行）：

```bash
docker compose -f compose.yaml -f compose.dev.yaml exec backend bash   # 後端（Debian 基底，有 bash）
docker compose -f compose.yaml -f compose.dev.yaml exec frontend sh    # 前端（nginx:alpine，用 sh）
```

或用容器名（先以 `docker ps` / `make ps` 查名稱）：

```bash
docker exec -it <容器名> bash    # 後端；前端用 sh
```

容器內：後端工作目錄為 `/app`、程式在 `/app/app`、venv 在 `/app/.venv`（`uvicorn`、`pytest` 等已在 PATH）。**後端以非 root 的 `appuser` 執行**（前端 nginx 則以預設 root 執行）。後端需要安裝系統套件時，改用 root 進入：

```bash
docker compose -f compose.yaml -f compose.dev.yaml exec -u root backend bash
```

> 上述指令針對 `make dev`。若跑的是部署模式（`make up-*`），各環境 project 名不同（如 `fullstack-dev`），用 `docker ps` 查容器名後以 `docker exec -it <容器名> …` 進入最直接。

## 不透過容器（更快的內層迴圈）

```bash
# 後端
cd backend && uv sync --dev
APP_ENV=dev uv run uvicorn app.main:app --reload   # :8000
uv run pytest -q

# 前端（另開終端機）
cd frontend && npm install && npm run dev           # :5173，/api 已由 Vite 代理到 :8000
```

## 查看「現在跑的是哪一版」

映像用 **git SHA** 當標籤，所以「哪個環境跑哪一版」= 「跑哪個 SHA」。

```bash
git log --oneline -10                 # 看最近的 commit 與其 SHA
git show <sha>                        # 看某個 SHA 改了什麼
git checkout <sha>                    # 切過去看該版 code（看完 git switch - 回來）

docker ps --format '{{.Image}}'       # 看正在跑的容器用哪個映像
```

> GitHub 網頁 → repo → **Environments**：可看每個環境「部署了哪個 SHA、何時、由誰」的完整歷史。不用開環境分支。

## 回溯（rollback）到舊版

映像不可變且都留在 registry，所以**回溯 = 重新部署上一組好的 SHA，不需重新 build**。

```bash
git log --oneline                     # 1. 找出要回到的舊 SHA

# 2. 在目標主機上把該環境部署回舊 SHA（一行，不重 build）
make deploy MODE=<擇一> ENV=prod \
    IMAGE=ghcr.io/<your-account>/fullstack-docker-template-multienv TAG=<old-sha>
```

## 版本標記（可選，讓紀錄更清楚）

```bash
git tag v1.0.0 && git push origin v1.0.0   # 發版時打 tag（也會觸發 prod 發版，見 docs/cicd.md）
git checkout v1.0.0                          # 之後要看該版 code
```
