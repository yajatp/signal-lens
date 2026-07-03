"""Terrain shadowing along the LOS path (spec §6.2 step 5).

Elevations come from the USGS 3DEP Elevation Point Query Service, cached in
the terrain_points table on a ~10 m grid. The penalty is a documented
heuristic: a knife-edge-flavored function of how deep the terrain pierces the
LOS line — not a full diffraction model (that's a Phase 2+ refinement).
"""

import math
from dataclasses import dataclass

from app.physics.geo import interpolate_path
from app.physics.los import line_height_at


@dataclass
class TerrainProfile:
    samples: list[tuple[float, float, float]]  # (lat, lon, elevation_m)
    max_intrusion_m: float                     # deepest terrain penetration into the LOS line
    penalty_db: float


def terrain_penalty_db(max_intrusion_m: float) -> float:
    """Heuristic knife-edge-style penalty. 0 dB when terrain clears the line;
    grows with intrusion depth and saturates around 30 dB."""
    if max_intrusion_m <= 0:
        return 0.0
    return min(30.0, 6.0 + 8.0 * math.log2(1.0 + max_intrusion_m))


def profile_path(
    elevations_lookup,
    user_lat: float, user_lon: float,
    tower_lat: float, tower_lon: float,
    user_ground_m: float, tower_ground_m: float,
    user_height_m: float, tower_height_m: float,
    sample_count: int = 12,
) -> TerrainProfile:
    """elevations_lookup(lat, lon) -> elevation_m (cached EPQS client or test stub)."""
    points = interpolate_path(user_lat, user_lon, tower_lat, tower_lon, sample_count)
    samples: list[tuple[float, float, float]] = []
    max_intrusion = 0.0
    n = len(points)
    for i, (lat, lon) in enumerate(points):
        elev = elevations_lookup(lat, lon)
        samples.append((lat, lon, elev))
        if i in (0, n - 1):
            continue  # endpoints are the antennas themselves
        fraction = i / (n - 1)
        line_elev = line_height_at(
            fraction, user_ground_m, user_height_m, tower_ground_m, tower_height_m
        )
        intrusion = elev - line_elev
        max_intrusion = max(max_intrusion, intrusion)
    return TerrainProfile(
        samples=samples,
        max_intrusion_m=max_intrusion,
        penalty_db=terrain_penalty_db(max_intrusion),
    )
