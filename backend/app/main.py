from fastapi import FastAPI

from app.config import settings

app = FastAPI(title="fullstack-docker-template-multienv backend", version="0.1.0")


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.get("/api/message")
def message():
    # 回傳目前環境，證明設定隨環境切換（前端會顯示）
    return {"message": "Hello from the backend", "env": settings.app_env}
