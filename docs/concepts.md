# Core Concepts

[← README](../README.md) ｜ 詞彙：[CONTEXT.md](../CONTEXT.md)

三個核心觀念，按順序讀。搞懂這些，其餘文檔都是操作細節。

## One image, config per environment

**三個 environment（dev / qas / prod）跑的是同一顆 image**，差別只在**載入哪份 `env/.env.<env>` 設定**。
這是 12-factor 核心：一份 code、一顆 image、設定隨環境變。

接線（以 qas 為例）：

```bash
make deploy ENV=qas IMAGE=… TAG=…
#  = COMPOSE_PROJECT_NAME=fullstack-qas docker compose … --env-file env/.env.qas up -d --no-build
```

1. `--env-file env/.env.qas` 讀進該檔 → 其中 `APP_ENV=qas`
2. `compose.yaml` 的 `env_file: env/.env.${APP_ENV:-dev}` 用這個 `APP_ENV` 解析成 `env/.env.qas`
3. Container 載入 `env/.env.qas`（`APP_ENV`、`LOG_LEVEL`、`DOMAIN`、`HTTP_PORT`…）

> 「是哪個 environment」= **哪份 env 檔被載入**，不是哪顆 image。CI/CD 也一樣：build 一次打 `:sha`，
> dev/qas/prod promote **同一顆**——這才保證「dev 測過的就是上 prod 的那顆」。

## Two commands, two places

只有兩個指令，各有各的地盤：

| 指令 | 在哪執行 | 跑什麼 |
|------|---------|--------|
| `make dev` | **你的開發機** | 掛載本機 source code、hot reload、直連 `localhost` |
| `make deploy` | **目標主機** | 拉 CI 測過的不可變映像，`--no-build` |

| | `make dev` | `make deploy` |
|---|-----------|---------------|
| 目的 | 寫 code | 部署某個 environment |
| 環境數 | 只有 **dev 一個** | dev / qas / prod（topology B / C 可同機並存） |
| Image | 本機現場 build，掛載 source code | registry 的 `:sha` 或 `:vX.Y.Z` |
| 執行方式 | 前景（`Ctrl+C` 停、`make dev-down` 清） | 背景 `-d`（`make down` 才會停） |
| 怎麼連 | `localhost:3000` / `:8000` | 依 topology（80 埠 / `IP:port` / domain） |

**刻意沒有第三個「在本機 build 然後部署」的指令。** 在目標主機上重 build 會拉到不同的 base layer 或相依，
「dev 測過的就是上 prod 的那顆」這個保證就沒了。要臨時在開發機上跑某個 environment，
[deployment.md](deployment.md#running-an-environment-on-your-dev-machine) 有手動指令——但那是例外，不是部署路徑。

> 版本永遠是**傳入的**——environment 不「知道」自己該跑哪顆 image。`make deploy` 的 `TAG` 由 promotion 流程
> 決定（merge → 該 commit 的 `:sha` 部署 dev+qas；打 `v*` tag → prod），人工部署與 rollback 就自己指定。
> 「哪個環境跑哪顆」的紀錄 = GitHub Environments 部署歷史 + `docker ps` 的 image tag。見 [cicd.md](cicd.md)。

## Local vs CI/CD: two separate worlds

同樣叫 dev/qas/prod，但**「你本機的 `make dev`」和「CI/CD 部署的環境」是兩個不相干的世界**。

**本機**：`make dev` 跑的永遠是你**當下的工作區**，連未 commit 的改動都算，而且只有 dev 一個環境。
它跟 GitHub 無關，不會因為誰 merge 了什麼而改變。

**遠端**：推到 GitHub 後由 pipeline build（CI）並部署（CD）：

```bash
gh pr merge --squash                        # 部署 dev + qas（merge 到 main 自動觸發，不含 prod）
git tag v1.2.0 && git push origin v1.2.0    # 部署 prod（只有打 v* tag 才觸發，需人工核准）
```

| 指令 | 更新哪裡 | 更新哪個 environment |
|------|---------|-------------|
| `make dev`（重跑） | 你**本機** | 只有 dev |
| `gh pr merge`（merge main） | **遠端 CD 部署** | **dev + qas**（不含 prod） |
| `git tag v* && git push` | **遠端 CD 部署** | **prod**（需核准） |

> 目前 pipeline 的 deploy job（CD）只會**印出**「該在主機上執行的 `make deploy` 指令」，尚未真的連線主機——
> 接上 SSH / docker context 後（見 [roadmap.md](roadmap.md)），上表「遠端」那兩列才會真的部署到伺服器。
