# 本機開發

[← 回 README](../README.md)

## 前後端怎麼溝通

瀏覽器只打 `frontend`，`/api/*` 由 frontend 的 nginx 反向代理到 `backend`（同源，後端免處理 CORS）。
`/api/message` 會回傳目前環境，所以切換 `APP_ENV` 時前端顯示的環境也會跟著變。

```
瀏覽器 → frontend(nginx:80) ──/api/──▶ backend(uvicorn:8000)
                          └─ 其他路徑 = SPA 靜態檔
```

## 快速開始（容器、單環境）

```bash
make dev     # APP_ENV=dev：前後端起來，後端熱重載（不經 Traefik）
# 前端 → http://localhost:3000（會顯示 backend 回傳的環境）
# 後端 → http://localhost:8000/health
make down    # 停掉
```

`make dev` 用 `compose.dev.yaml`：前端開 3000、後端開 8000，並掛載後端原始碼 + 熱重載。

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

映像不可變且都留在 registry，所以**回溯 = 重新部署上一組好的 SHA，不用重 build**（超快）。

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
