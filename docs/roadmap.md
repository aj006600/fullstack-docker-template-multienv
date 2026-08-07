# Roadmap

這個範本刻意保持精簡——給你正確的**骨架與流程**，production 細節按你的 app 再長上去。
以下項目是**刻意留白**的（不是缺陷，是「minimal，需要再加」的範圍選擇），需要時再補。

## Known limitations

這一節與其他節不同：**不是「還沒做」，是已經決定不做**，因為它們的成本會轉嫁給每個使用這個範本的人。

- **映像只有 amd64**：CI 在 GitHub 的預設機器（amd64）上建，不做多平台建置。
  **後果：Apple Silicon 的開發機無法用 `make deploy`**（會出現 `no matching manifest for linux/arm64`）——
  開發機請用 `make dev`，部署目標請用 amd64 Linux 主機。
  之所以不補：QEMU 模擬會讓每個 fork 的人每次 merge 都多等數分鐘（即使他從不碰 arm64），
  改用原生 arm64 runner 則要多一組 build matrix 與 manifest 合併 job。
  真的要部署到 arm64 主機（AWS Graviton）時再加，改的只有 `build` job。

## Deployment

- **讓 CD 連上目標主機**：部署指令 `make deploy`（pull tested `:sha` + `up -d`）已就緒，但 pipeline
  **沒有** deploy job——Free 方案的私有 repo 拿不到 Environments，一個既不連線主機、又拿不到核准閘門的
  job 只是每次 merge 白付分鐘數（理由見 [cicd.md](cicd.md#為什麼沒有-deploy-job)）。要自動化得同時補兩件事：
  連線方式（SSH + secrets、docker context 或 self-hosted runner），以及 prod 的核准閘門——後者要先升級到 GitHub Pro。
- **改用 digest 部署**：目前用 `:sha` tag 指定版本。tag 理論上可被覆寫，digest（`@sha256:…`）不行——
  供應鏈保證要求最嚴時，部署與稽核都應記錄 digest 而非 tag。

## Common production needs

- **Secrets 管理**：真正的密鑰怎麼注入部署（GitHub Secrets → deploy、或 Vault / 雲端 secrets manager）。`env/` 只放非機密設定。
- **TLS / HTTPS**：目前純 HTTP。走 `proxy` topology 的話，憑證屬於那份共用 reverse proxy 的職責
  （對外真域名可自動申請 Let's Encrypt；內網用內部 CA / mkcert），本 repo 不需要改動——
  見 [deployment.md](deployment.md) 的契約說明。`ports` topology 則需要自己在前面加一層。
- **資料庫 / stateful 服務**：目前無狀態。加 compose 的 db 服務 + migration + 備份策略。
- **可觀測性**：結構化 log、metrics、tracing。
- **安全掃描**：映像漏洞掃描（Trivy）、Dependabot、SBOM、映像簽章（cosign）。

## Developer tooling

後端已有 ruff（lint + format，select E/F/I/UP/N/B/PT）與跑在 dev stage 容器裡的 `make test`。以下刻意延後：

- **相依自動更新**：`.github/dependabot.yml` 自動更新相依與 Actions 版本（同見上方「安全掃描」）。
  後端用 `==` 精確 pin，沒有自動更新機制就會慢慢腐化。
- **前端品質把關**：`frontend/` **刻意**不設 lint / format / 測試——後端有 ruff（含 CI 的 `format --check`）
  與 pytest，前端 CI 只跑 `npm run build`。這個不對稱是有意識的取捨：前端目前只有一個展示用元件，
  等它長出真正的邏輯，再一次導入 eslint + vitest 比較划算（導入時記得同步 CI 與本機 `make` target）。
- **前端 build-time 設定**：目前前端沒有任何自己的設定——環境是跟 backend 要的（`/api/message`），
  所以三個 environment 共用同一顆前端映像。一旦前端需要 `VITE_*` 這類**建置時**注入的設定，
  build-once promotion 就會被打破（每個 environment 都得各建一顆）。屆時的方向是改成 **runtime 注入**
  （啟動時產生設定檔、或由 backend 提供），而不是每環境建一顆。
- **前端 TypeScript**：目前純 JS。若前端會發展成真正的 Web UI，越早轉換成本越低。
- **後端型別檢查**：目前無 mypy。code 量還小時導入 `strict` 模式最便宜。

