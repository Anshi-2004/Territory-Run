from datetime import datetime, timezone
from typing import Dict, List, Any, Optional, Set
import h3

from app.core.territory_math import (
    DEFAULT_H3_RESOLUTION,
    DEFAULT_HALF_LIFE_DAYS,
    DEFAULT_HYSTERESIS_FACTOR,
    get_activity_weight,
    calculate_recency_decay,
    evaluate_ownership_flip,
    h3_to_postgis_wkt,
    h3_to_geojson_geometry,
    latlng_to_h3,
)
from app.core.anti_cheat import AntiCheatValidator, AntiCheatError


class TerritorySimulationEngine:
    """
    In-memory territory state & recalculation engine implementing Section 3, 6, and 7.
    Can be used standalone (Phase 0 validation) or backed by PostgreSQL/Redis in Phase 1+.
    """

    def __init__(
        self,
        h3_resolution: int = DEFAULT_H3_RESOLUTION,
        half_life_days: float = DEFAULT_HALF_LIFE_DAYS,
        hysteresis_factor: float = DEFAULT_HYSTERESIS_FACTOR,
    ):
        self.h3_resolution = h3_resolution
        self.half_life_days = half_life_days
        self.hysteresis_factor = hysteresis_factor
        self.validator = AntiCheatValidator()

        # In-memory representations mirroring database tables:
        # players: player_id -> {"username": str, "color_hex": str, "total_territory_area": float}
        self.players: Dict[str, Dict[str, Any]] = {}

        # territory_cells: h3_index -> {"owner_id": Optional[str], "owner_score": float, "last_claimed_at": datetime, "geom_wkt": str}
        self.territory_cells: Dict[str, Dict[str, Any]] = {}

        # cell_contests: (h3_index, player_id) -> {"score": float, "last_activity_at": datetime}
        self.cell_contests: Dict[str, Dict[str, Dict[str, Any]]] = {}

        # Queued displaced notifications: List[Dict]
        self.notification_queue: List[Dict[str, Any]] = []

        # Broadcast event log for WebSocket simulations
        self.event_stream: List[Dict[str, Any]] = []

    def register_player(self, player_id: str, username: str, color_hex: str = "#3388FF") -> Dict[str, Any]:
        """Register or update a player in the game engine."""
        self.players[player_id] = {
            "id": player_id,
            "username": username,
            "color_hex": color_hex,
            "total_territory_area": 0.0,
        }
        return self.players[player_id]

    def get_cell_area_m2(self, h3_index: str) -> float:
        """Returns cell area in square meters."""
        return float(h3.cell_area(h3_index, "m^2"))

    def process_route_pings(
        self,
        player_id: str,
        activity_type: str,
        pings: List[Dict[str, Any]],
        current_time: Optional[datetime] = None,
        allow_direct_flips: bool = True,
    ) -> Dict[str, Any]:
        """
        Executes Section 6 Territory Recalculation Flow:
          1. Validate GPS telemetry against anti-cheat rules.
          2. Snap points to H3 cells.
          3. Upsert scores with activity weight and recency decay.
          4. Check and flip ownership if score > 1.15 * owner_score.
          5. Update total territory area and trigger notifications.
        """
        if current_time is None:
            current_time = datetime.now(timezone.utc)
        elif current_time.tzinfo is None:
            current_time = current_time.replace(tzinfo=timezone.utc)

        # 1. Anti-cheat validation
        validated_pings = self.validator.validate_pings(pings, self.h3_resolution)
        weight = get_activity_weight(activity_type)

        touched_cells: Set[str] = set()
        ownership_changes: List[Dict[str, Any]] = []

        # Process each point
        for ping_data, cell in validated_pings:
            touched_cells.add(cell)
            visit_ts = ping_data["timestamp"]
            decay = calculate_recency_decay(
                visit_time=visit_ts,
                current_time=current_time,
                half_life_days=self.half_life_days,
            )
            incremental_score = weight * decay

            # 2a. Upsert cell_contests(cell, player)
            if cell not in self.cell_contests:
                self.cell_contests[cell] = {}

            if player_id not in self.cell_contests[cell]:
                self.cell_contests[cell][player_id] = {
                    "score": 0.0,
                    "last_activity_at": visit_ts,
                }

            contest_record = self.cell_contests[cell][player_id]
            contest_record["score"] += incremental_score
            contest_record["last_activity_at"] = visit_ts

            # Retrieve current cell status
            cell_record = self.territory_cells.get(cell, {
                "h3_index": cell,
                "owner_id": None,
                "owner_score": 0.0,
                "last_claimed_at": None,
                "geom_wkt": h3_to_postgis_wkt(cell),
            })

            curr_owner_id = cell_record["owner_id"]
            curr_owner_score = cell_record["owner_score"]

            # If current owner is contesting, evaluate decaying of owner's score
            if curr_owner_id and curr_owner_id in self.cell_contests[cell]:
                owner_last_act = self.cell_contests[cell][curr_owner_id]["last_activity_at"]
                owner_decay = calculate_recency_decay(
                    visit_time=owner_last_act,
                    current_time=current_time,
                    half_life_days=self.half_life_days,
                )
                effective_owner_score = (
                    self.cell_contests[cell][curr_owner_id]["score"] * owner_decay
                )
            else:
                effective_owner_score = curr_owner_score

            challenger_score = contest_record["score"]

            # 2c. Check ownership flip rule (15% hysteresis)
            flipped, new_owner, new_score = evaluate_ownership_flip(
                current_owner_id=curr_owner_id,
                current_owner_score=effective_owner_score,
                challenger_id=player_id,
                challenger_score=challenger_score,
                hysteresis_factor=self.hysteresis_factor,
            )

            # Territory capture requires completing a closed circle unless direct flips are requested
            if allow_direct_flips and flipped:
                displaced_player_id = curr_owner_id
                cell_area = self.get_cell_area_m2(cell)

                # Update territory_cells
                cell_record["owner_id"] = new_owner
                cell_record["owner_score"] = new_score
                cell_record["last_claimed_at"] = visit_ts
                self.territory_cells[cell] = cell_record

                # Update area stats
                if displaced_player_id and displaced_player_id in self.players:
                    self.players[displaced_player_id]["total_territory_area"] = max(
                        0.0,
                        self.players[displaced_player_id]["total_territory_area"] - cell_area,
                    )

                if new_owner in self.players:
                    self.players[new_owner]["total_territory_area"] += cell_area

                change_event = {
                    "h3_index": cell,
                    "new_owner_id": new_owner,
                    "previous_owner_id": displaced_player_id,
                    "score": new_score,
                    "timestamp": visit_ts.isoformat(),
                    "geojson": h3_to_geojson_geometry(cell),
                }
                ownership_changes.append(change_event)
                self.event_stream.append(change_event)

                # 2d. Notification to displaced player
                if displaced_player_id and displaced_player_id != new_owner:
                    notif = {
                        "recipient_id": displaced_player_id,
                        "title": "Territory Lost!",
                        "message": f"Your territory at cell {cell[:8]}... was captured by {self.players.get(new_owner, {}).get('username', 'another player')}!",
                        "h3_index": cell,
                        "displaced_by": new_owner,
                        "timestamp": visit_ts.isoformat(),
                    }
                    self.notification_queue.append(notif)
            else:
                # Update current owner score if owner defended
                if curr_owner_id == player_id:
                    cell_record["owner_score"] = new_score
                    self.territory_cells[cell] = cell_record

        return {
            "touched_cells_count": len(touched_cells),
            "touched_cells": list(touched_cells),
            "ownership_changes": ownership_changes,
        }

    def process_closed_loop(
        self,
        player_id: str,
        activity_type: str,
        loop_points: List[Dict[str, Any]],
        current_time: Optional[datetime] = None,
    ) -> Dict[str, Any]:
        """
        Executes Loop Enclosure Conquest:
        When a runner completes a circle/loop:
          1. Form a closed boundary polygon from GPS coordinates.
          2. Compute all perimeter cells along the loop boundary.
          3. Polyfill all interior H3 hexagon cells inside the enclosed area.
          4. Capture and flip ownership of ALL cells inside the circle for the runner!
        """
        if current_time is None:
            current_time = datetime.now(timezone.utc)
        elif current_time.tzinfo is None:
            current_time = current_time.replace(tzinfo=timezone.utc)

        coords = [(float(p["lat"]), float(p["lng"])) for p in loop_points]
        if len(coords) < 3:
            return {"enclosed_cells_count": 0, "enclosed_area_m2": 0.0, "ownership_changes": []}

        # Close polygon if not closed
        if coords[0] != coords[-1]:
            coords.append(coords[0])

        weight = get_activity_weight(activity_type)
        perimeter_cells: Set[str] = set()

        # Continuous edge sampling
        for i in range(len(coords) - 1):
            p1 = coords[i]
            p2 = coords[i + 1]
            perimeter_cells.add(latlng_to_h3(p1[0], p1[1], self.h3_resolution))
            perimeter_cells.add(latlng_to_h3(p2[0], p2[1], self.h3_resolution))
            # Midpoint sampling
            mid_lat = (p1[0] + p2[0]) / 2.0
            mid_lng = (p1[1] + p2[1]) / 2.0
            perimeter_cells.add(latlng_to_h3(mid_lat, mid_lng, self.h3_resolution))

        # Enclosed interior cells via H3 LatLngPoly
        interior_cells: Set[str] = set()
        try:
            poly = h3.LatLngPoly(coords)
            interior_cells = set(h3.polygon_to_cells(poly, res=self.h3_resolution))
        except Exception:
            interior_cells = set()

        all_enclosed_cells = perimeter_cells | interior_cells
        ownership_changes: List[Dict[str, Any]] = []
        total_captured_area = 0.0

        for cell in all_enclosed_cells:
            cell_record = self.territory_cells.get(cell, {
                "h3_index": cell,
                "owner_id": None,
                "owner_score": 0.0,
                "last_claimed_at": None,
                "geom_wkt": h3_to_postgis_wkt(cell),
            })

            curr_owner_id = cell_record["owner_id"]
            cell_area = self.get_cell_area_m2(cell)
            total_captured_area += cell_area

            # Award significant loop conquest score
            loop_score = 12.0 * weight
            if cell not in self.cell_contests:
                self.cell_contests[cell] = {}
            if player_id not in self.cell_contests[cell]:
                self.cell_contests[cell][player_id] = {"score": 0.0, "last_activity_at": current_time}

            self.cell_contests[cell][player_id]["score"] += loop_score
            self.cell_contests[cell][player_id]["last_activity_at"] = current_time

            # Flip cell ownership to the loop conqueror
            cell_record["owner_id"] = player_id
            cell_record["owner_score"] = self.cell_contests[cell][player_id]["score"]
            cell_record["last_claimed_at"] = current_time
            self.territory_cells[cell] = cell_record

            # Update total player territory area
            if curr_owner_id != player_id:
                if player_id in self.players:
                    self.players[player_id]["total_territory_area"] += cell_area
                if curr_owner_id and curr_owner_id in self.players:
                    self.players[curr_owner_id]["total_territory_area"] = max(
                        0.0, self.players[curr_owner_id]["total_territory_area"] - cell_area
                    )

                change_event = {
                    "h3_index": cell,
                    "new_owner_id": player_id,
                    "previous_owner_id": curr_owner_id,
                    "score": cell_record["owner_score"],
                    "timestamp": current_time.isoformat(),
                    "geojson": h3_to_geojson_geometry(cell),
                }
                ownership_changes.append(change_event)
                self.event_stream.append(change_event)

                if curr_owner_id and curr_owner_id != player_id:
                    notif = {
                        "recipient_id": curr_owner_id,
                        "title": "Territory Enclosed!",
                        "message": f"Your territory at cell {cell[:8]}... was encircled and captured by {self.players.get(player_id, {}).get('username', 'another player')}!",
                        "h3_index": cell,
                        "displaced_by": player_id,
                        "timestamp": current_time.isoformat(),
                    }
                    self.notification_queue.append(notif)

        return {
            "enclosed_cells_count": len(all_enclosed_cells),
            "enclosed_area_m2": total_captured_area,
            "ownership_changes": ownership_changes,
        }

    def get_leaderboard(self) -> List[Dict[str, Any]]:
        """Return leaderboard ranked by total claimed territory area descending."""
        sorted_players = sorted(
            self.players.values(),
            key=lambda p: p["total_territory_area"],
            reverse=True,
        )
        return [
            {
                "rank": i + 1,
                "player_id": p["id"],
                "username": p["username"],
                "color_hex": p["color_hex"],
                "total_territory_area_m2": round(p["total_territory_area"], 2),
                "total_territory_area_km2": round(p["total_territory_area"] / 1_000_000, 4),
            }
            for i, p in enumerate(sorted_players)
        ]
