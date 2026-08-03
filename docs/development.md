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

# 2. 直接拉那組舊映像（真部署時把部署指令指向這個 tag 即可）
docker pull ghcr.io/<your-account>/fullstack-docker-template-multienv-backend:<old-sha>
docker pull ghcr.io/<your-account>/fullstack-docker-template-multienv-frontend:<old-sha>
```

## 版本標記（可選，讓紀錄更清楚）

```bash
git tag v1.0.0 && git push origin v1.0.0   # 發版時打 tag（也會觸發 prod 發版，見 docs/cicd.md）
git checkout v1.0.0                          # 之後要看該版 code
```
