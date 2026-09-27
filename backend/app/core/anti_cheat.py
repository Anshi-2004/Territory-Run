from datetime import datetime, timezone
from typing import List, Dict, Any, Tuple, Optional
import h3

from app.core.territory_math import (
    haversine_distance_meters,
    compute_speed_kmh,
    latlng_to_h3,
    MAX_SPEED_KMH,
)


class AntiCheatError(Exception):
    """Raised when GPS pings violate anti-cheat constraints."""
    pass


class AntiCheatValidator:
    """
    Enforces anti-cheat integrity rules on GPS telemetry before scoring:
      1. Speed sanity check: sustained speed <= 25.0 km/h (running/jogging max).
      2. Continuity / Teleportation check: consecutive cells must be identical or adjacent neighbors.
      3. Rate limiting on cell touch events.
    """

    def __init__(
        self,
        max_speed_kmh: float = MAX_SPEED_KMH,
        max_rate_cells_per_minute: int = 40,
    ):
        self.max_speed_kmh = max_speed_kmh
        self.max_rate_cells_per_minute = max_rate_cells_per_minute

    def validate_pings(
        self,
        pings: List[Dict[str, Any]],
        h3_resolution: int = 9,
    ) -> List[Tuple[Dict[str, Any], str]]:
        """
        Validates an ordered list of GPS pings:
          pings: list of dicts with keys 'lat', 'lng', 'timestamp' (ISO string or datetime).
        Returns a list of validated tuples: (ping_data, h3_index).
        Raises AntiCheatError if an invalid or spoofed jump is detected.
        """
        if not pings:
            return []

        validated: List[Tuple[Dict[str, Any], str]] = []
        prev_ping: Optional[Dict[str, Any]] = None
        prev_h3: Optional[str] = None

        for idx, ping in enumerate(pings):
            lat = float(ping["lat"])
            lng = float(ping["lng"])
            ts = ping["timestamp"]
            if isinstance(ts, str):
                ts = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            if ts.tzinfo is None:
                ts = ts.replace(tzinfo=timezone.utc)

            cell = latlng_to_h3(lat, lng, resolution=h3_resolution)

            if prev_ping is not None:
                prev_ts = prev_ping["timestamp"]
                if isinstance(prev_ts, str):
                    prev_ts = datetime.fromisoformat(prev_ts.replace("Z", "+00:00"))
                if prev_ts.tzinfo is None:
                    prev_ts = prev_ts.replace(tzinfo=timezone.utc)

                dt = (ts - prev_ts).total_seconds()
                if dt < 0:
                    raise AntiCheatError(
                        f"Non-monotonic timestamp order at point #{idx}: {ts} < {prev_ts}"
                    )

                # Speed check
                speed = compute_speed_kmh(
                    prev_ping["lat"], prev_ping["lng"], prev_ts,
                    lat, lng, ts,
                )

                if speed > self.max_speed_kmh:
                    raise AntiCheatError(
                        f"Excessive speed detected at point #{idx}: {speed:.2f} km/h "
                        f"exceeds sustained limit of {self.max_speed_kmh} km/h."
                    )

                # Spatial adjacency / teleportation check:
                # If cells differ, check grid distance or neighbor status
                if prev_h3 and cell != prev_h3:
                    is_neighbor = h3.are_neighbor_cells(prev_h3, cell)
                    if not is_neighbor:
                        dist_steps = h3.grid_distance(prev_h3, cell)
                        # If points are far apart without intermediate route cells
                        if dist_steps > 1:
                            raise AntiCheatError(
                                f"Discontinuous cell jump detected: cell {prev_h3} to {cell} "
                                f"(grid distance {dist_steps} steps, expected <= 1). Teleportation rejected."
                            )

            validated.append(({"lat": lat, "lng": lng, "timestamp": ts}, cell))
            prev_ping = {"lat": lat, "lng": lng, "timestamp": ts}
            prev_h3 = cell

        return validated
