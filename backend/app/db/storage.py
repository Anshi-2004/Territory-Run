import asyncio
import uuid
from datetime import datetime, timezone
from typing import Dict, List, Optional, Any, Set, Tuple
from fastapi import WebSocket
import h3

from app.core.territory_math import (
    DEFAULT_H3_RESOLUTION,
    DEFAULT_HALF_LIFE_DAYS,
    DEFAULT_HYSTERESIS_FACTOR,
    latlng_to_h3,
    h3_to_postgis_wkt,
    h3_to_geojson_geometry,
    haversine_distance_meters,
)
from app.core.engine import TerritorySimulationEngine


class InMemorySpatialStore:
    """
    High-performance in-memory geospatial store implementing PostGIS and Redis behaviors.
    Provides fast H3 spatial indexing, real-time bounding box queries, route tracking,
    leaderboards, and user feeds.
    """

    def __init__(self):
        self._lock = asyncio.Lock()
        self.engine = TerritorySimulationEngine()
        
        # Players: id -> dict
        self.players: Dict[str, Dict[str, Any]] = {}
        # Email lookup: email -> player_id
        self.email_to_id: Dict[str, str] = {}
        # Username lookup: username -> player_id
        self.username_to_id: Dict[str, str] = {}

        # Routes: route_id -> dict
        self.routes: Dict[str, Dict[str, Any]] = {}

        # Notifications: id -> dict
        self.notifications: List[Dict[str, Any]] = []

    async def create_player(
        self,
        email: str,
        username: str,
        password_hash: str,
        color_hex: str = "#3388FF",
    ) -> Dict[str, Any]:
        async with self._lock:
            if email.lower() in self.email_to_id:
                raise ValueError("Email already registered")
            if username.lower() in self.username_to_id:
                raise ValueError("Username already taken")

            player_id = str(uuid.uuid4())
            player = {
                "id": player_id,
                "email": email.lower(),
                "username": username,
                "password_hash": password_hash,
                "color_hex": color_hex,
                "clan_id": None,
                "total_territory_area": 0.0,
                "coins": 0,
                "created_at": datetime.now(timezone.utc),
            }
            self.players[player_id] = player
            self.email_to_id[email.lower()] = player_id
            self.username_to_id[username.lower()] = player_id
            self.engine.register_player(player_id, username, color_hex)
            return player

    async def get_player_by_id(self, player_id: str) -> Optional[Dict[str, Any]]:
        async with self._lock:
            player = self.players.get(player_id)
            if not player:
                return None
            # Sync total territory area from engine
            engine_player = self.engine.players.get(player_id)
            if engine_player:
                player["total_territory_area"] = engine_player["total_territory_area"]
            return dict(player)

    async def get_player_by_email(self, email: str) -> Optional[Dict[str, Any]]:
        async with self._lock:
            player_id = self.email_to_id.get(email.lower())
            if not player_id:
                return None
            return dict(self.players[player_id])

    async def update_player(
        self,
        player_id: str,
        username: Optional[str] = None,
        color_hex: Optional[str] = None,
    ) -> Dict[str, Any]:
        async with self._lock:
            player = self.players.get(player_id)
            if not player:
                raise KeyError("Player not found")

            if username and username.lower() != player["username"].lower():
                if username.lower() in self.username_to_id:
                    raise ValueError("Username already taken")
                del self.username_to_id[player["username"].lower()]
                player["username"] = username
                self.username_to_id[username.lower()] = player_id
                if player_id in self.engine.players:
                    self.engine.players[player_id]["username"] = username

            if color_hex:
                player["color_hex"] = color_hex
                if player_id in self.engine.players:
                    self.engine.players[player_id]["color_hex"] = color_hex

            return dict(player)

    # Routes
    async def start_route(self, player_id: str, activity_type: str) -> Dict[str, Any]:
        async with self._lock:
            route_id = str(uuid.uuid4())
            route = {
                "id": route_id,
                "player_id": player_id,
                "activity_type": activity_type,
                "started_at": datetime.now(timezone.utc),
                "ended_at": None,
                "distance_m": 0.0,
                "pings": [],
                "touched_cells": set(),
                "captured_cells": set(),
            }
            self.routes[route_id] = route
            return route

    async def get_route(self, route_id: str) -> Optional[Dict[str, Any]]:
        async with self._lock:
            return self.routes.get(route_id)

    async def record_pings(
        self,
        route_id: str,
        pings: List[Dict[str, Any]],
    ) -> Dict[str, Any]:
        async with self._lock:
            route = self.routes.get(route_id)
            if not route:
                raise KeyError(f"Route {route_id} not found")
            if route["ended_at"] is not None:
                raise ValueError("Route has already ended")

            player_id = route["player_id"]
            activity_type = route["activity_type"]

            # Process through territory simulation engine
            res = self.engine.process_route_pings(
                player_id=player_id,
                activity_type=activity_type,
                pings=pings,
            )

            # Update route telemetry
            for p in pings:
                if route["pings"]:
                    last_p = route["pings"][-1]
                    dist = haversine_distance_meters(
                        last_p["lat"], last_p["lng"], p["lat"], p["lng"]
                    )
                    route["distance_m"] += dist
                route["pings"].append(p)

            for cell in res["touched_cells"]:
                route["touched_cells"].add(cell)

            for chg in res["ownership_changes"]:
                if chg["new_owner_id"] == player_id:
                    route["captured_cells"].add(chg["h3_index"])

            # Drain notification queue from engine to persistent store
            while self.engine.notification_queue:
                notif = self.engine.notification_queue.pop(0)
                notif_record = {
                    "id": str(uuid.uuid4()),
                    "player_id": notif["recipient_id"],
                    "title": notif["title"],
                    "message": notif["message"],
                    "h3_index": notif.get("h3_index"),
                    "displaced_by": notif.get("displaced_by"),
                    "created_at": datetime.now(timezone.utc),
                    "is_read": False,
                }
                self.notifications.append(notif_record)

            return res

    async def end_route(self, route_id: str) -> Dict[str, Any]:
        async with self._lock:
            route = self.routes.get(route_id)
            if not route:
                raise KeyError(f"Route {route_id} not found")
            if route["ended_at"] is None:
                route["ended_at"] = datetime.now(timezone.utc)
            return dict(route)

    # Territory Queries
    async def get_cells_in_bbox(
        self,
        min_lng: float,
        min_lat: float,
        max_lng: float,
        max_lat: float,
    ) -> List[Dict[str, Any]]:
        """
        Returns all owned cells whose center falls within the bounding box viewport.
        """
        async with self._lock:
            results = []
            for cell_id, cell_data in self.engine.territory_cells.items():
                owner_id = cell_data.get("owner_id")
                if not owner_id:
                    continue

                lat, lng = h3.cell_to_latlng(cell_id)
                # Check bounding box inclusion
                if min_lat <= lat <= max_lat and min_lng <= lng <= max_lng:
                    owner = self.players.get(owner_id, {})
                    results.append({
                        "h3_index": cell_id,
                        "owner_id": owner_id,
                        "owner_username": owner.get("username", "Unknown"),
                        "owner_color_hex": owner.get("color_hex", "#3388FF"),
                        "owner_score": round(cell_data.get("owner_score", 0.0), 3),
                        "last_claimed_at": cell_data.get("last_claimed_at"),
                        "geojson": h3_to_geojson_geometry(cell_id),
                    })
            return results

    async def get_cell_detail(self, h3_index: str) -> Optional[Dict[str, Any]]:
        async with self._lock:
            cell_data = self.engine.territory_cells.get(h3_index)
            if not cell_data and h3_index not in self.engine.cell_contests:
                # Return empty unowned structure with polygon
                try:
                    return {
                        "h3_index": h3_index,
                        "owner_id": None,
                        "owner_username": None,
                        "owner_color_hex": None,
                        "owner_score": 0.0,
                        "last_claimed_at": None,
                        "geojson": h3_to_geojson_geometry(h3_index),
                        "contestants": [],
                    }
                except Exception:
                    return None

            owner_id = cell_data.get("owner_id") if cell_data else None
            owner = self.players.get(owner_id, {}) if owner_id else {}

            contestants = []
            if h3_index in self.engine.cell_contests:
                for pid, cdata in self.engine.cell_contests[h3_index].items():
                    p = self.players.get(pid, {})
                    contestants.append({
                        "player_id": pid,
                        "username": p.get("username", "Unknown"),
                        "color_hex": p.get("color_hex", "#3388FF"),
                        "score": round(cdata["score"], 3),
                        "last_activity_at": cdata["last_activity_at"],
                    })
            contestants.sort(key=lambda c: c["score"], reverse=True)

            return {
                "h3_index": h3_index,
                "owner_id": owner_id,
                "owner_username": owner.get("username"),
                "owner_color_hex": owner.get("color_hex"),
                "owner_score": round(cell_data.get("owner_score", 0.0), 3) if cell_data else 0.0,
                "last_claimed_at": cell_data.get("last_claimed_at") if cell_data else None,
                "geojson": h3_to_geojson_geometry(h3_index),
                "contestants": contestants,
            }

    # Leaderboard
    async def get_leaderboard(self, scope: str = "local") -> List[Dict[str, Any]]:
        async with self._lock:
            lb = self.engine.get_leaderboard()
            return lb

    # Notifications
    async def get_player_notifications(self, player_id: str) -> List[Dict[str, Any]]:
        async with self._lock:
            notifs = [n for n in self.notifications if n["player_id"] == player_id]
            notifs.sort(key=lambda n: n["created_at"], reverse=True)
            return list(notifs)

    async def mark_notification_read(self, player_id: str, notif_id: str) -> bool:
        async with self._lock:
            for n in self.notifications:
                if n["id"] == notif_id and n["player_id"] == player_id:
                    n["is_read"] = True
                    return True
            return False


