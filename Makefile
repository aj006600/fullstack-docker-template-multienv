.PHONY: dev qas prod down

# 本機開發：後端熱重載 + 掛載原始碼
dev:
	APP_ENV=dev docker compose -f compose.yaml -f compose.dev.yaml up --build

# 以 qas / prod 設定在本機跑（模擬該環境）
qas:
	APP_ENV=qas docker compose up --build -d

prod:
	APP_ENV=prod docker compose up --build -d

down:
	docker compose down
