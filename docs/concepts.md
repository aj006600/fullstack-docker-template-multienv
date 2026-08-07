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
| 環境數 | 只有 **dev 一個** | dev / qas / prod（可同機並存） |
| Image | 本機現場 build，掛載 source code | registry 的 `:sha` 或 `:vX.Y.Z` |
| 執行方式 | 前景（`Ctrl+C` 停、`make dev-down` 清） | 背景 `-d`（`make down` 才會停） |
| 怎麼連 | `localhost:3000` / `:8000` | 依 topology（`IP:port` 或 domain） |

**刻意沒有第三個「在本機 build 然後部署」的指令。** 在目標主機上重 build 會拉到不同的 base layer 或相依，
「dev 測過的就是上 prod 的那顆」這個保證就沒了。要臨時在開發機上跑某個 environment，
[deployment.md](deployment.md#running-an-environment-on-your-dev-machine) 有手動指令——但那是例外，不是部署路徑。

> 版本永遠是**傳入的**——environment 不「知道」自己該跑哪顆 image。`make deploy` 的 `TAG` 由 promotion 流程
> 決定（merge → 該 commit 的 `:sha` 部署 dev+qas；打 `v*` tag → prod），人工部署與 rollback 就自己指定。
> 見 [cicd.md](cicd.md)。

> **「哪個環境跑哪顆」只能靠主機上 `docker ps` 的 image tag。** pipeline 不部署，所以 GitHub
> 那邊沒有部署紀錄可查（見 [cicd.md](cicd.md)）。

## Local vs CI/CD: two separate worlds

同樣叫 dev/qas/prod，但**「你本機的 `make dev`」和「CI/CD 部署的環境」是兩個不相干的世界**。

**本機**：`make dev` 跑的永遠是你**當下的工作區**，連未 commit 的改動都算，而且只有 dev 一個環境。
它跟 GitHub 無關，不會因為誰 merge 了什麼而改變。

**遠端**：推到 GitHub 後由 pipeline 建置並標籤（CI）。部署是另一件事，由人執行：

```bash
gh pr merge --squash                        # build 出該 commit 的 :sha
git tag v1.2.0 && git push origin v1.2.0    # 把該 :sha 加標成 :v1.2.0
```

| 指令 | 動到哪裡 | 效果 |
|------|---------|------|
| `make dev`（重跑） | 你**本機** | 只有 dev，立即生效 |
| `gh pr merge`（merge main） | **registry** | 產出 `:sha`，沒有任何環境變動 |
| `git tag v* && git push` | **registry** | 產出 `:vX.Y.Z`，沒有任何環境變動 |
| `make deploy`（在主機上） | **那台主機** | 唯一會改變執行中環境的動作 |

> 推到 GitHub 不會改變任何正在跑的環境——pipeline 的職責到「建置與標籤」為止。要讓某個
> environment 換版，一定要有人在該主機上跑 `make deploy`（見 [cicd.md](cicd.md)）。
