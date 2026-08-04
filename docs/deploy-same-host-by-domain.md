# Topology C: same-host-by-domain

[← README](../README.md) ｜ 其他 topology：[A. separate-hosts](deploy-separate-hosts.md) ｜ [B. same-host-by-port](deploy-same-host-by-port.md)

三個環境**跑在同一台機器**，但用 **domain 區分**（同一個 **80** 埠、靠共用 **Traefik** 依 Host 導流）。同機方案裡最貼近真實 prod 的做法。

- **適合**：只有一台機器、要用 domain、團隊要能連
- **代價**：三環境同機，**沒有實體隔離**；要跑一份共用 Traefik
- **對外曝露**：`deploy/compose.same-host-by-domain.yaml`（前端接上 `proxy` network + Traefik label，不自己開 host 埠）

```
                        ┌─ dev.app.localhost  → dev  這組 container
瀏覽器 → Traefik(:80) ────┼─ qas.app.localhost  → qas  這組 container
                        └─ app.localhost      → prod 這組 container
```

## Prerequisite: start the shared Traefik (once per machine)

Traefik 不在本 repo，在獨立的 **[`traefik-proxy`](../../traefik-proxy)** repo（整台機器共用一份）：

```bash
cd ../traefik-proxy && make up
```

這會建立 `proxy` network + 啟動 Traefik（佔 80 埠、dashboard 在 `:8080`）。**所有 app、所有環境共用這一份**，不用每個專案各跑。

## Steps

### 1. Create your repo from this template

GitHub「Use this template」或 clone，改成你的 app。

### 2. Start all three environments (side by side)

```bash
make up-domain-dev
make up-domain-qas
make up-domain-prod
make ps                # 看狀態
```

每個環境是**獨立的 compose project**，靠 env 檔的 `DOMAIN` 註冊到 Traefik。停某個：`make down-domain-dev`。

### 3. Access — how the domain resolves (important)

網址由 env 檔的 `DOMAIN` 決定。依「誰要連」有三種寫法：

| 誰要連 | `DOMAIN` 寫法 | 要設定什麼 |
|--------|--------------|-----------|
| **只有你自己（本機）** | `dev.app.localhost` | 無——`*.localhost` 瀏覽器自動解析到 127.0.0.1 |
| **團隊（同網路、免 DNS）** | `dev.app.<你的IP>.nip.io` | 無——nip.io 自動解析到該 IP（需連得到外網） |
| **正式對外** | 你的真實域名 | 正規 DNS + TLS + 機器對外曝露 |

#### 3a. Yourself only (zero setup)

`env/.env.*` 預設就是 `.localhost`，直接開：

- dev → `http://dev.app.localhost`
- qas → `http://qas.app.localhost`
- prod → `http://app.localhost`

> ⚠️ `*.localhost` 指的是「**執行瀏覽器那台機器自己**」（127.0.0.1）。**隊友用這個網址只會連到自己的電腦，連不到你。**

#### 3b. Team access without DNS — nip.io

`nip.io` 讓 `任何字.<你的IP>.nip.io` 自動解析到 `<你的IP>`，零 DNS 設定。

先查你機器的對外 IP（活躍介面**不一定**是 `en0`，別寫死）：

```bash
ipconfig getifaddr "$(route get default | awk '/interface:/{print $2}')"
```

假設是 `10.0.0.5`，**執行時傳入 `DOMAIN`**（**別改 `env/.env.*`**——那是被 git 追蹤的檔案，IP 一旦 commit 就會進公開 repo，而且 IP 會變）：

```bash
DOMAIN=dev.app.10.0.0.5.nip.io make up-domain-dev   # qas/prod 同理
```

隊友（在同一網路、能連外網）就開 `http://dev.app.10.0.0.5.nip.io`。

#### 3c. Public-facing

用你**自己的真實域名** + 正規 DNS 指到機器 + **TLS**（見 [roadmap.md](roadmap.md)）。nip.io 只是過渡方便，不是 production 做法。

### 4. Stop

```bash
make down-domain-dev   # 停 dev（qas/prod 不受影響）
```

## Changing the domain

- 本機預設：改 `env/.env.<env>` 的 `DOMAIN`（例如換前綴）。
- 機器/團隊/正式：**執行時傳入 `DOMAIN`**（如上 3b），不動追蹤檔。

## Troubleshooting

### 404

代表 nip.io/localhost **有解析成功**（請求有到 Traefik），只是 Traefik 沒有對應的路由。逐項檢查：

```bash
# 1. Traefik 有起來嗎？
docker ps --filter name=traefik

# 2. 你的環境有起來、且接上 proxy network 嗎？
docker ps --format '{{.Names}}\t{{.Networks}}' | grep fullstack

# 3. Traefik 現在有哪些 Host 路由？（比對你打的網址）
curl -s http://localhost:8080/api/http/routers | grep -oE '"rule":"Host[^"]*"' | sort -u

# 4. 你打的網址，跟 env 的 DOMAIN 一致嗎？
grep DOMAIN env/.env.dev
```

最常見原因：**DOMAIN 沒改**（還是 `.localhost`）卻用 nip.io 網址打 → 路由是 `Host(dev.app.localhost)`、不 match nip.io → 404。解法：用執行時傳入 `DOMAIN`（3b）重跑。

### Port 80 already in use

Traefik 綁 80。若 `traefik-proxy` 的 `make up` 報 `port is already allocated`：

```bash
lsof -nP -iTCP:80 -sTCP:LISTEN     # 看什麼占用 80
```

停掉占用者（常見是 topology A 也綁了 80、或別的 web server）。

> 三環境同機沒有故障/安全隔離——prod 若重要，改用 [A. separate-hosts](deploy-separate-hosts.md)。