class WebSocketManager:
    """
    Manages active WebSocket subscriptions for real-time map viewport deltas
    and direct player notifications.
    """

    def __init__(self):
        # BBox subscriptions: ws -> (minLng, minLat, maxLng, maxLat)
        self.map_connections: Dict[WebSocket, Tuple[float, float, float, float]] = {}
        # Player connections: player_id -> Set[WebSocket]
        self.player_connections: Dict[str, Set[WebSocket]] = {}
        self._lock = asyncio.Lock()

    async def connect_map(
        self,
        websocket: WebSocket,
        bbox: Tuple[float, float, float, float],
    ):
        await websocket.accept()
        async with self._lock:
            self.map_connections[websocket] = bbox

    async def disconnect_map(self, websocket: WebSocket):
        async with self._lock:
            if websocket in self.map_connections:
                del self.map_connections[websocket]

    async def connect_player(self, websocket: WebSocket, player_id: str):
        await websocket.accept()
        async with self._lock:
            if player_id not in self.player_connections:
                self.player_connections[player_id] = set()
            self.player_connections[player_id].add(websocket)

    async def disconnect_player(self, websocket: WebSocket, player_id: str):
        async with self._lock:
            if player_id in self.player_connections:
                self.player_connections[player_id].discard(websocket)
                if not self.player_connections[player_id]:
                    del self.player_connections[player_id]

    async def broadcast_cell_delta(self, delta: Dict[str, Any]):
        """Broadcasts cell update to clients whose bbox viewport contains the cell."""
        h3_index = delta["h3_index"]
        lat, lng = h3.cell_to_latlng(h3_index)

        async with self._lock:
            dead_sockets = []
            for ws, (min_lng, min_lat, max_lng, max_lat) in self.map_connections.items():
                if min_lat <= lat <= max_lat and min_lng <= lng <= max_lng:
                    try:
                        await ws.send_json({
                            "type": "cell_update",
                            "delta": delta,
                        })
                    except Exception:
                        dead_sockets.append(ws)

            for ws in dead_sockets:
                if ws in self.map_connections:
                    del self.map_connections[ws]

    async def send_player_alert(self, player_id: str, alert: Dict[str, Any]):
        """Pushes real-time notification to a specific player's active sockets."""
        async with self._lock:
            sockets = list(self.player_connections.get(player_id, []))

        for ws in sockets:
            try:
                await ws.send_json({
                    "type": "notification",
                    "data": alert,
                })
            except Exception:
                pass


# Global singleton instances
store = InMemorySpatialStore()
ws_manager = WebSocketManager()
