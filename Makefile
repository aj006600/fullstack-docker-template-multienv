SEP  := -f compose.yaml -f deploy/compose.separate-hosts.yaml
PORT := -f compose.yaml -f deploy/compose.same-host-by-port.yaml
DOM  := -f compose.yaml -f deploy/compose.same-host-by-domain.yaml
DEV  := -f compose.yaml -f compose.dev.yaml
ENV  ?= dev
MODE ?= separate-hosts

.PHONY: dev dev-down test lint format deploy \
	up-separate-hosts down-separate-hosts \
	up-port-dev up-port-qas up-port-prod down-port-dev down-port-qas down-port-prod \
	up-domain-dev up-domain-qas up-domain-prod down-domain-dev down-domain-qas down-domain-prod \
	ps

# ── 本機開發 ──
dev:
	APP_ENV=dev docker compose $(DEV) up --build
dev-down:
	docker compose $(DEV) down

# ── 測試與品質（dev stage 容器，與 CI 同一份 uv.lock）──
# --build 必要：pyproject.toml / uv.lock 烤在 image 裡（掛載只蓋 app/ 與 tests/），
# 不重建會用到舊設定；無變更時 layer cache 幾乎零成本。
test:
	docker compose $(DEV) run --build --rm backend pytest
lint:
	docker compose $(DEV) run --build --rm backend ruff check .
format:
	docker compose $(DEV) run --build --rm backend ruff format .

# ── Preview（up-*）：build 本機 code 預覽環境設定與 topology，不是部署——見 docs/concepts.md ──

# A：separate-hosts——單機一次只能預覽一個環境（都綁 80）：make up-separate-hosts ENV=qas
up-separate-hosts:
	docker compose $(SEP) --env-file env/.env.$(ENV) up -d --build
down-separate-hosts:
	docker compose $(SEP) --env-file env/.env.$(ENV) down

# B：same-host-by-port——三環境可並存
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

# C：same-host-by-domain——前置：先在 traefik-proxy repo 跑一次 `make up`（共用 Traefik + proxy 網路）
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

# ── Deploy（目標主機上執行）：拉 CI 測過的不可變 image，不重 build。rollback = TAG 換舊 sha ──
deploy:
	@test -n "$(IMAGE)" && test -n "$(TAG)" || { echo "需要 IMAGE 與 TAG，例：make deploy MODE=same-host-by-domain ENV=dev IMAGE=ghcr.io/<帳號>/<repo> TAG=<sha>"; exit 1; }
	IMAGE=$(IMAGE) TAG=$(TAG) COMPOSE_PROJECT_NAME=fullstack-$(ENV) docker compose -f compose.yaml -f deploy/compose.$(MODE).yaml --env-file env/.env.$(ENV) pull
	IMAGE=$(IMAGE) TAG=$(TAG) COMPOSE_PROJECT_NAME=fullstack-$(ENV) docker compose -f compose.yaml -f deploy/compose.$(MODE).yaml --env-file env/.env.$(ENV) up -d --no-build

ps:
	docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
