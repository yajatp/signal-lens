"""Prediction engine: ties together tower lookup, path loss, LOS obstruction,
and terrain shadowing into one explainable prediction (spec §6.3).

predicted_dbm = free_space_baseline - obstruction_penalty - terrain_penalty
"""

from dataclasses import dataclass, field

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.config import settings
from app.ingest.terrain import elevation_m
from app.models import Tower
from app.physics import geo, los, path_loss, terrain


@dataclass
class ObstructionDetail:
    osm_id: int
    building_type: str
    height_m: float
    height_source: str
    clearance_m: float


@dataclass
class Prediction:
    lat: float
    lon: float
    tower_id: str | None
    tower_lat: float | None
    tower_lon: float | None
    tower_distance_m: float | None
    baseline_dbm: float | None
    obstruction_count: int
    obstruction_penalty_db: float
    terrain_penalty_db: float
    terrain_max_intrusion_m: float
    predicted_dbm: float | None
    obstructions: list[ObstructionDetail] = field(default_factory=list)
    explanation: str = ""


def nearest_towers(db: Session, lat: float, lon: float, limit: int = 5) -> list[Tower]:
    point = func.ST_SetSRID(func.ST_MakePoint(lon, lat), 4326)
    stmt = (
        select(Tower)
        .order_by(Tower.geom.op("<->")(point))
        .limit(limit)
    )
    return list(db.execute(stmt).scalars())


def predict(db: Session, lat: float, lon: float, height_m: float | None = None) -> Prediction:
    user_height = height_m if height_m is not None else settings.user_height_m
    towers = nearest_towers(db, lat, lon, limit=1)
    if not towers:
        return Prediction(
            lat=lat, lon=lon, tower_id=None, tower_lat=None, tower_lon=None,
            tower_distance_m=None, baseline_dbm=None, obstruction_count=0,
            obstruction_penalty_db=0.0, terrain_penalty_db=0.0,
            terrain_max_intrusion_m=0.0, predicted_dbm=None,
            explanation="No towers ingested for this area yet.",
        )

    tower = towers[0]
    dist = geo.distance_m(lat, lon, tower.lat, tower.lon)
    baseline = path_loss.received_power_dbm(
        dist,
        settings.default_frequency_mhz,
        settings.path_loss_exponent,
        settings.tower_eirp_dbm,
        settings.reference_distance_m,
    )

    user_ground = elevation_m(db, lat, lon)
    tower_ground = elevation_m(db, tower.lat, tower.lon)
    tower_height = settings.default_tower_height_m

    los_result = los.find_obstructions(
        db, lat, lon, tower.lat, tower.lon,
        user_ground, tower_ground, user_height, tower_height,
        ground_elevation_lookup=lambda la, lo: elevation_m(db, la, lo),
    )
    obstruction_penalty = los_result.count * settings.building_obstruction_penalty_db

    profile = terrain.profile_path(
        lambda la, lo: elevation_m(db, la, lo),
        lat, lon, tower.lat, tower.lon,
        user_ground, tower_ground, user_height, tower_height,
        sample_count=settings.terrain_sample_count,
    )

    predicted = path_loss.clamp_rsrp(baseline - obstruction_penalty - profile.penalty_db)

    return Prediction(
        lat=lat, lon=lon,
        tower_id=tower.id, tower_lat=tower.lat, tower_lon=tower.lon,
        tower_distance_m=round(dist, 1),
        baseline_dbm=round(baseline, 1),
        obstruction_count=los_result.count,
        obstruction_penalty_db=round(obstruction_penalty, 1),
        terrain_penalty_db=round(profile.penalty_db, 1),
        terrain_max_intrusion_m=round(profile.max_intrusion_m, 1),
        predicted_dbm=round(predicted, 1),
        obstructions=[
            ObstructionDetail(
                osm_id=o.osm_id, building_type=o.building_type, height_m=o.height_m,
                height_source=o.height_source, clearance_m=round(o.clearance_m, 1),
            )
            for o in los_result.obstructions
        ],
        explanation=_explain(dist, los_result, profile),
    )


def _explain(dist_m: float, los_result: los.LosResult, profile: terrain.TerrainProfile) -> str:
    miles = dist_m / 1609.34
    parts = [f"{miles:.2f} mi from tower"]
    if los_result.count == 0:
        parts.append("clear line of sight through mapped buildings")
    else:
        plural = "building" if los_result.count == 1 else "buildings"
        parts.append(f"blocked by {los_result.count} {plural}")
    if profile.penalty_db > 0:
        parts.append(f"terrain rises {profile.max_intrusion_m:.0f} m into the signal path")
    return ", ".join(parts) + "."
