import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    PROJECT_NAME: str = "Territory Run API"
    VERSION: str = "1.0.0"
    API_V1_STR: str = "/api"

    # Security
    JWT_SECRET: str = os.getenv("JWT_SECRET", "territory_run_dev_super_secret_key_2026")
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days

    # Database
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://territory_user:territory_password@localhost:5432/territory_run"
    )
    REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379/0")

    # Game Parameters (DECISIONS.md)
    H3_RESOLUTION: int = int(os.getenv("H3_RESOLUTION", "9"))
    RECENCY_HALF_LIFE_DAYS: float = float(os.getenv("RECENCY_HALF_LIFE_DAYS", "14.0"))
    HYSTERESIS_FACTOR: float = float(os.getenv("HYSTERESIS_FACTOR", "1.15"))
    MAX_SPEED_KMH: float = float(os.getenv("MAX_SPEED_KMH", "25.0"))

    model_config = {
        "env_file": ".env",
        "case_sensitive": True,
    }


settings = Settings()
