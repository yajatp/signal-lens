import uuid
from datetime import datetime, timezone

from geoalchemy2 import Geometry
from sqlalchemy import Float, Index, Integer, String, DateTime, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Tower(Base):
    """Cell tower from OpenCelliD. Radio cell granularity — one row per cell."""

    __tablename__ = "towers"

    id: Mapped[str] = mapped_column(String, primary_key=True)  # "{mcc}-{mnc}-{lac}-{cellid}"
    radio: Mapped[str] = mapped_column(String)                 # LTE / NR / UMTS / GSM
    mcc: Mapped[int] = mapped_column(Integer)
    mnc: Mapped[int] = mapped_column(Integer)
    lac: Mapped[int] = mapped_column(Integer)
    cell_id: Mapped[int] = mapped_column(Integer)
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)
    range_m: Mapped[float] = mapped_column(Float, default=0.0)
    samples: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    geom = mapped_column(Geometry("POINT", srid=4326))

    __table_args__ = (Index("ix_towers_geom", "geom", postgresql_using="gist"),)


class Building(Base):
    """Building footprint from OSM (Overpass). Height may be estimated — see height_source."""

    __tablename__ = "buildings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    osm_id: Mapped[int] = mapped_column(Integer, unique=True)
    height_m: Mapped[float] = mapped_column(Float)
    height_source: Mapped[str] = mapped_column(String)  # 'tag' | 'levels' | 'default'
    building_type: Mapped[str] = mapped_column(String, default="yes")
    geom = mapped_column(Geometry("POLYGON", srid=4326))

    __table_args__ = (Index("ix_buildings_geom", "geom", postgresql_using="gist"),)


class TerrainPoint(Base):
    """Cache of USGS 3DEP EPQS elevation lookups, snapped to a ~10 m grid."""

    __tablename__ = "terrain_points"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    grid_key: Mapped[str] = mapped_column(String, unique=True)  # "round(lat,4):round(lon,4)"
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)
    elevation_m: Mapped[float] = mapped_column(Float)


class Measurement(Base):
    """Every prediction logged with its physics inputs — the ML training schema (spec §7)."""

    __tablename__ = "measurements"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)
    device_height_estimate: Mapped[float] = mapped_column(Float, default=1.5)
    tower_id: Mapped[str | None] = mapped_column(String, nullable=True)
    tower_distance_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    obstruction_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    obstruction_total_height_penalty: Mapped[float | None] = mapped_column(Float, nullable=True)
    terrain_penalty: Mapped[float | None] = mapped_column(Float, nullable=True)
    predicted_dbm: Mapped[float | None] = mapped_column(Float, nullable=True)
    actual_proxy_signal: Mapped[float | None] = mapped_column(Float, nullable=True)
    actual_field_test_dbm: Mapped[float | None] = mapped_column(Float, nullable=True)
    source: Mapped[str] = mapped_column(String)  # 'walk_test' | 'calibration' | 'passive'
