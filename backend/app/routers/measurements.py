from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Measurement
from app.physics import engine
from app.schemas import MeasurementIn, MeasurementOut

router = APIRouter(tags=["measurements"])


@router.post("/measurements", response_model=MeasurementOut)
def create_measurement(body: MeasurementIn, db: Session = Depends(get_db)):
    """Log a measurement. The server runs the physics prediction at ingest time so
    every row carries prediction + inputs + actuals — the ML training schema."""
    pred = engine.predict(db, body.lat, body.lon, body.device_height_estimate)
    m = Measurement(
        lat=body.lat,
        lon=body.lon,
        device_height_estimate=body.device_height_estimate,
        tower_id=pred.tower_id,
        tower_distance_m=pred.tower_distance_m,
        obstruction_count=pred.obstruction_count,
        obstruction_total_height_penalty=pred.obstruction_penalty_db,
        terrain_penalty=pred.terrain_penalty_db,
        predicted_dbm=pred.predicted_dbm,
        actual_proxy_signal=body.actual_proxy_signal,
        actual_field_test_dbm=body.actual_field_test_dbm,
        source=body.source,
    )
    db.add(m)
    db.commit()
    db.refresh(m)
    return m


@router.get("/measurements", response_model=list[MeasurementOut])
def list_measurements(
    limit: int = Query(default=100, ge=1, le=1000),
    source: str | None = None,
    db: Session = Depends(get_db),
):
    stmt = select(Measurement).order_by(Measurement.timestamp.desc()).limit(limit)
    if source:
        stmt = stmt.where(Measurement.source == source)
    return list(db.execute(stmt).scalars())
