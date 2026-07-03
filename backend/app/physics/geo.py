"""Shared geodesy helpers. All heavy geometry runs in a local UTM projection so
distances/intersections are in meters, not degrees."""

from functools import lru_cache

from pyproj import Geod, Transformer

_geod = Geod(ellps="WGS84")


def distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    _, _, dist = _geod.inv(lon1, lat1, lon2, lat2)
    return dist


def utm_epsg_for(lon: float, lat: float) -> int:
    zone = int((lon + 180) // 6) + 1
    return (32600 if lat >= 0 else 32700) + zone


@lru_cache(maxsize=32)
def _transformers(epsg: int) -> tuple[Transformer, Transformer]:
    fwd = Transformer.from_crs(4326, epsg, always_xy=True)
    inv = Transformer.from_crs(epsg, 4326, always_xy=True)
    return fwd, inv


def to_utm(lon: float, lat: float, epsg: int) -> tuple[float, float]:
    return _transformers(epsg)[0].transform(lon, lat)


def from_utm(x: float, y: float, epsg: int) -> tuple[float, float]:
    return _transformers(epsg)[1].transform(x, y)


def interpolate_path(
    lat1: float, lon1: float, lat2: float, lon2: float, n: int
) -> list[tuple[float, float]]:
    """n evenly spaced (lat, lon) points along the geodesic, endpoints included."""
    if n < 2:
        return [(lat1, lon1), (lat2, lon2)]
    pts = _geod.npts(lon1, lat1, lon2, lat2, n - 2)
    return [(lat1, lon1)] + [(la, lo) for lo, la in pts] + [(lat2, lon2)]
