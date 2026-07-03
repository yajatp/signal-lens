"""Seed the MVP test region: Allen + McKinney, TX.

Pulls real cell towers from OpenCelliD and real building footprints from OSM
(Overpass) for the bbox covering both cities.

Usage: python -m scripts.seed_allen_mckinney  (from backend/, with .venv active)
Options: --bbox lat_min lon_min lat_max lon_max   to seed a different region
         --skip-towers / --skip-buildings
"""

import argparse

from app.db import SessionLocal
from app.ingest import opencellid, osm_buildings

# Covers Allen (south) through McKinney (north)
ALLEN_MCKINNEY_BBOX = (33.08, -96.75, 33.25, -96.55)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bbox", nargs=4, type=float, metavar=("LAT_MIN", "LON_MIN", "LAT_MAX", "LON_MAX"))
    parser.add_argument("--skip-towers", action="store_true")
    parser.add_argument("--skip-buildings", action="store_true")
    args = parser.parse_args()
    bbox = tuple(args.bbox) if args.bbox else ALLEN_MCKINNEY_BBOX

    db = SessionLocal()
    try:
        if not args.skip_towers:
            print(f"Ingesting OpenCelliD towers for bbox {bbox} (tiled requests)...")
            n = opencellid.ingest_bbox(db, *bbox)
            print(f"  -> {n} tower cells upserted")
        if not args.skip_buildings:
            print(f"Ingesting OSM building footprints for bbox {bbox} (Overpass)...")
            n = osm_buildings.ingest_bbox(db, *bbox)
            print(f"  -> {n} buildings upserted")
    finally:
        db.close()
    print("Seed complete.")


if __name__ == "__main__":
    main()
