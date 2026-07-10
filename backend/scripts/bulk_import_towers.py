"""Bulk CSV import from OpenCelliD — dramatically denser tower coverage.

The REST API (getInArea) caps at 50 results per tile, which is why Allen shows
only 48 towers all 9+ miles away. The bulk CSV download for US MCCs (310, 311)
contains *every* known cell, including ones the tile-based API truncates.

Usage:
    .venv/bin/python -m scripts.bulk_import_towers

Downloads MCC 310 and 311 CSVs, filters to the DFW metro area (or a custom
bbox), and upserts into the towers table. Rate limit: 2 downloads/day per
OpenCelliD account, so the CSVs are cached locally.
"""

import csv
import gzip
import io
import logging
import sys
from datetime import datetime, timezone
from pathlib import Path

import httpx
from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.config import settings
from app.db import SessionLocal
from app.models import Tower

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger(__name__)

DOWNLOAD_URL = "https://opencellid.org/ocid/downloads"
CACHE_DIR = Path(__file__).resolve().parent.parent / "data" / "cache"

# DFW metro — broad enough to catch all towers that could serve Allen/McKinney.
# Allen is at ~33.10, -96.67. This bbox covers roughly DFW metro + suburbs.
DEFAULT_BBOX = {
    "lat_min": 32.5,
    "lat_max": 33.5,
    "lon_min": -97.5,
    "lon_max": -96.2,
}

# US carrier MCCs
US_MCCS = [310, 311]


def download_mcc_csv(mcc: int) -> Path:
    """Download the gzipped CSV for an MCC, caching to disk."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = CACHE_DIR / f"{mcc}.csv.gz"

    if cache_path.exists():
        age_hours = (datetime.now().timestamp() - cache_path.stat().st_mtime) / 3600
        if age_hours < 24:
            log.info("Using cached %s (%.1f hours old)", cache_path.name, age_hours)
            return cache_path
        log.info("Cache expired for %s (%.1f hours), re-downloading", cache_path.name, age_hours)

    if not settings.opencellid_api_key:
        log.error("OPENCELLID_API_KEY not set in backend/.env")
        sys.exit(1)

    log.info("Downloading MCC %d from OpenCelliD (this may take a minute)...", mcc)
    with httpx.Client(timeout=120, follow_redirects=True) as client:
        resp = client.get(DOWNLOAD_URL, params={
            "token": settings.opencellid_api_key,
            "type": "mcc",
            "file": f"{mcc}.csv.gz",
        })
        if resp.status_code == 403:
            log.error("OpenCelliD returned 403 — daily download limit (2/day) may be hit, or token invalid.")
            sys.exit(1)
        resp.raise_for_status()
        cache_path.write_bytes(resp.content)
        log.info("Downloaded %s (%.1f MB)", cache_path.name, len(resp.content) / 1e6)

    return cache_path


def parse_csv(path: Path) -> list[dict]:
    """Parse the gzipped CSV."""
    cells = []
    # OpenCelliD bulk CSVs don't have a header row. The format is:
    # radio, mcc, net, area, cell, unit, lon, lat, range, samples, changeable, created, updated, averageSignal
    fieldnames = [
        "radio", "mcc", "net", "area", "cell", "unit", "lon", "lat", 
        "range", "samples", "changeable", "created", "updated", "averageSignal"
    ]
    with gzip.open(path, "rt", encoding="utf-8") as f:
        reader = csv.DictReader(f, fieldnames=fieldnames)
        for row in reader:
            try:
                _ = float(row["lat"])
                _ = float(row["lon"])
            except (KeyError, ValueError):
                continue
            cells.append(row)
    return cells


def upsert_cells(cells: list[dict]) -> int:
    """Upsert parsed CSV rows into the towers table."""
    db = SessionLocal()
    count = 0
    try:
        def chunker(seq, size):
            return (seq[pos:pos + size] for pos in range(0, len(seq), size))
            
        for chunk in chunker(cells, 2000):
            values = []
            for c in chunk:
                try:
                    radio = c.get("radio", "unknown")
                    mcc = int(c["mcc"])
                    mnc = int(c.get("net") or c.get("mnc", 0))
                    lac = int(c.get("area") or c.get("lac", 0))
                    cell_id = int(c.get("cell") or c.get("cellid", 0))
                    lat = float(c["lat"])
                    lon = float(c["lon"])
                    range_m = float(c.get("range") or 0)
                    samples = int(c.get("samples") or 0)
                except (KeyError, ValueError, TypeError):
                    continue

                tower_id = f"{mcc}-{mnc}-{lac}-{cell_id}"
                values.append({
                    "id": tower_id,
                    "radio": radio,
                    "mcc": mcc, "mnc": mnc, "lac": lac, "cell_id": cell_id,
                    "lat": lat, "lon": lon,
                    "range_m": range_m,
                    "samples": samples,
                    "updated_at": datetime.now(timezone.utc),
                    "geom": func.ST_SetSRID(func.ST_MakePoint(lon, lat), 4326),
                })
            
            if not values:
                continue
                
            stmt = pg_insert(Tower).values(values)
            stmt = stmt.on_conflict_do_update(
                index_elements=[Tower.id],
                set_={
                    "radio": stmt.excluded.radio,
                    "lat": stmt.excluded.lat,
                    "lon": stmt.excluded.lon,
                    "range_m": stmt.excluded.range_m,
                    "samples": stmt.excluded.samples,
                    "updated_at": stmt.excluded.updated_at,
                    "geom": stmt.excluded.geom,
                },
            )
            db.execute(stmt)
            db.commit()
            count += len(values)
            log.info("  upserted %d cells...", count)

    finally:
        db.close()
    return count


def main():
    log.info("Bulk tower import — importing entire MCC datasets")

    total = 0
    for mcc in US_MCCS:
        path = download_mcc_csv(mcc)
        cells = parse_csv(path)
        log.info("MCC %d: %d cells found", mcc, len(cells))
        if cells:
            n = upsert_cells(cells)
            total += n
            log.info("MCC %d: upserted %d towers", mcc, n)

    # Report
    db = SessionLocal()
    try:
        tower_count = db.execute(func.count(Tower.id)).scalar()
        log.info("Done — %d towers upserted this run, %d total in database", total, tower_count)
    finally:
        db.close()


if __name__ == "__main__":
    main()
