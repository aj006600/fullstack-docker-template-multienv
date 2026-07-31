BASE := -f compose.yaml -f compose.proxy.yaml

.PHONY: dev up-dev up-qas up-prod down-dev down-qas down-prod ps

# ---------- 本機單環境開發（不經 Traefik，直接 localhost:3000）----------
dev:
	APP_ENV=dev docker compose -f compose.yaml -f compose.dev.yaml up --build

# ---------- 部署各環境（經共用 Traefik，可同時並存）----------
# 前置：先在 traefik-proxy repo 跑一次 `make up`（建立 proxy 網路 + 啟動 Traefik）
# 每個環境用不同 COMPOSE_PROJECT_NAME → 各自獨立網路/容器，互不干擾
up-dev:
	COMPOSE_PROJECT_NAME=fullstack-dev  docker compose $(BASE) --env-file env/.env.dev  up -d --build
up-qas:
	COMPOSE_PROJECT_NAME=fullstack-qas  docker compose $(BASE) --env-file env/.env.qas  up -d --build
up-prod:
	COMPOSE_PROJECT_NAME=fullstack-prod docker compose $(BASE) --env-file env/.env.prod up -d --build

down-dev:
	COMPOSE_PROJECT_NAME=fullstack-dev  docker compose $(BASE) --env-file env/.env.dev  down
down-qas:
	COMPOSE_PROJECT_NAME=fullstack-qas  docker compose $(BASE) --env-file env/.env.qas  down
down-prod:
	COMPOSE_PROJECT_NAME=fullstack-prod docker compose $(BASE) --env-file env/.env.prod down

ps:
	docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
