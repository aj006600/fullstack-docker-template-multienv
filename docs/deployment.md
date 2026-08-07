# Deployment

[← README](../README.md) ｜ 觀念先修：[concepts.md](concepts.md) ｜ 詞彙：[CONTEXT.md](../CONTEXT.md)

部署 = 在某台主機上讓某個 environment 跑起來。兩個旋鈕：

| 旋鈕 | 決定什麼 | 值 |
|------|---------|----|
| `EXPOSE` | **Topology**——怎麼對外曝露 | `ports` ｜ `proxy` |
| `ENV` | **Environment**——載入哪份設定 | `dev` ｜ `qas` ｜ `prod` |

部署在**目標主機**上執行，拉 CI 測過的不可變映像，不重 build：

```bash
make deploy EXPOSE=<topology> ENV=<env> IMAGE=… TAG=…    # 拉指定版本並啟動
make down   EXPOSE=<topology> ENV=<env>                  # 停止
```

`TAG` 是 `:sha`（dev/qas）或 `vX.Y.Z`（prod），由 promotion 流程決定；rollback 就換回舊的 sha。
見 [cicd.md](cicd.md)。

> **主機必須是 amd64 Linux。** CI 只建 amd64——在 Apple Silicon 的開發機上 `make deploy` 會失敗
> （`no matching manifest for linux/arm64`）。開發機請用 `make dev`；理由與例外見 [roadmap.md](roadmap.md)
> 與本文最後一節。

## Choosing a topology

只有兩種真正不同的曝露方式：

| Topology | 做什麼 | 何時選 | 網址長相 |
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

`env/.env.dev`、`env/.env.qas`、`env/.env.prod` 各放該 environment 的**非機密**設定：`APP_ENV`、`LOG_LEVEL`、
以及 topology 的參數——`ports` 用 `HTTP_PORT`、`proxy` 用 `DOMAIN`。
真正的密鑰走 CI secrets 或部署時注入，別提交進 repo（見 [roadmap.md](roadmap.md)）。

### 3. Push and let CI build

`make deploy` 拉的是 registry 裡的映像，所以要先 merge 到 `main`、讓 CI 建出該 commit 的 `:sha`。
之後在主機上帶那個 sha 部署。

### 4. Log in to the registry (只有 package 是 private 時才需要)

GHCR 的 package 預設跟著 repo 的可見性走。**package 是 public 的話這步跳過**——`docker compose pull`
不需要認證。

package 是 private 時，目標主機要先登入**一次**（這是主機的 bootstrap，不是每次部署的參數）：

```bash
echo <PAT> | docker login ghcr.io -u <你的帳號> --password-stdin
```

PAT 需要 `read:packages` 權限。沒登入的話 `make deploy` 會停在 `pull` 這步，錯誤訊息是
`denied` 或 `unauthorized`。

> CD（deploy job）之後真的連上主機時同樣要處理這件事，見 [roadmap.md](roadmap.md)。

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
                        ┌─ dev.app.localhost  → dev  這組 container
瀏覽器 → proxy(:80) ─────┼─ qas.app.localhost  → qas  這組 container
                        └─ app.localhost      → prod 這組 container
```

### Prerequisite: 一份整台機器共用的 reverse proxy

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

### 回 404

代表網址**有解析成功**（請求到了 proxy），只是 proxy 沒有對應的路由：

```bash
docker ps --format '{{.Names}}\t{{.Networks}}' | grep fullstack   # 環境起來了、且接上 proxy network？
grep DOMAIN env/.env.dev                                          # 打的網址跟 DOMAIN 一致嗎？
```

最常見原因是**打的網址與 `DOMAIN` 不一致**——路由規則是 `Host(<DOMAIN>)`，不 match 就 404。
proxy 本身沒起來、或路由表怎麼看，屬於 proxy 那邊的排查。

---

## Troubleshooting

### `Bind for 0.0.0.0:<port> failed: port is already allocated`

`ports` topology 才會遇到。

```bash
lsof -nP -iTCP:<port> -sTCP:LISTEN      # 看什麼程式占用
docker ps --filter publish=<port>        # 或看是哪個 container
```

解法：停掉占用者，或改 `env/.env.<env>` 的 `HTTP_PORT` 再重跑。
若占用 80 埠的是共用 proxy，代表這台機器已經在跑 `proxy` topology——兩種 topology 不能同時搶 80。

---

## Running an environment on your dev machine

日常開發用 `make dev` 就好。但偶爾你會想在開發機上看某個 environment 的完整部署形態——
例如驗證 topology 設定、或 debug「dev stage 正常、runtime stage 壞掉」這種只在非 root 下出現的問題。

**這個 template 刻意不提供對應的 `make` target**，因為同一個指令在正式主機上執行就是反模式
（在主機重 build 會破壞 build-once 的保證，見 [concepts.md](concepts.md#two-commands-two-places)）。
真的需要時手動執行：

```bash
COMPOSE_PROJECT_NAME=fullstack-qas APP_NAME=fullstack docker compose \
  -f compose.yaml -f deploy/compose.ports.yaml \
  --env-file env/.env.qas up -d --build

make down EXPOSE=ports ENV=qas      # 停止
```

兩個變數都不能省：`COMPOSE_PROJECT_NAME` 省了會用資料夾名當 project 名，跟 `make dev` 的 container
互相覆蓋；`APP_NAME` 省了 `env/.env.*` 的 `DOMAIN` 會插值成畸形的 `qas..localhost`——而且只是**警告**，
不會失敗。平常走 `make` 時這兩個都由 Makefile 帶入。

注意這樣跑起來的東西：**沒有經過 CI 把關，image 名是 `fullstack-backend:latest`、追不到版本**。
它是臨時檢查手段，不是部署方式——不要讓別人長期連它。
