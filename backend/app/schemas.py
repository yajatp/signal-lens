import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class ObstructionOut(BaseModel):
    osm_id: int
    building_type: str
    height_m: float
    height_source: str
    clearance_m: float


class PredictionOut(BaseModel):
    lat: float
    lon: float
    tower_id: str | None
    tower_lat: float | None
    tower_lon: float | None
    tower_distance_m: float | None
    baseline_dbm: float | None
    obstruction_count: int
    obstruction_penalty_db: float
    terrain_penalty_db: float
    terrain_max_intrusion_m: float
    predicted_dbm: float | None
    obstructions: list[ObstructionOut]
    explanation: str


class TowerOut(BaseModel):
    id: str
    radio: str
    mcc: int
    mnc: int
    lat: float
    lon: float
    range_m: float
    samples: int

    model_config = {"from_attributes": True}


class MeasurementIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    device_height_estimate: float = 1.5
    actual_proxy_signal: float | None = None   # throughput/latency-derived score
    actual_field_test_dbm: float | None = None  # manual Field Test Mode entry
    source: str = Field(pattern="^(walk_test|calibration|passive)$")


class MeasurementOut(BaseModel):
    id: uuid.UUID
    timestamp: datetime
    lat: float
    lon: float
    tower_id: str | None
    tower_distance_m: float | None
    obstruction_count: int | None
    terrain_penalty: float | None
    predicted_dbm: float | None
    actual_proxy_signal: float | None
    actual_field_test_dbm: float | None
    source: str

    model_config = {"from_attributes": True}


class IngestRequest(BaseModel):
    lat_min: float
    lon_min: float
    lat_max: float
    lon_max: float
