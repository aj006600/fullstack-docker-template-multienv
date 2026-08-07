# 這個專案的名字。所有「執行期」名稱都從這一行流出去：compose project 名（＝container 與
# network 名）、本機 build 的 image 名、reverse proxy 的 router 名、env 檔的 DOMAIN。
# 注意 README 標題、頁面 title、pyproject description 這些沒有插值能力的地方是寫死的——
# 只改這一行不會動到它們。
APP_NAME := fullstack

DEV := -f compose.yaml -f compose.dev.yaml

# EXPOSE = ports | proxy
# ENV    = dev | qas | prod
# 註解不可寫在同一行：Make 會把 # 之前的空白一起吃進變數值
EXPOSE ?= ports
ENV    ?= dev

STACK   := -f compose.yaml -f deploy/compose.$(EXPOSE).yaml --env-file env/.env.$(ENV)
# APP_NAME 必須進到 compose 的插值環境：compose.yaml 的 image 預設名與 env 檔的
# DOMAIN=<env>.$${APP_NAME}.localhost 都用到它。沒帶進去只會是警告不是錯誤，
# DOMAIN 會靜默變成 "dev..localhost"。
PROJECT := COMPOSE_PROJECT_NAME=$(APP_NAME)-$(ENV) APP_NAME=$(APP_NAME)

# 打錯 EXPOSE/ENV 時給明確訊息，而不是 compose 的 "no such file" 或靜靜載入到別的環境
guard = @test -f deploy/compose.$(EXPOSE).yaml || { echo "EXPOSE=$(EXPOSE) 無效。可用：ports | proxy"; exit 1; }; \
	test -f env/.env.$(ENV) || { echo "ENV=$(ENV) 無效。可用：dev | qas | prod"; exit 1; }

.PHONY: help init dev dev-down test lint format down deploy ps

help:
	@echo "Setup（從 template 開新專案時做一次）"
	@echo "  make init APP_NAME=my-app         把專案改名成你的，並移除這個 target 自己"
	@echo ""
	@echo "Development（在你的開發機上）"
	@echo "  make dev                          hot reload、localhost:3000 / :8000（前景執行）"
	@echo "  make dev-down                     停止並清理 make dev 的 container 與 network"
	@echo "  make test | lint | format         跑在 dev stage 容器裡，與 CI 同一份 uv.lock"
	@echo ""
	@echo "Deployment（在目標主機上）"
	@echo "  make deploy  EXPOSE=… ENV=… IMAGE=… TAG=…   拉 CI 測過的映像，不重 build"
	@echo "  make down    EXPOSE=… ENV=…                 停止該環境"
	@echo ""
	@echo "  EXPOSE = ports | proxy      怎麼對外曝露：綁主機埠 / 掛共用 reverse proxy   (預設 $(EXPOSE))"
	@echo "  ENV    = dev | qas | prod                                                 (預設 $(ENV))"
	@echo ""
	@echo "Inspection"
	@echo "  make ps                           正在跑的 container（名稱 / 狀態 / 埠）"

# >>> init（make init 會刪掉這整段，不要移除這兩行標記）
# ── Project init（一次性）──
# 把 template 的名字換成你的專案名。對 git 追蹤的檔案全跑，不維護檔案清單——
# 之後新增的檔案自動涵蓋，不會靜默漏改。
#
# 兩條規則的順序不能反：先換長的（repo 名），否則 "fullstack-docker-template-multienv"
# 會先被短規則切成 "my-app-docker-template-multienv"。
#
# 不分大小寫（/i）：展示用的標題寫成 "Fullstack Multi-env"（頁面 title、<h1>、
# pyproject description），只比對小寫會漏掉它們。
#
# 用 perl 而非 sed：BSD（macOS）要寫 -i ''、GNU（Linux）要寫 -i，語法不相容；
# perl -pi 兩邊一致，而且兩個平台都內建。
#
# 要求工作區乾淨：這會改動十幾個檔案，保持「反悔就 git checkout .」這條退路。
init:
	@test "$(APP_NAME)" != "fullstack" || { echo "用法：make init APP_NAME=my-app"; exit 1; }
	@echo "$(APP_NAME)" | grep -qE '^[a-z][a-z0-9-]*$$' || { echo "APP_NAME 只能是小寫英數與連字號、開頭為字母——它會用在 image 名、compose project 名與 domain。"; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "工作區有未提交的改動。請先 commit 或 stash——init 會改動多個檔案，乾淨的工作區才能用 git checkout . 還原。"; exit 1; }
	@git ls-files -z | xargs -0 perl -pi -e 's/fullstack-docker-template-multienv/$(APP_NAME)/gi; s/fullstack/$(APP_NAME)/gi'
	@rm -rf CLAUDE.md docs/agents
	@perl -0777 -pi -e 's/^# >>> init.*?^# <<< init.*?\n\n//ms' Makefile
	@perl -0777 -pi -e 's/^\t\@echo "Setup.*?\n\t\@echo ""\n//ms; s/^\.PHONY: help init /.PHONY: help /m' Makefile
	@perl -0777 -pi -e 's/^<!-- init:start -->.*?^<!-- init:end -->\n\n//ms' README.md
	@echo "已更名為 $(APP_NAME)，並移除 init target 與 agent 設定檔。"
	@echo "請 git diff 檢查後 commit。"
# <<< init

# ── Development ──
dev:
	APP_ENV=dev APP_NAME=$(APP_NAME) docker compose $(DEV) up --build

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
	@test -n "$(IMAGE)" && test -n "$(TAG)" || { echo "需要 IMAGE 與 TAG，例：make deploy EXPOSE=proxy ENV=dev IMAGE=ghcr.io/<帳號>/<repo> TAG=<sha>"; exit 1; }
	IMAGE=$(IMAGE) TAG=$(TAG) $(PROJECT) docker compose $(STACK) pull
	IMAGE=$(IMAGE) TAG=$(TAG) $(PROJECT) docker compose $(STACK) up -d --no-build

down:
	$(guard)
	$(PROJECT) docker compose $(STACK) down

ps:
	docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
