# CI/CD & Release

[← README](../README.md) ｜ 觀念先修：[concepts.md](concepts.md) ｜ 詞彙：[CONTEXT.md](../CONTEXT.md)

## Development flow (trunk-based)

只有一個長期分支 `main`。所有改動走「短命 feature branch → PR → merge main」：

```bash
git checkout -b fix/xxx
# 改、commit、git push -u origin fix/xxx
gh pr create --fill
gh pr merge --squash    # CI 綠燈後自己就能 merge（approvals = 0）
```

- PR 觸發測試；merge 到 main 才 build + 部署 **dev/qas**；打 `v*` tag 才上 **prod**
- main 上**每個** commit 都會 build 出 `:sha`（含純文件 commit）——promote、rollback、`git bisect` 都依賴這個不變量。重複建置的成本由 build cache 吸收

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
ghcr.io/<your-account>/<your-repo>-backend:<git-sha>
ghcr.io/<your-account>/<your-repo>-frontend:<git-sha>
```

> deploy-dev/qas/prod job 目前只**印出**「該在主機上執行的 `make deploy` 指令」，尚未連線主機。promotion 結構與審核閘門已就緒，接上 SSH / docker context 讓 CD（deploy job）真的在主機執行該指令即可（見 [roadmap.md](roadmap.md)）。

## Deploy execution: make deploy

Deployment = 在**目標主機**上「拉 CI 測過的不可變 image + `up -d`」，**不在主機重 build**（在主機重 build 會破壞 build-once 的保證）。pipeline 與人工走**同一條指令**，不會漂移：

```bash
make deploy EXPOSE=<ports|proxy> ENV=<dev|qas|prod> \
    IMAGE=ghcr.io/<your-account>/<your-repo> TAG=<git-sha 或 vX.Y.Z>
```

職責分工：

```
CI/CD（自動）    ＝ 決策 + 閘門 + 紀錄：何時部署（merge / tag）、部署哪顆（sha）、
                   測試綠燈、prod 人工核准、Environments 部署歷史
make deploy      ＝ 執行原語：拉指定 TAG + up。CD（deploy job）呼叫它；人工只在 bootstrap／緊急／rollback 時用
```

## Release to prod (git tag)

```bash
git checkout main && git pull          # 1. 要發的 commit 已在 main、dev/qas 驗過（:sha 已 build）
git tag v1.2.0                         # 2. 打版本 tag
git push origin v1.2.0                 # 3. 推 tag → 觸發 prod 發版
```

會把測試過的 `:sha` **加上版本 tag `:v1.2.0`（不重 build）**，再部署 prod。

> `production` environment 若設了 required reviewers，發版會**停下等人核准**。

**tag 必須指向已經 build 完成的 commit。** `release` job 是把既有的 `:sha` 重新貼標籤，所以那顆映像要先存在。
merge 之後**立刻**打 tag 有可能搶在 main 的 build 完成之前（tag 與 main 是不同的 ref，concurrency 不會讓它們排隊），
此時 job 會以 `manifest unknown` 失敗。

這個失敗是**安全**的——沒有任何東西被發布。等 main 的 build 跑完，在 Actions 頁面 re-run 該 job 即可，不必重打 tag。

> 反過來說，`:sha` 存在本身就證明那個 commit 上過 main 且測試綠燈（`build` job 的前提就是這兩件事），
> 所以指向未經 CI 的 commit 的 tag 也會在這一步失敗，不會漏出去。

## Which version is running

Image 用 **git SHA** 當 tag，所以「哪個環境跑哪一版」= 「跑哪個 SHA」。

```bash
git log --oneline -10                 # 看最近的 commit 與其 SHA
git show <sha>                        # 看某個 SHA 改了什麼
git checkout <sha>                    # 切過去看該版 code（看完 git switch - 回來）
git checkout v1.0.0                   # 或用版本 tag 切到某次發版的 code

docker ps --format '{{.Image}}'       # 看正在跑的 container 用哪顆 image
```

> GitHub 網頁 → repo → **Environments** 會列出部署歷史，但 deploy job 目前只印指令、不連線主機，
> 所以那些紀錄**不代表實際部署發生過**。現階段請以主機上的 `docker ps` 為準；接上 SSH / docker context
> 之後（見 [roadmap.md](roadmap.md)），Environments 才會成為可信的紀錄。

## Rollback

Image 不可變且都留在 registry，所以 **rollback = 重新部署上一組好的 SHA，不需重新 build**：

```bash
git log --oneline                     # 1. 找出要回到的舊 SHA

# 2. 在目標主機上把該環境部署回舊 SHA（一行）
make deploy EXPOSE=<ports|proxy> ENV=prod \
    IMAGE=ghcr.io/<your-account>/<your-repo> TAG=<old-sha>
```

## Image cleanup

`.github/workflows/cleanup.yml` 每週跑一次——兩個 service 的 `:sha` 建置各**只留最近 50 個**、**保護 `v*` 正式版**（永不刪除，rollback 才有得回）、刪 untagged。避免 image 無限累積。

> 這個數字就是 dev/qas 的 rollback 視窗有多深（main 每個 commit 建一顆）。package 名由
> `GITHUB_REPOSITORY` 推導，fork 或改名都不必改那個檔案。

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

### 3. 若要把 repo 轉為 private：先升級方案，再轉

順序反了會掉設定。GitHub **Free 方案的私有 repo** 不支援 branch protection 與 rulesets，也**不能設定
Environments**——連帶失去 environment secrets 與 prod 的 required reviewers，上面兩節就全部做不了。
而且 public repo 轉 private 時，**既有的 protection rules 與 environment secrets 會直接失效**，
不是保留但停用；等升級後還得重設一次。

所以要轉私有：**先升到 GitHub Pro 以上**（私有 repo 才能用 Environments），再轉。

若堅持留在免費方案並轉私有，剩下的只有可見性——PR 仍會觸發 `test-backend` 與 `build-frontend`、
紅燈仍看得見，但 `main` 可被直接 push、紅燈擋不住 merge、上 prod 也不會停下等核准。
單人 repo 的實務影響有限（這些機制主要是擋別人）。

> 順帶一提，維持 public 的話 Actions 分鐘數與 Packages 儲存都不計費；轉私有後兩者都開始計入方案額度。

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
