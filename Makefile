DEV := -f compose.yaml -f compose.dev.yaml

# MODE = separate-hosts | same-host-by-port | same-host-by-domain
# ENV  = dev | qas | prod
# 註解不可寫在同一行：Make 會把 # 之前的空白一起吃進變數值
MODE ?= same-host-by-port
ENV  ?= dev

STACK   := -f compose.yaml -f deploy/compose.$(MODE).yaml --env-file env/.env.$(ENV)
PROJECT := COMPOSE_PROJECT_NAME=fullstack-$(ENV)

# 打錯 MODE/ENV 時給明確訊息，而不是 compose 的 "no such file" 或靜靜載入到別的環境
guard = @test -f deploy/compose.$(MODE).yaml || { echo "MODE=$(MODE) 無效。可用：separate-hosts | same-host-by-port | same-host-by-domain"; exit 1; }; \
	test -f env/.env.$(ENV) || { echo "ENV=$(ENV) 無效。可用：dev | qas | prod"; exit 1; }

.PHONY: help dev dev-down test lint format up down deploy ps

help:
	@echo "Development"
	@echo "  make dev                          本機開發：hot reload、localhost:3000 / :8000（前景執行）"
	@echo "  make dev-down                     停止並清理 make dev 的 container 與 network"
	@echo "  make test | lint | format         跑在 dev stage 容器裡，與 CI 同一份 uv.lock"
	@echo ""
	@echo "Deployment（兩者都是部署，差別只在 image 從哪來）"
	@echo "  make up      MODE=… ENV=…                 用本機當前 code 現場 build"
	@echo "  make deploy  MODE=… ENV=… IMAGE=… TAG=…   拉 CI 測過的映像，不重 build"
	@echo "  make down    MODE=… ENV=…                 停止該環境（up 與 deploy 共用）"
	@echo ""
	@echo "  MODE = separate-hosts | same-host-by-port | same-host-by-domain   (預設 $(MODE))"
	@echo "  ENV  = dev | qas | prod                                          (預設 $(ENV))"
	@echo ""
	@echo "Inspection"
	@echo "  make ps                           正在跑的 container（名稱 / 狀態 / 埠）"

# ── Development ──
dev:
	APP_ENV=dev docker compose $(DEV) up --build

dev-down:
	docker compose $(DEV) down

# ── Tests and quality（dev stage 容器，與 CI 同一份 uv.lock）──
# --build 必要：pyproject.toml / uv.lock 烤在 image 裡（掛載只蓋 app/ 與 tests/），
# 不重建會用到舊設定；無變更時 layer cache 幾乎零成本。
test:
	docker compose $(DEV) run --build --rm backend pytest

lint:
	docker compose $(DEV) run --build --rm backend ruff check .

format:
	docker compose $(DEV) run --build --rm backend ruff format .

# ── Deployment ──
# up 與 deploy 都是部署，差別只在 image 來源：up 用本機當前 code 現場 build，
# deploy 拉 CI 測過的不可變映像（在目標主機重 build 會破壞 build-once 的保證）。
# 兩者用同一組 project 名，所以同一個 down 都收得掉。詳見 docs/deployment.md。
up:
	$(guard)
	$(PROJECT) docker compose $(STACK) up -d --build

down:
	$(guard)
	$(PROJECT) docker compose $(STACK) down

# rollback = TAG 換回舊的 sha
deploy:
	$(guard)
	@test -n "$(IMAGE)" && test -n "$(TAG)" || { echo "需要 IMAGE 與 TAG，例：make deploy MODE=same-host-by-domain ENV=dev IMAGE=ghcr.io/<帳號>/<repo> TAG=<sha>"; exit 1; }
	IMAGE=$(IMAGE) TAG=$(TAG) $(PROJECT) docker compose $(STACK) pull
	IMAGE=$(IMAGE) TAG=$(TAG) $(PROJECT) docker compose $(STACK) up -d --no-build

ps:
	docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
