# Roadmap

這個範本刻意保持精簡——給你正確的**骨架與流程**，production 細節按你的 app 再長上去。
以下項目是**刻意留白**的（不是缺陷，是「minimal，需要再加」的範圍選擇），需要時再補：

## Deployment

- **讓 CD（deploy job）連上目標主機**：拉取式部署指令 `make deploy`（pull tested `:sha` + `up -d`，見 [cicd.md](cicd.md)）已就緒，
  `deploy-dev/qas/prod` job 目前只**印出**該指令、尚未連線主機。補上連線方式（SSH + secrets、docker context、
  或 self-hosted runner）讓 CD 真的在主機執行它。**CD 結構、prod 核准閘門、部署指令都已就緒，只差這一步。**

## Common production needs

- **Secrets 管理**：真正的密鑰怎麼注入部署（GitHub Secrets → deploy、或 Vault / 雲端 secrets manager）。`env/` 只放非機密設定。
- **TLS / HTTPS**：目前純 HTTP。對外真域名可讓 Traefik 自動申請 Let's Encrypt；內網用內部 CA / mkcert。
- **資料庫 / stateful 服務**：目前無狀態。加 compose 的 db 服務 + migration + 備份策略。
- **健康檢查**：後端有 `/health`，但 Dockerfile / compose 尚未接 `HEALTHCHECK` 去用它（部署到 LB / orchestrator 時需要）。
- **可觀測性**：結構化 log、metrics、tracing。
- **安全掃描**：映像漏洞掃描（Trivy）、Dependabot、SBOM、映像簽章（cosign）。
- **多架構映像**：目前只 build amd64。要跑 arm64（Apple Silicon / AWS Graviton）需 buildx 多平台建置。
