# Core Concepts

[← README](../README.md) ｜ 詞彙：[CONTEXT.md](../CONTEXT.md)

三個核心觀念，按順序讀。搞懂這些，其餘文檔都是操作細節。

## One image, config per environment

**三個 environment（dev / qas / prod）跑的是同一顆 image**，差別只在**載入哪份 `env/.env.<env>` 設定**。
這是 12-factor 核心：一份 code、一顆 image、設定隨環境變。

接線（以 qas 為例）：

```bash
make up ENV=qas
#  = COMPOSE_PROJECT_NAME=fullstack-qas docker compose … --env-file env/.env.qas up -d --build
```

1. `--env-file env/.env.qas` 讀進該檔 → 其中 `APP_ENV=qas`
2. `compose.yaml` 的 `env_file: env/.env.${APP_ENV:-dev}` 用這個 `APP_ENV` 解析成 `env/.env.qas`
3. Container 載入 `env/.env.qas`（`APP_ENV`、`LOG_LEVEL`、`DOMAIN`、`HTTP_PORT`…）

> 「是哪個 environment」= **哪份 env 檔被載入**，不是哪顆 image。CI/CD 也一樣：build 一次打 `:sha`，
> dev/qas/prod promote **同一顆**——這才保證「dev 測過的就是上 prod 的那顆」。

## Image provenance: build vs registry

有三個指令會讓服務跑起來。`make dev` 是開發用；另外兩個**都是部署**，差別只在 **image 從哪來**：

| 指令 | 用途 | Image 來源 |
|------|------|-----------|
| `make dev` | **開發**：寫 code、hot reload、直連 `localhost` | 掛載本機 source code |
| `make up` | **部署**：用本機當前 code 現場 build | `--build` 本機工作區 |
| `make deploy` | **部署**：拉 CI 測過的不可變映像 | registry 的 `:sha` 或 `:vX.Y.Z` |

`make up` 與 `make deploy` 吃同樣的 `MODE`（topology）與 `ENV`（environment）、產生同名的 compose project，
所以同一個 `make down` 都收得掉。**選哪個看你有沒有 CI pipeline**：有的話用 `make deploy`——它不在目標主機重
build，才保得住 build-once 的保證（在主機重 build 會拉到不同的 base layer 或相依，破壞「測過的就是上線的」）。

`make dev` 與 `make up` 的差別：

| | `make dev` | `make up` |
|---|-----------|-----------|
| 目的 | **本機開發**（寫 code） | **部署**某個 environment |
| 環境數 | 只有 **dev 一個** | dev / qas / prod 可同時並存（topology B / C） |
| 跑什麼 | 掛載 source code + **hot reload** | build 好的 image（改 code 需重跑 `make up`） |
| 執行方式 | 前景（`Ctrl+C` 停、`make dev-down` 清） | 背景 `-d`（要 `make down` 才會停） |
| 怎麼連 | `localhost:3000` / `:8000` | 依 topology（80 埠 / `IP:port` / domain） |

> 版本永遠是**傳入的**——environment 不「知道」自己該跑哪顆 image。`make deploy` 的 `TAG` 由 promotion 流程
> 決定（merge → 該 commit 的 `:sha` 部署 dev+qas；打 `v*` tag → prod），人工部署與 rollback 就自己指定。
> 「哪個環境跑哪顆」的紀錄 = GitHub Environments 部署歷史 + `docker ps` 的 image tag。見 [cicd.md](cicd.md)。

## Local vs CI/CD: two separate worlds

同樣叫 dev/qas/prod，但**「你本機跑的」和「CI/CD 部署的」是兩個不相干的世界**。
常見誤解是「merge 一下、本機 `make up` 的環境就變新」——不會。

**本機**：`make up` 用你**當下的本機 code** 現場 build，連未 commit 的改動都算。merge PR 不會更新它們；
改了 code 想讓本機環境變新，就自己重跑 `make up ENV=…`——**不用先 `make down`**，`up -d --build` 會 rebuild
並自動把舊 container 換掉（僅幾秒中斷）。只有改了 compose 結構（network / volume / service）或想全新重來時才先 down。

**遠端**：推到 GitHub 後由 pipeline build（CI）並部署（CD）：

```bash
gh pr merge --squash                        # 部署 dev + qas（merge 到 main 自動觸發，不含 prod）
git tag v1.2.0 && git push origin v1.2.0    # 部署 prod（只有打 v* tag 才觸發，需人工核准）
```

| 指令 | 更新哪裡 | 更新哪個 environment |
|------|---------|-------------|
| `make up`（重跑） | 你**本機** | 你指定的那一個 |
| `gh pr merge`（merge main） | **遠端 CD 部署** | **dev + qas**（不含 prod） |
| `git tag v* && git push` | **遠端 CD 部署** | **prod**（需核准） |

> 目前 pipeline 的 deploy job（CD）只會**印出**「該在主機上執行的 `make deploy` 指令」，尚未真的連線主機——
> 接上 SSH / docker context 後（見 [roadmap.md](roadmap.md)），上表「遠端」那兩列才會真的部署到伺服器。
