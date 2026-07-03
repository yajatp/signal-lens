"""Log-distance path loss model (spec §6.1).

PL(d) = PL(d0) + 10 * n * log10(d / d0)

PL(d0) is free-space (Friis) loss at the reference distance d0. The shadowing
term X_sigma is intentionally 0 for MVP — it is what the ML residual layer
replaces later.
"""

import math

# Practical RSRP bounds per 3GPP reporting range.
RSRP_MIN_DBM = -140.0
RSRP_MAX_DBM = -44.0


def free_space_path_loss_db(distance_m: float, frequency_mhz: float) -> float:
    """Friis free-space path loss. Distance clamped to >= 1 m."""
    d_km = max(distance_m, 1.0) / 1000.0
    return 20 * math.log10(d_km) + 20 * math.log10(frequency_mhz) + 32.44


def log_distance_path_loss_db(
    distance_m: float,
    frequency_mhz: float,
    exponent: float,
    reference_distance_m: float = 100.0,
) -> float:
    d = max(distance_m, 1.0)
    d0 = max(reference_distance_m, 1.0)
    pl_d0 = free_space_path_loss_db(d0, frequency_mhz)
    if d <= d0:
        return free_space_path_loss_db(d, frequency_mhz)
    return pl_d0 + 10 * exponent * math.log10(d / d0)


def received_power_dbm(
    distance_m: float,
    frequency_mhz: float,
    exponent: float,
    eirp_dbm: float,
    reference_distance_m: float = 100.0,
) -> float:
    """Baseline received power before obstruction/terrain penalties, clamped to RSRP range."""
    pl = log_distance_path_loss_db(distance_m, frequency_mhz, exponent, reference_distance_m)
    return clamp_rsrp(eirp_dbm - pl)


def clamp_rsrp(dbm: float) -> float:
    return max(RSRP_MIN_DBM, min(RSRP_MAX_DBM, dbm))
