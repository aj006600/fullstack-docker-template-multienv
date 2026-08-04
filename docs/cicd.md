# CI/CD & Release

[← README](../README.md) ｜ 觀念先修：[concepts.md](concepts.md)

## Development flow (trunk-based)

只有一個長期分支 `main`。所有改動走「短命 feature branch → PR → merge main」：

```bash
git checkout -b fix/xxx
# 改、commit、git push -u origin fix/xxx
gh pr create --fill
gh pr merge --squash    # CI 綠燈後自己就能 merge（approvals = 0）
```

- PR 觸發測試；merge 到 main 才 build + 部署 **dev/qas**；打 `v*` tag 才上 **prod**
- 純文件變更（`.md`、`docs/**`）靠 `paths-ignore` 跳過 build/deploy

## Build-once promotion

**Build 一次 → 兩個 service 各打不可變的 git SHA tag → 同一組 image promote。** dev/qas 靠 merge 自動、prod 靠打 tag——各環境跑的都是**同一組 image**（用 SHA 指定），不重 build、不靠 `latest`。

```
merge main ─▶ test ─▶ build(backend+frontend :sha) ─▶ deploy-dev ─▶ deploy-qas     （自動）
git tag v* ─▶ test ─▶ release(:sha→:v*) ─▶ deploy-prod                             （發版才觸發）
                                              ▲
                    GitHub Environment「production」設 required reviewers → 上 prod 需人工核准
```

Image 位置（兩個）：

```
ghcr.io/<your-account>/fullstack-docker-template-multienv-backend:<git-sha>
ghcr.io/<your-account>/fullstack-docker-template-multienv-frontend:<git-sha>
```

> deploy-dev/qas/prod job 目前只**印出**「該在主機上執行的 `make deploy` 指令」，尚未連線主機。promotion 結構與審核閘門已就緒，接上 SSH / docker context 讓 CI 真的在主機執行該指令即可（見 [roadmap.md](roadmap.md)）。

## Deploy execution: make deploy

Deployment = 在**目標主機**上「拉 CI 測過的不可變 image + `up -d`」，**不在主機重 build**（在主機重 build 會破壞 build-once 的保證）。CI 與人工走**同一條指令**，不會漂移：

```bash
make deploy MODE=<separate-hosts|same-host-by-port|same-host-by-domain> ENV=<dev|qas|prod> \
    IMAGE=ghcr.io/<your-account>/fullstack-docker-template-multienv TAG=<git-sha 或 vX.Y.Z>
```

職責分工：

```
CI/CD（自動）    ＝ 決策 + 閘門 + 紀錄：何時部署（merge / tag）、部署哪顆（sha）、
                   測試綠燈、prod 人工核准、Environments 部署歷史
make deploy      ＝ 執行原語：拉指定 TAG + up。CI 呼叫它；人工只在 bootstrap／緊急／rollback 時用
make up-*        ＝ 本機 preview（build 本機 code），與 deployment 無關
```

## Release to prod (git tag)

```bash
git checkout main && git pull          # 1. 要發的 commit 已在 main、dev/qas 驗過（:sha 已 build）
git tag v1.2.0                         # 2. 打版本 tag
git push origin v1.2.0                 # 3. 推 tag → 觸發 prod 發版
```

會把測試過的 `:sha` **加上版本 tag `:v1.2.0`（不重 build）**，再部署 prod。

> - `production` environment 若設了 required reviewers，發版會**停下等人核准**。
> - tag 要打在**已在 main、已 build** 的 commit（否則找不到對應的 `:sha` image）。

## Which version is running

Image 用 **git SHA** 當 tag，所以「哪個環境跑哪一版」= 「跑哪個 SHA」。

```bash
git log --oneline -10                 # 看最近的 commit 與其 SHA
git show <sha>                        # 看某個 SHA 改了什麼
git checkout <sha>                    # 切過去看該版 code（看完 git switch - 回來）

docker ps --format '{{.Image}}'       # 看正在跑的 container 用哪顆 image
```

> GitHub 網頁 → repo → **Environments**：可看每個環境「部署了哪個 SHA、何時、由誰」的完整歷史。不用開環境分支。

## Rollback

Image 不可變且都留在 registry，所以 **rollback = 重新部署上一組好的 SHA，不需重新 build**：

```bash
git log --oneline                     # 1. 找出要回到的舊 SHA

# 2. 在目標主機上把該環境部署回舊 SHA（一行）
make deploy MODE=<擇一> ENV=prod \
    IMAGE=ghcr.io/<your-account>/fullstack-docker-template-multienv TAG=<old-sha>
```

## Version tags (optional)

```bash
git tag v1.0.0 && git push origin v1.0.0   # 發版時打 tag（也會觸發 prod 發版，見上方 Release）
git checkout v1.0.0                          # 之後要看該版 code
```

## Image cleanup

`.github/workflows/cleanup.yml` 每週跑一次——兩個 service 的 `:sha` 建置各**只留最近 10 個**、**保護 `latest` 與 `v*` 正式版**、刪 untagged。避免 image 無限累積。

## One-time GitHub setup

以下設定存在 GitHub、不在程式碼裡，各做一次即可。

### 1. Prod approval (Environments)

> **注意：prod 只在打 `v*` tag 時才部署（merge 不會碰 prod）。但即使打了 tag，若沒設 required reviewers，`production` 也不會擋——會直接上。**

到 **Settings → Environments** 建立 `dev`、`qas`、`production`，並在 `production` 加 **Required reviewers**（發版才會停下等人核准）。

### 2. Branch protection (require PR + green CI)

到 **Settings → Branches** 對 `main` 加規則：

- **Require a pull request before merging**（禁止直接 push；單人可把 required approvals 設 0）
- **Require status checks to pass** → 勾 `test-backend` 和 `build-frontend`
- **Do not allow bypassing the above settings**（連 owner 也受限）

> 免費方案的**私有** repo 無法用 branch protection，需 GitHub Pro 或改為 **public**。

## Side note: dual hosting on GitLab + GitHub (deferred)

CI 設定檔是**平台專屬**的，兩份可並存、各讀各的；`backend/`、`frontend/`、`compose.yaml` 完全共用：

| 平台 | CI 設定檔 |
|------|----------|
| GitHub Actions | `.github/workflows/*.yml`（現有） |
| GitLab CI | `.gitlab-ci.yml`（放根目錄，之後再加） |

真的要做時，先決定三件事（避免常見陷阱）：

1. **選一邊當真相來源**，用倉庫鏡像（mirror）自動同步另一邊——避免兩邊各自 push 造成分岔。
2. **避免兩邊都跑 CI／都部署**（除非故意，例如各部署到不同雲）。
3. **Secrets 與 registry 各平台各設**（GHCR vs GitLab Container Registry）。
