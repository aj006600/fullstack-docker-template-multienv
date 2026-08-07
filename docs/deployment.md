# Deployment

[← README](../README.md)

部署 = 在某台主機上讓某個 environment 跑起來。兩個旋鈕：

| 旋鈕 | 決定什麼 | 值 |
|------|---------|----|
| `EXPOSE` | 怎麼對外曝露 | `ports` ｜ `proxy` |
| `ENV` | **Environment**——載入哪份設定 | `dev` ｜ `qas` ｜ `prod` |

部署在**目標主機**上執行，拉 CI 測過的不可變映像，不重 build：

```bash
make deploy EXPOSE=<ports|proxy> ENV=<dev|qas|prod> IMAGE=… TAG=…   # 拉指定版本並啟動
make down   EXPOSE=<ports|proxy> ENV=<dev|qas|prod>                 # 停止
```

`TAG` 是 `:sha`（dev/qas）或 `vX.Y.Z`（prod）；rollback 就換回舊的 sha——無狀態時才這麼單純：
一旦有了資料庫 schema，程式碼回得去，migration 過的資料回不去。

> **主機必須是 amd64 Linux。** CI 只建 amd64——在 Apple Silicon 的開發機上 `make deploy` 會失敗
> （`no matching manifest for linux/arm64`）。開發機請用 `make dev`；例外見本文最後一節。

## Choosing ports or proxy

只有兩種真正不同的曝露方式：

| `EXPOSE` | 做什麼 | 何時選 | 網址長相 |
|----------|--------|--------|---------|
| **`ports`** | frontend 綁到主機的 `HTTP_PORT` | 預設。一台機器跑一到多個 environment，不需要 domain | `http://<host>:<port>` |
| **`proxy`** | 不綁主機埠，接上整台機器共用的 reverse proxy，由它依 `DOMAIN` 導流 | 要 domain、要團隊用網址存取、日後要 TLS | `http://<domain>` |

**「一個 environment 獨佔一台主機」不是第三種選項**——那是 `ports` 把該主機的 `HTTP_PORT` 設成 80，
網址就不必帶埠。

> `ports` 的三個 environment 同機並存時沒有故障與安全隔離。prod 若重要，讓它獨佔一台主機。

## Common steps

### 1. Create your repo from this template

GitHub 上按「Use this template」（或 clone 本 repo），改成你的 app。

### 2. Configure each environment

每個 environment 的設定分兩層：

| 檔案 | 進版控 | 放什麼 |
|------|-------|-------|
| `env/.env.<env>` | 是 | **非機密**：`APP_ENV`、`LOG_LEVEL`，與曝露用的參數（`ports` 用 `HTTP_PORT`、`proxy` 用 `DOMAIN`） |
| `env/.env.<env>.local` | **否**（`.gitignore` 擋掉） | **機密**：DB 連線字串、API key。每台主機自己建 |

`.local` 疊在前者之上，**同名變數以 `.local` 為準**；沒有 `.local` 的機器照常啟動。

```bash
# 在目標主機上，例如 prod
cat > env/.env.prod.local <<'EOF'
DATABASE_URL=postgresql://...
EOF
```

> `.local` 只注入 **container 內的環境變數**，不參與 compose 檔自身的插值——`HTTP_PORT` 與 `DOMAIN`
> 走 Makefile 的 `--env-file`，寫進 `.local` 不會生效。這兩個本來也不是機密。

### 3. Push and let CI build

`make deploy` 拉的是 registry 裡的映像，所以要先 merge 到 `main`、讓 CI 建出該 commit 的 `:sha`。
之後在主機上帶那個 sha 部署。

### 4. Log in to the registry

GHCR 的 package 預設跟著 repo 的可見性走，而這個 template 假設 repo 是 private，所以 package 也是——
目標主機要先登入**一次**（這是主機的 bootstrap，不是每次部署的參數）。
（repo 若是 public，package 也會是 public，這步可以跳過。）

```bash
echo <PAT> | docker login ghcr.io -u <你的帳號> --password-stdin
```

PAT 需要 `read:packages` 權限。沒登入的話 `make deploy` 會停在 `pull` 這步，錯誤訊息是
`denied` 或 `unauthorized`。

> 之後 CD 真的連上主機時同樣要處理這件事。

---

## `ports`

frontend 綁到主機的 `HTTP_PORT`。三個 environment 同機並存時各用不同的埠。

| Environment | `HTTP_PORT`（在 `env/.env.*`） | 網址 |
|------|------------------------------|------|
| dev  | 3000 | `http://<host>:3000` |
| qas  | 3001 | `http://<host>:3001` |
| prod | 3002 | `http://<host>:3002` |

同機並存時三個埠**必須不同**。

```bash
# EXPOSE 預設就是 ports
make deploy ENV=dev  IMAGE=ghcr.io/<your-account>/<your-repo> TAG=<git-sha>
make deploy ENV=qas  IMAGE=… TAG=…
make deploy ENV=prod IMAGE=… TAG=vX.Y.Z
make ps              # 看狀態
```

