import math
from datetime import datetime, timezone
from typing import List, Tuple, Dict, Any, Optional
import h3


DEFAULT_H3_RESOLUTION = 9
DEFAULT_HALF_LIFE_DAYS = 14.0
DEFAULT_HYSTERESIS_FACTOR = 1.15  # 15% buffer
MAX_SPEED_KMH = 25.0  # Max sustained speed before anti-cheat rejection

ACTIVITY_WEIGHTS = {
    "walk": 1.0,
    "jog": 1.3,
    "run": 1.6,
}


def get_activity_weight(activity_type: str) -> float:
    """Return the scoring weight multiplier for a given activity type."""
    norm_type = (activity_type or "walk").strip().lower()
    return ACTIVITY_WEIGHTS.get(norm_type, 1.0)


def calculate_recency_decay(
    visit_time: datetime,
    current_time: Optional[datetime] = None,
    half_life_days: float = DEFAULT_HALF_LIFE_DAYS,
) -> float:
    """
    Calculate exponential decay factor based on elapsed time:
    decay = 2 ^ (-elapsed_seconds / half_life_seconds)
    At t = 0, returns 1.0
    At t = half_life_days, returns 0.5
    """
    if current_time is None:
        current_time = datetime.now(timezone.utc)

    # Ensure both datetimes are timezone-aware
    if visit_time.tzinfo is None:
        visit_time = visit_time.replace(tzinfo=timezone.utc)
    if current_time.tzinfo is None:
        current_time = current_time.replace(tzinfo=timezone.utc)

    elapsed_seconds = max(0.0, (current_time - visit_time).total_seconds())
    half_life_seconds = half_life_days * 86400.0

    if half_life_seconds <= 0:
        return 1.0

    return math.pow(2.0, -elapsed_seconds / half_life_seconds)


def latlng_to_h3(lat: float, lng: float, resolution: int = DEFAULT_H3_RESOLUTION) -> str:
    """Convert (latitude, longitude) coordinate to an H3 hexagon index string."""
    return h3.latlng_to_cell(lat, lng, resolution)


def h3_to_boundary_coords(h3_index: str) -> List[Tuple[float, float]]:
    """
    Return the boundary coordinates of the H3 cell as a list of (lat, lng) tuples.
    """
    return list(h3.cell_to_boundary(h3_index))


def h3_to_postgis_wkt(h3_index: str) -> str:
    """
    Convert an H3 cell index to a PostGIS-compatible WKT Polygon string.
    Coordinates in PostGIS WKT are formatted as: (lng lat, ...) with closed ring.
    SRID 4326 is standard WGS-84.
    """
    boundary = h3.cell_to_boundary(h3_index)
    if not boundary:
        raise ValueError(f"Invalid H3 index or empty boundary for: {h3_index}")

    # Standard WKT expects 'lng lat'
    coords = [f"{lng} {lat}" for lat, lng in boundary]
    # Close polygon ring by repeating the first vertex
    coords.append(f"{boundary[0][1]} {boundary[0][0]}")

    ring_str = ", ".join(coords)
    return f"SRID=4326;POLYGON(({ring_str}))"


def h3_to_geojson_geometry(h3_index: str) -> Dict[str, Any]:
    """
    Convert H3 cell index into GeoJSON Polygon geometry dictionary.
    Coordinates format: [[[lng, lat], [lng, lat], ..., [lng0, lat0]]]
    """
    boundary = h3.cell_to_boundary(h3_index)
    coords = [[lng, lat] for lat, lng in boundary]
    coords.append([boundary[0][1], boundary[0][0]])  # Close ring
    return {
        "type": "Polygon",
        "coordinates": [coords],
    }


def haversine_distance_meters(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """
    Compute great-circle distance between two GPS coordinates using the Haversine formula.
    Returns distance in meters.
    """
    R = 6371000.0  # Earth radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lng2 - lng1)

    a = (
        math.sin(delta_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return R * c


def compute_speed_kmh(
    lat1: float, lng1: float, t1: datetime,
    lat2: float, lng2: float, t2: datetime
) -> float:
    """Compute instantaneous speed between two timestamped points in km/h."""
    dist_m = haversine_distance_meters(lat1, lng1, lat2, lng2)
    dt_seconds = abs((t2 - t1).total_seconds())

    if dt_seconds <= 0.001:
        # Effectively zero time; if distance is non-trivial, speed is infinite
        return 999999.0 if dist_m > 1.0 else 0.0

    speed_mps = dist_m / dt_seconds
    return speed_mps * 3.6  # Convert m/s to km/h


def evaluate_ownership_flip(
    current_owner_id: Optional[str],
    current_owner_score: float,
    challenger_id: str,
    challenger_score: float,
    hysteresis_factor: float = DEFAULT_HYSTERESIS_FACTOR,
) -> Tuple[bool, Optional[str], float]:
    """
    Evaluate if ownership of a cell flips to the challenger.
    Rule:
      - If no current owner or current_owner_id is challenger: owner stays/is challenger if score > 0.
      - If current owner exists and != challenger:
        flips ONLY if challenger_score > hysteresis_factor * current_owner_score (15% buffer).
    Returns:
      (has_flipped, new_owner_id, new_owner_score)
    """
    if challenger_score <= 0.0:
        return False, current_owner_id, current_owner_score

    if current_owner_id is None or current_owner_id == "":
        # Unowned cell claimed by challenger
        return True, challenger_id, challenger_score

    if current_owner_id == challenger_id:
        # Same player defending or increasing score
        return False, current_owner_id, max(current_owner_score, challenger_score)

    threshold = current_owner_score * hysteresis_factor
    if challenger_score > threshold:
        return True, challenger_id, challenger_score

    return False, current_owner_id, current_owner_score
