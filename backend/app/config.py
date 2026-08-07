from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_env: str = "dev"
    log_level: str = "info"


settings = Settings()
