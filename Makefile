SEP  := -f compose.yaml -f deploy/compose.separate-hosts.yaml
PORT := -f compose.yaml -f deploy/compose.same-host-by-port.yaml
DOM  := -f compose.yaml -f deploy/compose.same-host-by-domain.yaml
ENV  ?= dev

.PHONY: dev \
	up-separate-hosts down-separate-hosts \
	up-port-dev up-port-qas up-port-prod down-port-dev down-port-qas down-port-prod \
	up-domain-dev up-domain-qas up-domain-prod down-domain-dev down-domain-qas down-domain-prod \
	ps

# ── 本機開發（不經任何 proxy，直接 localhost:3000）──
dev:
	APP_ENV=dev docker compose -f compose.yaml -f compose.dev.yaml up --build

# ── A：separate-hosts（每環境各自一台主機，標準 80 埠）──
# 在該環境的主機上跑，用 ENV 指定環境：make up-separate-hosts ENV=qas
up-separate-hosts:
	docker compose $(SEP) --env-file env/.env.$(ENV) up -d --build
down-separate-hosts:
	docker compose $(SEP) --env-file env/.env.$(ENV) down

# ── B：same-host-by-port（同機、不同 port，三環境並存）──
up-port-dev:
	COMPOSE_PROJECT_NAME=fullstack-dev  docker compose $(PORT) --env-file env/.env.dev  up -d --build
up-port-qas:
	COMPOSE_PROJECT_NAME=fullstack-qas  docker compose $(PORT) --env-file env/.env.qas  up -d --build
up-port-prod:
	COMPOSE_PROJECT_NAME=fullstack-prod docker compose $(PORT) --env-file env/.env.prod up -d --build
down-port-dev:
	COMPOSE_PROJECT_NAME=fullstack-dev  docker compose $(PORT) --env-file env/.env.dev  down
down-port-qas:
	COMPOSE_PROJECT_NAME=fullstack-qas  docker compose $(PORT) --env-file env/.env.qas  down
down-port-prod:
	COMPOSE_PROJECT_NAME=fullstack-prod docker compose $(PORT) --env-file env/.env.prod down

# ── C：same-host-by-domain（同機、Traefik 依 domain，三環境並存）──
# 前置：到 traefik-proxy repo 跑一次 `make up`（啟動共用 Traefik + proxy 網路）
up-domain-dev:
	COMPOSE_PROJECT_NAME=fullstack-dev  docker compose $(DOM) --env-file env/.env.dev  up -d --build
up-domain-qas:
	COMPOSE_PROJECT_NAME=fullstack-qas  docker compose $(DOM) --env-file env/.env.qas  up -d --build
up-domain-prod:
	COMPOSE_PROJECT_NAME=fullstack-prod docker compose $(DOM) --env-file env/.env.prod up -d --build
down-domain-dev:
	COMPOSE_PROJECT_NAME=fullstack-dev  docker compose $(DOM) --env-file env/.env.dev  down
down-domain-qas:
	COMPOSE_PROJECT_NAME=fullstack-qas  docker compose $(DOM) --env-file env/.env.qas  down
down-domain-prod:
	COMPOSE_PROJECT_NAME=fullstack-prod docker compose $(DOM) --env-file env/.env.prod down

ps:
	docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
