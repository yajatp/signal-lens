from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parent.parent / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    database_url: str = "postgresql+psycopg://localhost/signal_lens"
    opencellid_api_key: str = ""

    # Physics model defaults (documented heuristics — see spec §6)
    tower_eirp_dbm: float = 58.0        # typical macro-cell EIRP assumption
    default_frequency_mhz: float = 1900.0
    path_loss_exponent: float = 2.9     # suburban; ~2 free space, 2.7–3.5 urban
    reference_distance_m: float = 100.0
    building_obstruction_penalty_db: float = 13.5  # flat per-building penalty (spec §6.2)
    user_height_m: float = 1.5
    default_tower_height_m: float = 30.0
    terrain_sample_count: int = 12      # elevation samples along the LOS path


settings = Settings()
