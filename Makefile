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

.PHONY: help dev dev-down test lint format down deploy ps

help:
	@echo "Development（在你的開發機上）"
	@echo "  make dev                          hot reload、localhost:3000 / :8000（前景執行）"
	@echo "  make dev-down                     停止並清理 make dev 的 container 與 network"
	@echo "  make test | lint | format         跑在 dev stage 容器裡，與 CI 同一份 uv.lock"
	@echo ""
	@echo "Deployment（在目標主機上）"
	@echo "  make deploy  MODE=… ENV=… IMAGE=… TAG=…   拉 CI 測過的映像，不重 build"
	@echo "  make down    MODE=… ENV=…                 停止該環境"
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
#
# --user：dev stage 以 root 執行，而 ruff format 會寫回掛載的 app/ 與 tests/。
# 在 Linux 上那些檔案會變成 root 所有，之後編輯不了（macOS 的 Docker Desktop 會轉譯所有權，看不出問題）。
# 快取改寫到 /tmp：映像裡的 /app 由 root 擁有，換成你的 uid 之後寫不進 .ruff_cache / .pytest_cache。
RUNDEV = docker compose $(DEV) run --build --rm \
	--user $(shell id -u):$(shell id -g) \
	-e RUFF_CACHE_DIR=/tmp/.ruff_cache \
	-e PYTEST_ADDOPTS="-p no:cacheprovider" \
	backend

test:
	$(RUNDEV) pytest

lint:
	$(RUNDEV) ruff check .

format:
	$(RUNDEV) ruff format .

# ── Deployment ──
# 部署只有一條路：在目標主機上拉 CI 測過的不可變映像。刻意不提供「本機 build 後部署」
# 的 target——在主機上重 build 會拉到不同的 base layer 或相依，破壞「測過的就是上線的」。
# 臨時要在開發機上跑某個 environment，見 docs/deployment.md 的手動指令。
# rollback = TAG 換回舊的 sha
deploy:
	$(guard)
	@test -n "$(IMAGE)" && test -n "$(TAG)" || { echo "需要 IMAGE 與 TAG，例：make deploy MODE=same-host-by-domain ENV=dev IMAGE=ghcr.io/<帳號>/<repo> TAG=<sha>"; exit 1; }
	IMAGE=$(IMAGE) TAG=$(TAG) $(PROJECT) docker compose $(STACK) pull
	IMAGE=$(IMAGE) TAG=$(TAG) $(PROJECT) docker compose $(STACK) up -d --no-build

down:
	$(guard)
	$(PROJECT) docker compose $(STACK) down

ps:
	docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