每個 environment 是**獨立的 compose project**（`fullstack-dev` / `fullstack-qas` / `fullstack-prod`，
各自獨立的 network 與 container），dev 的前端只連 dev 的後端，互不干擾。

**連上**：

- 你自己：`http://localhost:3000` / `:3001` / `:3002`
- 團隊（同網路）：`http://<你的機器IP>:3000` 等——不需要 domain，直接 IP:port
  ```bash
  ipconfig getifaddr "$(route get default | awk '/interface:/{print $2}')"   # macOS
  hostname -I | awk '{print $1}'                                            # Linux
  ```

**獨佔主機**：把該主機上 `env/.env.<env>` 的 `HTTP_PORT` 改成 `80`，網址就是 `http://<host>`。

**改埠**：改 `env/.env.<env>` 的 `HTTP_PORT`，再重跑 `make deploy ENV=<env> …`。
（env 檔是主機上的本機檔案，不在映像裡，所以改完不需要重新 build。）

---

## `proxy`

不綁主機埠，接上整台機器共用的 reverse proxy，由它依 `DOMAIN` 把請求導到對應的 environment。

```
                        ┌─ dev.fullstack.localhost  → dev  這組 container
瀏覽器 → proxy(:80) ─────┼─ qas.fullstack.localhost  → qas  這組 container
                        └─ fullstack.localhost      → prod 這組 container
```

（`fullstack` 是專案名，來自 Makefile 的 `APP_NAME`——`make init` 之後會是你的名字。）

### Prerequisite: a machine-wide reverse proxy

**這份 proxy 不在本 repo**，因為它是「一台機器一份」，而 app 是「一台機器多個」——每個 app repo
各帶一份，只會互相搶 80 埠。

本 repo 依賴的**契約**是四件事，任何滿足它的 proxy 都可以：

1. 一個名為 **`proxy`** 的 external Docker network（本 repo 的 frontend 會接上去）
2. 一個名為 **`web`** 的 entrypoint，綁在主機的 **80** 埠
3. 啟用 **Docker provider**，且 `exposedbydefault=false`——只導流明確貼了 `traefik.enable=true` 的 container
4. Docker provider 的預設 network 設為 **`proxy`**

我用的實作是 [aj006600/traefik-proxy](https://github.com/aj006600/traefik-proxy)（Traefik v3，
`make up` 一次，整台機器共用）。你也可以用自己的——只要滿足上面四項。

### Bring up

```bash
make deploy EXPOSE=proxy ENV=dev  IMAGE=ghcr.io/<your-account>/<your-repo> TAG=<git-sha>
make deploy EXPOSE=proxy ENV=qas  IMAGE=… TAG=…
make deploy EXPOSE=proxy ENV=prod IMAGE=… TAG=vX.Y.Z
make ps
```

每個 environment 靠 env 檔的 `DOMAIN` 註冊路由。停某一個：`make down EXPOSE=proxy ENV=dev`。

### Domain

`DOMAIN` 必須**能解析到這台主機**。預設的 `*.localhost` 只在**主機自己**上開瀏覽器時有效
（`*.localhost` 永遠指向 127.0.0.1），適合部署後在主機上驗證。

要讓別人連得到，就得換成真的解析得到這台機器的名字——內網、公開域名各有做法，
見 [traefik-proxy 的 README](https://github.com/aj006600/traefik-proxy)（domain 怎麼解析是 proxy 的事，
本 repo 不重述）。**執行時傳入即可，不要改 `env/.env.*`**（那是被 git 追蹤的檔案）：

```bash
DOMAIN=dev.app.example.com make deploy EXPOSE=proxy ENV=dev IMAGE=… TAG=…
```

---

## Troubleshooting

### `Bind for 0.0.0.0:<port> failed: port is already allocated`

只有 `ports` 會遇到。

```bash
lsof -nP -iTCP:<port> -sTCP:LISTEN      # 看什麼程式占用
docker ps --filter publish=<port>        # 或看是哪個 container
```

解法：停掉占用者，或改 `env/.env.<env>` 的 `HTTP_PORT` 再重跑。
若占用 80 埠的是共用 proxy，代表這台機器已經在跑 `proxy`——兩種曝露方式不能同時搶 80。

### 404 from the proxy

只有 `proxy` 會遇到。網址**有解析成功**（請求到了 proxy），只是 proxy 沒有對應的路由：

```bash
docker ps --format '{{.Names}}\t{{.Networks}}' | grep fullstack   # 環境起來了、且接上 proxy network？
grep DOMAIN env/.env.dev                                          # 打的網址跟 DOMAIN 一致嗎？
```

最常見原因是**打的網址與 `DOMAIN` 不一致**——路由規則是 `Host(<DOMAIN>)`，不 match 就 404。
proxy 本身沒起來、或路由表怎麼看，屬於 proxy 那邊的排查。
