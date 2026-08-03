# fullstack-docker-template-multienv

前後端分離 + 多環境（dev / qas / prod）的容器範本：React(Vite) 前端 + FastAPI 後端，
用 docker compose 兜起來，CI/CD 遵循「build 一次、依序 promote」的業界最佳實踐。

> 核心原則（12-factor）：**一份程式碼、一組映像、設定隨環境變**。絕不複製程式碼，環境差異只在設定。

## 文檔導覽

| 想做的事 | 看這份 |
|----------|--------|
| **本機開發**（起服務、常用指令、查看/回溯版本） | [docs/development.md](docs/development.md) |
| **部署 A**：每環境各自一台主機（最佳實踐） | [docs/deploy-separate-hosts.md](docs/deploy-separate-hosts.md) |
| **部署 B**：同機、不同 port（最簡妥協） | [docs/deploy-same-host-by-port.md](docs/deploy-same-host-by-port.md) |
| **部署 C**：同機、Traefik 依 domain | [docs/deploy-same-host-by-domain.md](docs/deploy-same-host-by-domain.md) |
| **CI/CD、發版、GitHub 設定**（tag 發版、分支保護、映像清理） | [docs/cicd.md](docs/cicd.md) |
| **上 production 前還要加什麼**（Secrets/TLS/DB/健康檢查…） | [docs/roadmap.md](docs/roadmap.md) |

## 快速開始（2 分鐘，本機）

```bash
make dev       # 前後端起來，後端熱重載（前景執行）
# 前端 → http://localhost:3000（會顯示 backend 回傳的環境）
# 後端 → http://localhost:8000/health
make dev-down  # 停止並清理（或直接 Ctrl+C 停止；詳見 docs/development.md）
```

前後端怎麼溝通：瀏覽器只打 frontend，`/api/*` 由 frontend 的 nginx 反向代理到 backend（同源、免 CORS）。

```
瀏覽器 → frontend(nginx:80) ──/api/──▶ backend(uvicorn:8000)
                          └─ 其他路徑 = SPA 靜態檔
```

## 選你的部署模式（三選一）

同一個 app，三種「怎麼把環境跑起來/曝露」的做法。**選一種用**，不是同時跑。

| 模式 | 拓撲 | 隔離/最佳實踐 | 何時選 | 詳細 |
|------|------|--------------|--------|------|
| **A. separate-hosts** | 每環境**各自一台主機**、標準 80 埠 | 最佳實踐、完整隔離 | 有多台機器 / 在意 prod 隔離 | [→](docs/deploy-separate-hosts.md) |
| **B. same-host-by-port** | 三環境**同機、不同 port** | 最簡妥協、無隔離 | 一台機器、想最快、能接受 `IP:port` | [→](docs/deploy-same-host-by-port.md) |
| **C. same-host-by-domain** | 三環境**同機、Traefik 依 domain** | 同機但用 domain（貼近真實） | 一台機器、要 domain、團隊存取 | [→](docs/deploy-same-host-by-domain.md) |

## 結構

```
.
├── backend/                    # FastAPI + uv（單階段、非 root）
│   ├── app/main.py             # /health、/api/message（回傳目前環境）
│   ├── app/config.py           # pydantic-settings：從環境變數讀設定
│   ├── tests/  ·  pyproject.toml · uv.lock  ·  Dockerfile
├── frontend/                   # React + Vite（node→nginx 多階段）
│   ├── src/App.jsx  ·  nginx.conf（供靜態檔 + 反向代理 /api）
│   ├── package.json · package-lock.json  ·  Dockerfile
├── compose.yaml                # base：只定義服務與內部接線（不決定對外曝露）
├── compose.dev.yaml            # 本機開發覆寫：開 localhost 埠 + 後端熱重載
├── deploy/                     # 三種部署模式（同一個 app、只差怎麼曝露）
│   ├── compose.separate-hosts.yaml
│   ├── compose.same-host-by-port.yaml
│   └── compose.same-host-by-domain.yaml
├── env/{.env.dev,.env.qas,.env.prod}   # 各環境設定 + HTTP_PORT(B) + DOMAIN(C)
├── Makefile                    # make dev / up-separate-hosts / up-port-* / up-domain-* / down-* / ps
├── .github/workflows/
│   ├── ci-cd.yml               # merge→build+dev/qas 自動；打 v* tag→prod
│   └── cleanup.yml             # 每週清理舊映像
└── docs/                       # 詳細文檔（見上方導覽）
```

> C 模式用的共用 Traefik 不在本 repo，在獨立的 **[`traefik-proxy`](../traefik-proxy)** repo（整台機器跑一次）。
