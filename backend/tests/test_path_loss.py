import math

from app.physics.path_loss import (
    RSRP_MAX_DBM,
    RSRP_MIN_DBM,
    clamp_rsrp,
    free_space_path_loss_db,
    log_distance_path_loss_db,
    received_power_dbm,
)


def test_friis_known_value():
    # FSPL at 1 km, 1900 MHz: 32.44 + 20log10(1) + 20log10(1900) ≈ 98.03 dB
    assert math.isclose(free_space_path_loss_db(1000, 1900), 98.03, abs_tol=0.05)


def test_friis_doubles_distance_adds_6db():
    a = free_space_path_loss_db(1000, 1900)
    b = free_space_path_loss_db(2000, 1900)
    assert math.isclose(b - a, 6.02, abs_tol=0.01)


def test_log_distance_matches_friis_at_reference():
    d0 = 100.0
    assert math.isclose(
        log_distance_path_loss_db(d0, 1900, 2.9, d0),
        free_space_path_loss_db(d0, 1900),
        abs_tol=1e-9,
    )


def test_log_distance_exponent_slope():
    # 10x distance beyond d0 adds 10*n dB
    pl1 = log_distance_path_loss_db(1000, 1900, 2.9, 100)
    pl2 = log_distance_path_loss_db(10000, 1900, 2.9, 100)
    assert math.isclose(pl2 - pl1, 29.0, abs_tol=0.01)


def test_received_power_decreases_with_distance():
    near = received_power_dbm(200, 1900, 2.9, 58)
    far = received_power_dbm(5000, 1900, 2.9, 58)
    assert near > far
    assert RSRP_MIN_DBM <= far <= near <= RSRP_MAX_DBM


def test_clamp():
    assert clamp_rsrp(-500) == RSRP_MIN_DBM
    assert clamp_rsrp(0) == RSRP_MAX_DBM
    assert clamp_rsrp(-90) == -90
