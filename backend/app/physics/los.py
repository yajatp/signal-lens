"""Line-of-sight obstruction check (spec §6.2).

Candidate buildings come from a PostGIS spatial query (2D line ∩ footprint);
the height-of-line-at-crossing math runs here in a local UTM projection so it
is unit-testable with synthetic geometry, independent of the database.
"""

from dataclasses import dataclass

from shapely import wkb
from shapely.geometry import LineString, Polygon
from shapely.ops import transform as shp_transform
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Building
from app.physics import geo


@dataclass
class Obstruction:
    osm_id: int
    building_type: str
    height_m: float
    height_source: str
    line_height_at_crossing_m: float
    crossing_fraction: float  # 0 = at user, 1 = at tower
    clearance_m: float        # negative → building pierces the LOS line


@dataclass
class LosResult:
    obstructions: list[Obstruction]
    checked_buildings: int

    @property
    def count(self) -> int:
        return len(self.obstructions)


def line_height_at(
    fraction: float, user_ground_m: float, user_height_m: float,
    tower_ground_m: float, tower_height_m: float,
) -> float:
    """Elevation (ASL) of the straight LOS segment at a fraction along the path."""
    start = user_ground_m + user_height_m
    end = tower_ground_m + tower_height_m
    return start + (end - start) * fraction


def check_building_obstruction(
    footprint_utm: Polygon,
    height_m: float,
    ground_elevation_m: float,
    path_utm: LineString,
    user_ground_m: float,
    user_height_m: float,
    tower_ground_m: float,
    tower_height_m: float,
) -> tuple[bool, float, float]:
    """Return (obstructs, crossing_fraction, clearance_m) for one footprint.

    The crossing point is the midpoint of the segment of the path inside the
    footprint. A building obstructs when its roof (ground + height) exceeds the
    LOS line elevation there.
    """
    crossing = path_utm.intersection(footprint_utm)
    if crossing.is_empty:
        return False, 0.0, float("inf")
    mid = crossing.centroid
    fraction = path_utm.project(mid) / path_utm.length if path_utm.length > 0 else 0.0
    line_elev = line_height_at(
        fraction, user_ground_m, user_height_m, tower_ground_m, tower_height_m
    )
    roof_elev = ground_elevation_m + height_m
    clearance = line_elev - roof_elev
    return clearance < 0, fraction, clearance


def find_obstructions(
    db: Session,
    user_lat: float, user_lon: float,
    tower_lat: float, tower_lon: float,
    user_ground_m: float, tower_ground_m: float,
    user_height_m: float, tower_height_m: float,
    ground_elevation_lookup=None,
) -> LosResult:
    """PostGIS candidate query + per-building height check.

    ground_elevation_lookup(lat, lon) -> float lets the caller supply terrain
    under each building; defaults to linear interpolation between endpoints.
    """
    path_wkt = f"LINESTRING({user_lon} {user_lat}, {tower_lon} {tower_lat})"
    path_geom = func.ST_GeomFromText(path_wkt, 4326)
    candidates = db.execute(
        select(Building).where(Building.geom.ST_Intersects(path_geom))
    )
    buildings = list(candidates.scalars())

    epsg = geo.utm_epsg_for(user_lon, user_lat)
    to_utm = lambda lon, lat: geo.to_utm(lon, lat, epsg)  # noqa: E731
    path_utm = LineString([to_utm(user_lon, user_lat), to_utm(tower_lon, tower_lat)])

    obstructions: list[Obstruction] = []
    for b in buildings:
        footprint = wkb.loads(bytes(b.geom.data))
        footprint_utm = shp_transform(lambda x, y: to_utm(x, y), footprint)
        # Ground under the building: caller-provided terrain, else endpoint interpolation.
        centroid = footprint.centroid
        if ground_elevation_lookup is not None:
            ground = ground_elevation_lookup(centroid.y, centroid.x)
        else:
            frac = path_utm.project(footprint_utm.centroid) / max(path_utm.length, 1.0)
            ground = user_ground_m + (tower_ground_m - user_ground_m) * frac
        obstructs, fraction, clearance = check_building_obstruction(
            footprint_utm, b.height_m, ground, path_utm,
            user_ground_m, user_height_m, tower_ground_m, tower_height_m,
        )
        if obstructs:
            obstructions.append(Obstruction(
                osm_id=b.osm_id,
                building_type=b.building_type,
                height_m=b.height_m,
                height_source=b.height_source,
                line_height_at_crossing_m=line_height_at(
                    fraction, user_ground_m, user_height_m, tower_ground_m, tower_height_m
                ),
                crossing_fraction=fraction,
                clearance_m=clearance,
            ))

    obstructions.sort(key=lambda o: o.crossing_fraction)
    return LosResult(obstructions=obstructions, checked_buildings=len(buildings))
