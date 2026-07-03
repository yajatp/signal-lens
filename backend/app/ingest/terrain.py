"""USGS 3DEP elevation lookups (EPQS point API) with a DB-backed cache.

Lookups snap to a ~10 m grid (4 decimal places) so repeated predictions in the
same area never re-hit the USGS API.
"""

import logging

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import TerrainPoint

log = logging.getLogger(__name__)

EPQS_URL = "https://epqs.nationalmap.gov/v1/json"


def _grid_key(lat: float, lon: float) -> tuple[str, float, float]:
    glat, glon = round(lat, 4), round(lon, 4)
    return f"{glat}:{glon}", glat, glon


def _fetch_epqs(lat: float, lon: float) -> float:
    try:
        resp = httpx.get(
            EPQS_URL,
            params={"x": lon, "y": lat, "units": "Meters", "wkid": 4326, "includeDate": "false"},
            timeout=15,
        )
        resp.raise_for_status()
        value = resp.json().get("value")
        if value is None:
            return 0.0
        elev = float(value)
        # EPQS uses large negative sentinels for no-data (ocean, out of coverage)
        return elev if elev > -1000 else 0.0
    except Exception as e:
        log.warning("EPQS lookup failed for (%s, %s): %s — using 0 m", lat, lon, e)
        return 0.0


def elevation_m(db: Session, lat: float, lon: float) -> float:
    key, glat, glon = _grid_key(lat, lon)
    cached = db.execute(
        select(TerrainPoint).where(TerrainPoint.grid_key == key)
    ).scalar_one_or_none()
    if cached is not None:
        return cached.elevation_m
    elev = _fetch_epqs(glat, glon)
    db.add(TerrainPoint(grid_key=key, lat=glat, lon=glon, elevation_m=elev))
    try:
        db.commit()
    except Exception:  # concurrent insert of the same grid cell
        db.rollback()
    return elev
