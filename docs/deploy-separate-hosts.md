# 部署模式 A：separate-hosts（每環境各自一台主機）

[← 回 README](../README.md) ｜ 其他模式：[B. same-host-by-port](deploy-same-host-by-port.md) ｜ [C. same-host-by-domain](deploy-same-host-by-domain.md)

每個環境（dev / qas / prod）**各自跑在一台主機**上，前端佔標準 **80** 埠。這是**隔離最完整、最貼近真實世界**的部署方式（同一個映像、不同機器，以 host/domain 區分）。

- **適合**：有多台機器（或雲端多台 VM）、在意 prod 隔離
- **代價**：要多台機器
- **對外曝露**：`deploy/compose.separate-hosts.yaml`（前端 `80:80`，後端不對外，由前端 nginx 內部代理 `/api`）

## 步驟

### 1. 從範本建立你的專案

GitHub 上按 **「Use this template」**（或 clone 本 repo），得到你自己的 repo，改成你的 app。

### 2. 設定各環境

`env/.env.dev`、`env/.env.qas`、`env/.env.prod` 各放該環境的**非機密**設定（`APP_ENV`、`LOG_LEVEL`…）。真正的密鑰走 CI secrets / 部署時注入，別提交進 repo。

### 3. 在「每台環境主機」上各跑一個環境

在 **dev 那台主機**：

```bash
make up-separate-hosts ENV=dev
```

在 **qas 主機**：`make up-separate-hosts ENV=qas`；**prod 主機**：`make up-separate-hosts ENV=prod`。

> 每台主機只跑它自己那個環境，用標準 80 埠，不會與其他環境衝突。

### 4. 存取

瀏覽器打 **該主機的位址**：`http://<dev 主機 IP 或域名>`。頁面會顯示 `Environment: dev`（前端打 `/api/message` 從後端拿到的）。

### 5. 停止

```bash
make down-separate-hosts ENV=dev
```

## 改埠 / 改設定

- **對外埠**：預設前端 80。要改成別的（例如 8080），編輯 `deploy/compose.separate-hosts.yaml` 的 `ports: "80:80"` → `"8080:80"`。
- **環境設定**：改對應的 `env/.env.<env>`。

## 上正式對外（prod）

這個模式已是隔離的好起點，但對外還需要（見 [docs/roadmap.md](roadmap.md)）：

- 真實域名 + DNS 指到 prod 主機
- **TLS/HTTPS**（在 prod 主機前放 Caddy/Traefik/nginx + 憑證，或用雲端 LB）
- 防火牆 / 安全強化

## 疑難排解

**`Bind for 0.0.0.0:80 failed: port is already allocated`** — 80 埠被占用：

```bash
lsof -nP -iTCP:80 -sTCP:LISTEN     # 看什麼程式占用
docker ps --filter publish=80       # 或看是哪個容器
```

解法：停掉占用者（`docker stop <容器>`），或改 override 的對外埠（見上）。
