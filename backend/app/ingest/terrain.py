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


def elevations_m(db: Session, points: list[tuple[float, float]]) -> dict[str, float]:
    """Bulk lookup keyed by grid key. Cache misses are fetched from EPQS
    concurrently — the API takes ~5 s per call, so sequential lookups along a
    path are unusably slow."""
    from concurrent.futures import ThreadPoolExecutor

    keyed = {_grid_key(lat, lon)[0]: _grid_key(lat, lon)[1:] for lat, lon in points}
    cached = {
        tp.grid_key: tp.elevation_m
        for tp in db.execute(
            select(TerrainPoint).where(TerrainPoint.grid_key.in_(keyed))
        ).scalars()
    }
    missing = [k for k in keyed if k not in cached]
    if missing:
        with ThreadPoolExecutor(max_workers=8) as pool:
            fetched = list(pool.map(lambda k: _fetch_epqs(*keyed[k]), missing))
        for key, elev in zip(missing, fetched):
            glat, glon = keyed[key]
            db.add(TerrainPoint(grid_key=key, lat=glat, lon=glon, elevation_m=elev))
            cached[key] = elev
        try:
            db.commit()
        except Exception:
            db.rollback()
    return cached


def grid_key(lat: float, lon: float) -> str:
    return _grid_key(lat, lon)[0]


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
