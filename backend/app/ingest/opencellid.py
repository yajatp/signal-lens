"""OpenCelliD tower ingestion.

The getInArea endpoint caps results per request, so a bbox is tiled into a
grid and each tile fetched separately, then upserted by composite cell id.
"""

import logging
from datetime import datetime, timezone

import httpx
from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.config import settings
from app.models import Tower

log = logging.getLogger(__name__)

API_URL = "https://opencellid.org/cell/getInArea"
PER_REQUEST_LIMIT = 50
TILE_DEG = 0.02  # ~2.2 km tiles keep each request under the result cap


def fetch_tile(client: httpx.Client, lat_min, lon_min, lat_max, lon_max) -> list[dict]:
    resp = client.get(API_URL, params={
        "key": settings.opencellid_api_key,
        "BBOX": f"{lat_min},{lon_min},{lat_max},{lon_max}",
        "format": "json",
        "limit": PER_REQUEST_LIMIT,
    })
    resp.raise_for_status()
    data = resp.json()
    if isinstance(data, dict) and data.get("error"):
        raise RuntimeError(f"OpenCelliD error: {data['error']}")
    return data.get("cells", []) if isinstance(data, dict) else []


def upsert_cells(db: Session, cells: list[dict]) -> int:
    count = 0
    for c in cells:
        try:
            cell_id = f"{c['mcc']}-{c['mnc']}-{c['lac']}-{c['cellid']}"
            lat, lon = float(c["lat"]), float(c["lon"])
        except (KeyError, TypeError, ValueError):
            continue
        stmt = pg_insert(Tower).values(
            id=cell_id,
            radio=str(c.get("radio", "unknown")),
            mcc=int(c["mcc"]), mnc=int(c["mnc"]),
            lac=int(c["lac"]), cell_id=int(c["cellid"]),
            lat=lat, lon=lon,
            range_m=float(c.get("range") or 0),
            samples=int(c.get("samples") or 0),
            updated_at=datetime.now(timezone.utc),
            geom=func.ST_SetSRID(func.ST_MakePoint(lon, lat), 4326),
        ).on_conflict_do_update(
            index_elements=[Tower.id],
            set_={
                "lat": lat, "lon": lon,
                "range_m": float(c.get("range") or 0),
                "samples": int(c.get("samples") or 0),
                "updated_at": datetime.now(timezone.utc),
                "geom": func.ST_SetSRID(func.ST_MakePoint(lon, lat), 4326),
            },
        )
        db.execute(stmt)
        count += 1
    db.commit()
    return count


def ingest_bbox(db: Session, lat_min: float, lon_min: float, lat_max: float, lon_max: float) -> int:
    """Tile the bbox and ingest every tile. Returns number of cells upserted."""
    if not settings.opencellid_api_key:
        raise RuntimeError("OPENCELLID_API_KEY is not set (backend/.env)")
    total = 0
    with httpx.Client(timeout=30) as client:
        lat = lat_min
        while lat < lat_max:
            lon = lon_min
            while lon < lon_max:
                tile = (lat, lon, min(lat + TILE_DEG, lat_max), min(lon + TILE_DEG, lon_max))
                try:
                    cells = fetch_tile(client, *tile)
                    total += upsert_cells(db, cells)
                except Exception as e:  # keep going; a failed tile shouldn't kill the run
                    log.warning("tile %s failed: %s", tile, e)
                lon += TILE_DEG
            lat += TILE_DEG
    return total
