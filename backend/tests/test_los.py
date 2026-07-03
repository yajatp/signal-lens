"""LOS geometry tests with synthetic UTM footprints — no database required."""

from shapely.geometry import LineString, Polygon

from app.physics.los import check_building_obstruction, line_height_at


def square(cx: float, cy: float, half: float = 10.0) -> Polygon:
    return Polygon([
        (cx - half, cy - half), (cx + half, cy - half),
        (cx + half, cy + half), (cx - half, cy + half),
    ])


# 1 km straight path on flat ground: user at (0,0) h=1.5 m, tower at (1000,0) h=30 m
PATH = LineString([(0, 0), (1000, 0)])
FLAT = dict(user_ground_m=100.0, tower_ground_m=100.0, user_height_m=1.5, tower_height_m=30.0)


def test_line_height_interpolation():
    assert line_height_at(0.0, 100, 1.5, 100, 30) == 101.5
    assert line_height_at(1.0, 100, 1.5, 100, 30) == 130.0
    assert line_height_at(0.5, 100, 1.5, 100, 30) == 115.75


def test_tall_building_midpath_obstructs():
    # LOS line is at ~115.75 m elevation midpath; 20 m building on 100 m ground → roof 120 m
    obstructs, fraction, clearance = check_building_obstruction(
        square(500, 0), height_m=20.0, ground_elevation_m=100.0, path_utm=PATH, **FLAT
    )
    assert obstructs
    assert 0.45 < fraction < 0.55
    assert clearance < 0


def test_short_building_midpath_clears():
    # 10 m building → roof 110 m, below the 115.75 m line
    obstructs, _, clearance = check_building_obstruction(
        square(500, 0), height_m=10.0, ground_elevation_m=100.0, path_utm=PATH, **FLAT
    )
    assert not obstructs
    assert clearance > 0


def test_building_off_path_ignored():
    obstructs, _, clearance = check_building_obstruction(
        square(500, 300), height_m=50.0, ground_elevation_m=100.0, path_utm=PATH, **FLAT
    )
    assert not obstructs
    assert clearance == float("inf")


def test_same_building_blocks_near_user_but_not_near_tower():
    # 12 m roof: line is ~104.35 m at x=100 (blocked), ~127.15 m at x=900 (clear)
    near_user, _, _ = check_building_obstruction(
        square(100, 0), height_m=12.0, ground_elevation_m=100.0, path_utm=PATH, **FLAT
    )
    near_tower, _, _ = check_building_obstruction(
        square(900, 0), height_m=12.0, ground_elevation_m=100.0, path_utm=PATH, **FLAT
    )
    assert near_user
    assert not near_tower
