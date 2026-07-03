from app.physics.terrain import profile_path, terrain_penalty_db


def test_no_penalty_when_terrain_clears():
    assert terrain_penalty_db(0.0) == 0.0
    assert terrain_penalty_db(-5.0) == 0.0


def test_penalty_grows_and_saturates():
    small = terrain_penalty_db(1.0)
    big = terrain_penalty_db(50.0)
    assert 0 < small < big <= 30.0


def test_flat_terrain_profile_no_intrusion():
    profile = profile_path(
        lambda lat, lon: 100.0,
        33.10, -96.70, 33.12, -96.68,
        user_ground_m=100.0, tower_ground_m=100.0,
        user_height_m=1.5, tower_height_m=30.0,
        sample_count=10,
    )
    assert profile.max_intrusion_m == 0.0
    assert profile.penalty_db == 0.0
    assert len(profile.samples) == 10


def test_hill_midpath_penalized():
    # 130 m hill in the middle of a path whose LOS line runs 101.5 → 130 m
    def hilly(lat, lon):
        return 130.0 if abs(lat - 33.11) < 0.004 else 100.0

    profile = profile_path(
        hilly,
        33.10, -96.70, 33.12, -96.68,
        user_ground_m=100.0, tower_ground_m=100.0,
        user_height_m=1.5, tower_height_m=30.0,
        sample_count=20,
    )
    assert profile.max_intrusion_m > 0
    assert profile.penalty_db > 0
