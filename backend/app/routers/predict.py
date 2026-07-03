from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db import get_db
from app.physics import engine
from app.schemas import PredictionOut

router = APIRouter(tags=["predict"])


@router.get("/predict", response_model=PredictionOut)
def predict(
    lat: float = Query(ge=-90, le=90),
    lon: float = Query(ge=-180, le=180),
    height_m: float | None = Query(default=None, ge=0, le=500),
    db: Session = Depends(get_db),
):
    """Physics-model signal prediction at a point, with the obstruction breakdown."""
    return engine.predict(db, lat, lon, height_m)
