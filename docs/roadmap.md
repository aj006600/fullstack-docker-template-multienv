# Roadmap

這個範本刻意保持精簡——給你正確的**骨架與流程**，production 細節按你的 app 再長上去。
以下項目是**刻意留白**的（不是缺陷，是「minimal，需要再加」的範圍選擇），需要時再補：

## Deployment

- **讓 CD（deploy job）連上目標主機**：拉取式部署指令 `make deploy`（pull tested `:sha` + `up -d`，見 [cicd.md](cicd.md)）已就緒，
  `deploy-dev/qas/prod` job 目前只**印出**該指令、尚未連線主機。補上連線方式（SSH + secrets、docker context、
  或 self-hosted runner）讓 CD 真的在主機執行它。**CD 結構、prod 核准閘門、部署指令都已就緒，只差這一步。**
- **改用 digest 部署**：目前用 `:sha` tag 指定版本。tag 理論上可被覆寫，digest（`@sha256:…`）不行——
  供應鏈保證要求最嚴時，部署與稽核都應記錄 digest 而非 tag。

## Common production needs

- **Secrets 管理**：真正的密鑰怎麼注入部署（GitHub Secrets → deploy、或 Vault / 雲端 secrets manager）。`env/` 只放非機密設定。
- **TLS / HTTPS**：目前純 HTTP。對外真域名可讓 Traefik 自動申請 Let's Encrypt；內網用內部 CA / mkcert。
- **資料庫 / stateful 服務**：目前無狀態。加 compose 的 db 服務 + migration + 備份策略。
- **可觀測性**：結構化 log、metrics、tracing。
- **安全掃描**：映像漏洞掃描（Trivy）、Dependabot、SBOM、映像簽章（cosign）。
- **多架構映像**：目前只 build amd64。要跑 arm64（Apple Silicon / AWS Graviton）需 buildx 多平台建置。

## Developer tooling

後端已有 ruff（lint + format，select E/F/I/UP/N/B/PT）與跑在 dev stage 容器裡的 `make test`。以下刻意延後：

- **相依自動更新**：`.github/dependabot.yml` 自動更新相依與 Actions 版本（同見上方「安全掃描」）。
  後端用 `==` 精確 pin，沒有自動更新機制就會慢慢腐化。
- **前端品質把關**：`frontend/` **刻意**不設 lint / format / 測試——後端有 ruff（含 CI 的 `format --check`）
  與 pytest，前端 CI 只跑 `npm run build`。這個不對稱是有意識的取捨：前端目前只有一個展示用元件，
  等它長出真正的邏輯，再一次導入 eslint + vitest 比較划算（導入時記得同步 CI 與本機 `make` target）。
- **前端 TypeScript**：目前純 JS。若前端會發展成真正的 Web UI，越早轉換成本越低。
- **後端型別檢查**：目前無 mypy。code 量還小時導入 `strict` 模式最便宜。

