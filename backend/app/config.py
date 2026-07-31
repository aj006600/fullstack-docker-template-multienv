from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # 從環境變數讀設定（compose 由 env/.env.<APP_ENV> 注入）
    model_config = SettingsConfigDict(extra="ignore")

    app_env: str = "dev"
    log_level: str = "info"


settings = Settings()
