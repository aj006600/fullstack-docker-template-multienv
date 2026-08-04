# Core Concepts

[← README](../README.md)

四個核心觀念，按順序讀。搞懂這些，其餘文檔都是操作細節。

## One image, config per environment

**三個環境（dev / qas / prod）跑的是同一顆 image**，差別只在**載入哪份 `env/.env.<env>` 設定**。這是 12-factor 核心：一份 code、一顆 image、設定隨環境變。

接線（以 qas 為例）：

```bash
make up-domain-qas
#  = COMPOSE_PROJECT_NAME=fullstack-qas docker compose … --env-file env/.env.qas up -d --build
```

1. `--env-file env/.env.qas` 讀進 `env/.env.qas` → 其中 `APP_ENV=qas`
2. `compose.yaml` 的 `env_file: env/.env.${APP_ENV:-dev}` 用這個 `APP_ENV` 解析成 `env/.env.qas`
3. Container 載入 `env/.env.qas`（`APP_ENV`、`LOG_LEVEL`、`DOMAIN`、`HTTP_PORT`…）

> 「是哪個環境」= **哪份 env 檔被載入**，不是哪顆 image。CI/CD 部署也一樣：build 一次打 `:sha`，dev/qas/prod promote **同一顆** `:sha`——這才保證「dev 測過的就是上 prod 的那顆」。

## Three commands: dev / up-* / deploy

| 指令 | 職責 | Image 來源 |
|------|------|-----------|
| `make dev` | **Development**（寫 code、hot reload） | 本機 code（掛載） |
| `make up-*` | **Preview**：本機預覽 env 設定 / exposure topology | 本機 code 現場 build |
| `make deploy` | **Deployment**：目標主機上執行（CI 與人工共用同一條） | **拉 CI 測過的 `:sha`**，不重 build |

`make dev` 和 `make up-*` 的差別：

| | `make dev` | `make up-separate-hosts` / `up-port-*` / `up-domain-*` |
|---|-----------|--------------------------------------------------------|
| 目的 | **本機開發**（寫 code） | **預覽環境**（設定 + topology） |
| 環境數 | 只有 **dev 一個** | **dev / qas / prod** 可同時並存 |
| 跑什麼 | 掛載 source code + **hot reload** | **build 好的 image**（改 code 不反映，需 rebuild） |
| 執行方式 | 前景（`Ctrl+C` 停、`make dev-down` 清） | 背景 `-d`（**一定要 `make down-*`** 才會停） |
| 怎麼連 | `localhost:3000/8000` | 依 topology（80 埠 / `IP:port` / domain） |

## Preview vs Deployment

**在你機器上跑 `make up-*` ≠ deployment。** 它 `--build` 用你當前 code 現場建，用途是**預覽/測試「該環境的 `env/.env.*` 設定 + exposure topology」**。三種 topology 的預覽能力不同：

- **B（port）/ C（domain）**：可在本機**同時起三個環境**，驗證各環境設定與導流（埠配置、Traefik 路由）。
- **A（separate-hosts）**：多機 topology**無法單機模擬**；本機跑 `up-separate-hosts` 只能**一次預覽一個環境**（都綁 80）。

用詞澄清：`deploy/compose.*.yaml` 是**exposure topology**（部署時用哪種對外方式）；**在本機跑它們是 preview，不等於 deployment**。

真部署 = 在**目標主機**上拉 **CI 測過的那顆 `:sha`** 跑（不重 build），用 `make deploy`：

```bash
make deploy MODE=same-host-by-domain ENV=dev \
    IMAGE=ghcr.io/<your-account>/fullstack-docker-template-multienv TAG=<git-sha>
# MODE = separate-hosts | same-host-by-port | same-host-by-domain
# TAG  = <git-sha>（dev/qas）或 vX.Y.Z（prod）
```

> 環境不「知道」自己該用哪顆 image——**版本（`TAG`）是傳入的**，由 promotion 流程決定：merge → CI 以該 commit 的 sha 部署 dev+qas；打 `v*` tag → prod（見 [cicd.md](cicd.md)）。人工部署 / rollback 就自己指定 `TAG`。「哪個環境跑哪顆」的紀錄 = GitHub Environments 部署歷史 + `docker ps` 的 image tag。

## Local vs CI/CD: two separate worlds

同樣叫 dev/qas/prod，但**「本機自己跑」和「CI/CD 部署」是兩個不相干的世界**，更新方式完全不同。常見誤解是「merge 一下、本機 `make up-*` 的環境就變新」——不會。

### Local: re-run `make up-*`

`make up-*` 用你**當下的本機 code** 現場 `--build`。**merge PR 不會更新它們**；改了 code 想讓本機環境變新，就自己重跑：

```bash
make up-domain-dev        # 用目前本機 code 建 + 跑 dev
# …改了 code…
make up-domain-dev        # 再跑一次即可，不用先 down（見下）
make down-domain-dev      # 收工要停時
```

> **改完 code 直接重跑 `make up-*` 就好，不用先 `make down-*`**——`up -d --build` 會 rebuild image、並自動把舊 container 換成新的（recreate，僅幾秒短暫中斷）。只有改了 **compose 結構**（network / volume / service）或想全新乾淨重來時，才先 `make down-*` 再 up。

> 這些 container 跟 GitHub / CI **無關**，不會因為你 merge 就自動變新。

> **本機這顆 image ≠ 最近 merge 那顆 `:sha`。** `make up-*` 建的是**你本機當前工作區的 code**（連未 commit 的改動都算），不會去 registry 拉 CI 建的 image。所以它跟「最近 merge 那顆」的關係全看你本機狀態：`git pull` 且無本機改動 → 內容相同（但仍是本機另建的一顆）；有未 commit 改動 → 比它新；本機落後 main → 比它舊。要真的跑「最近 merge 的那顆」，用 **`make deploy`**（拉 CI 建好的 `:sha`、不重 build）。

### Remote (CI/CD): merge / git tag

推到 GitHub 後由 CI 自動 build image 並部署（詳見 [cicd.md](cicd.md)）：

```bash
gh pr merge --squash                        # 部署 dev + qas（merge 到 main 自動觸發，不含 prod）
git tag v1.2.0 && git push origin v1.2.0    # 部署 prod（只有打 v* tag 才觸發，需人工核准）
```

### Which command updates what

| 指令 | 更新哪裡 | 更新哪個環境 |
|------|---------|-------------|
| `make up-*`（**重跑**） | 你**本機** | 你指定的那一個 |
| `gh pr merge`（merge main） | **遠端 CI 部署** | **dev + qas**（不含 prod） |
| `git tag v* && git push` | **遠端 CI 部署** | **prod**（需核准） |

> 目前 CI 的 deploy job 只會**印出「該在主機上執行的 `make deploy` 指令」**，尚未真的連線主機——接上 SSH / docker context 後（見 [roadmap.md](roadmap.md)），上表「遠端」那兩列才會真的部署到伺服器。
