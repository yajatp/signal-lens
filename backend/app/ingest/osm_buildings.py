"""OSM building footprint ingestion via the Overpass API.

Height resolution order (spec §5 note on inconsistent tag coverage):
  1. explicit `height` tag (meters; ft converted)
  2. `building:levels` * 3.0 m
  3. per-type default
The chosen source is recorded per building (height_source) so the ML layer
can weight estimated heights differently later.
"""

import logging
import re

import httpx
from shapely.geometry import Polygon
from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.models import Building

log = logging.getLogger(__name__)

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
# overpass-api.de rejects default client user agents with 406
HEADERS = {"User-Agent": "SignalLens/0.1 (github.com/yajatp/signal-lens)"}
METERS_PER_LEVEL = 3.0
DEFAULT_HEIGHTS = {
    "house": 5.0, "detached": 5.0, "residential": 6.0, "garage": 3.0,
    "apartments": 12.0, "commercial": 8.0, "retail": 6.0, "office": 10.0,
    "industrial": 9.0, "warehouse": 10.0, "school": 7.0, "church": 15.0,
    "hospital": 15.0, "hotel": 20.0,
}
FALLBACK_HEIGHT = 6.0


def parse_height(tags: dict) -> tuple[float, str]:
    raw = tags.get("height") or tags.get("building:height")
    if raw:
        m = re.match(r"^\s*([\d.]+)\s*(m|ft|')?\s*$", str(raw))
        if m:
            val = float(m.group(1))
            if m.group(2) in ("ft", "'"):
                val *= 0.3048
            return val, "tag"
    levels = tags.get("building:levels")
    if levels:
        try:
            return max(float(levels), 1.0) * METERS_PER_LEVEL, "levels"
        except ValueError:
            pass
    btype = tags.get("building", "yes")
    return DEFAULT_HEIGHTS.get(btype, FALLBACK_HEIGHT), "default"


def fetch_buildings(lat_min: float, lon_min: float, lat_max: float, lon_max: float) -> list[dict]:
    query = f"""
    [out:json][timeout:300][maxsize:536870912];
    way["building"]({lat_min},{lon_min},{lat_max},{lon_max});
    out tags geom;
    """
    with httpx.Client(timeout=360, headers=HEADERS) as client:
        resp = client.post(OVERPASS_URL, data={"data": query})
        resp.raise_for_status()
        return resp.json().get("elements", [])


def upsert_buildings(db: Session, elements: list[dict]) -> int:
    count = 0
    for el in elements:
        geometry = el.get("geometry")
        if not geometry or len(geometry) < 4:
            continue
        coords = [(pt["lon"], pt["lat"]) for pt in geometry]
        poly = Polygon(coords)
        if not poly.is_valid:
            poly = poly.buffer(0)
            if poly.is_empty or poly.geom_type != "Polygon":
                continue
        tags = el.get("tags", {})
        height, source = parse_height(tags)
        stmt = pg_insert(Building).values(
            osm_id=el["id"],
            height_m=height,
            height_source=source,
            building_type=tags.get("building", "yes"),
            geom=func.ST_GeomFromText(poly.wkt, 4326),
        ).on_conflict_do_update(
            index_elements=[Building.osm_id],
            set_={
                "height_m": height,
                "height_source": source,
                "building_type": tags.get("building", "yes"),
                "geom": func.ST_GeomFromText(poly.wkt, 4326),
            },
        )
        db.execute(stmt)
        count += 1
    db.commit()
    return count


def ingest_bbox(db: Session, lat_min: float, lon_min: float, lat_max: float, lon_max: float) -> int:
    elements = fetch_buildings(lat_min, lon_min, lat_max, lon_max)
    log.info("Overpass returned %d building ways", len(elements))
    return upsert_buildings(db, elements)
