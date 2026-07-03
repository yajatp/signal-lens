from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db import get_db
from app.physics.engine import nearest_towers
from app.schemas import TowerOut

router = APIRouter(tags=["towers"])


@router.get("/towers", response_model=list[TowerOut])
def towers_near(
    lat: float = Query(ge=-90, le=90),
    lon: float = Query(ge=-180, le=180),
    limit: int = Query(default=25, ge=1, le=200),
    db: Session = Depends(get_db),
):
    """Nearest known towers to a point (for the map view)."""
    return nearest_towers(db, lat, lon, limit)
