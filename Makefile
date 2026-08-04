SEP  := -f compose.yaml -f deploy/compose.separate-hosts.yaml
PORT := -f compose.yaml -f deploy/compose.same-host-by-port.yaml
DOM  := -f compose.yaml -f deploy/compose.same-host-by-domain.yaml
ENV  ?= dev
MODE ?= separate-hosts

.PHONY: dev dev-down deploy \
	up-separate-hosts down-separate-hosts \
	up-port-dev up-port-qas up-port-prod down-port-dev down-port-qas down-port-prod \
	up-domain-dev up-domain-qas up-domain-prod down-domain-dev down-domain-qas down-domain-prod \
	ps

# ── 本機開發（不經任何 proxy，直接 localhost:3000）──
dev:
	APP_ENV=dev docker compose -f compose.yaml -f compose.dev.yaml up --build
# 停止並清理本機開發的容器與網路（Ctrl+C 只停不移除，這個會移除）
dev-down:
	docker compose -f compose.yaml -f compose.dev.yaml down

# ══ Deployment topology（A/B/C 擇一）：deploy/compose.*.yaml 定義各環境「怎麼對外曝露」══
#    up-* 一律 build 本機 code = preview，不是 deployment；真部署用下方 make deploy（拉 CI 測過的 image）。
#    B/C 可在本機同時起三環境預覽各 env 設定；A 的多機 topology 無法單機模擬（本機一次只能預覽一個）。

# ── A：separate-hosts（每環境各自一台主機，標準 80 埠）──
# 預覽單一環境（都綁 80，一次一個）：make up-separate-hosts ENV=qas
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

# ── Deploy（在目標主機上跑）：拉 CI 測過的不可變 image，不重 build。CI 與人工共用同一條 ──
# 用法：make deploy MODE=<separate-hosts|same-host-by-port|same-host-by-domain> ENV=<dev|qas|prod> \
#              IMAGE=ghcr.io/<帳號>/<repo> TAG=<git-sha 或 vX.Y.Z>
# 回溯（rollback）：同一行指令、TAG 換成舊 sha 即可
deploy:
	@test -n "$(IMAGE)" && test -n "$(TAG)" || { echo "需要 IMAGE 與 TAG，例：make deploy MODE=same-host-by-domain ENV=dev IMAGE=ghcr.io/<帳號>/<repo> TAG=<sha>"; exit 1; }
	IMAGE=$(IMAGE) TAG=$(TAG) COMPOSE_PROJECT_NAME=fullstack-$(ENV) docker compose -f compose.yaml -f deploy/compose.$(MODE).yaml --env-file env/.env.$(ENV) pull
	IMAGE=$(IMAGE) TAG=$(TAG) COMPOSE_PROJECT_NAME=fullstack-$(ENV) docker compose -f compose.yaml -f deploy/compose.$(MODE).yaml --env-file env/.env.$(ENV) up -d --no-build

ps:
	docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
