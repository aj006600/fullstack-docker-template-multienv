# CI/CD、發版與 repo 設定

[← 回 README](../README.md)

## 開發流程（trunk-based）

只有一個長期分支 `main`。所有改動走「短命功能分支 → PR → 合併 main」：

```bash
git checkout -b fix/xxx
# 改、commit、git push -u origin fix/xxx
gh pr create --fill
gh pr merge --squash    # CI 綠燈後自己就能 merge（approvals = 0）
```

- PR 觸發測試；merge 到 main 才 build + 部署 **dev/qas**；打 `v*` tag 才上 **prod**
- 純文件變更（`.md`、`docs/**`）靠 `paths-ignore` 跳過 build/deploy

## CI/CD promotion（最佳實踐核心）

**build 一次 → 兩個服務各打不可變的 git SHA 標籤 → 同一組映像 promote。** dev/qas 靠 merge 自動、prod 靠打 tag——各環境跑的都是**同一組映像**（用 SHA 指定），不重 build、不靠 `latest`。

```
merge main ─▶ test ─▶ build(backend+frontend :sha) ─▶ deploy-dev ─▶ deploy-qas     （自動）
git tag v* ─▶ test ─▶ release(:sha→:v*) ─▶ deploy-prod                             （發版才觸發）
                                              ▲
                    GitHub Environment「production」設 required reviewers → 上 prod 需人工核准
```

映像位置（兩個）：

```
ghcr.io/<your-account>/fullstack-docker-template-multienv-backend:<git-sha>
ghcr.io/<your-account>/fullstack-docker-template-multienv-frontend:<git-sha>
```

> deploy 步驟目前是 placeholder（印出要部署的映像與環境）。promotion 結構與審核閘門已就緒，把 `echo` 換成你的實際部署指令即可（見 [docs/roadmap.md](roadmap.md)）。

## 怎麼發版（打 tag 上 prod）

```bash
git checkout main && git pull          # 1. 要發的 commit 已在 main、dev/qas 驗過（:sha 已 build）
git tag v1.2.0                         # 2. 打版本 tag
git push origin v1.2.0                 # 3. 推 tag → 觸發 prod 發版
```

會把測試過的 `:sha` **加上版本標籤 `:v1.2.0`（不重 build）**，再部署 prod。

> - `production` environment 若設了 required reviewers，發版會**停下等人核准**。
> - tag 要打在**已在 main、已 build** 的 commit（否則找不到對應的 `:sha` 映像）。

## 映像自動清理

`.github/workflows/cleanup.yml` 每週跑一次——兩個服務的 `:sha` 建置各**只留最近 10 個**、**保護 `latest` 與 `v*` 正式版**、刪 untagged。避免映像無限累積。

## 一次性設定（GitHub）

以下設定存在 GitHub、不在程式碼裡，各做一次即可。

### 1. prod 人工核准（Environments）

> **注意：prod 只在打 `v*` tag 時才部署（merge 不會碰 prod）。但即使打了 tag，若沒設 required reviewers，`production` 也不會擋——會直接上。**

到 **Settings → Environments** 建立 `dev`、`qas`、`production`，並在 `production` 加 **Required reviewers**（發版才會停下等人核准）。

### 2. 分支保護（require PR + CI 綠燈才能進 main）

到 **Settings → Branches** 對 `main` 加規則：

- **Require a pull request before merging**（禁止直接 push；單人可把 required approvals 設 0）
- **Require status checks to pass** → 勾 `test-backend` 和 `build-frontend`
- **Do not allow bypassing the above settings**（連 owner 也受限）

> 免費方案的**私有** repo 無法用分支保護，需 GitHub Pro 或改為 **public**。

## 備註：雙邊託管 GitLab + GitHub（尚未實作，之後需要再加）

CI 設定檔是**平台專屬**的，兩份可並存、各讀各的；`backend/`、`frontend/`、`compose.yaml` 完全共用：

| 平台 | CI 設定檔 |
|------|----------|
| GitHub Actions | `.github/workflows/*.yml`（現有） |
| GitLab CI | `.gitlab-ci.yml`（放根目錄，之後再加） |

真的要做時，先決定三件事（不然容易踩雷）：

1. **選一邊當真相來源**，用倉庫鏡像（mirror）自動同步另一邊——避免兩邊各自 push 造成分岔。
2. **避免兩邊都跑 CI／都部署**（除非故意，例如各部署到不同雲）。
3. **secrets 與 registry 各平台各設**（GHCR vs GitLab Container Registry）。
