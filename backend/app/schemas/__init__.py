from pydantic import BaseModel, EmailStr, Field
from typing import Optional, List, Dict, Any
from datetime import datetime


# Auth Schemas
class RegisterRequest(BaseModel):
    email: EmailStr
    username: str = Field(..., min_length=3, max_length=30)
    password: str = Field(..., min_length=6)
    color_hex: Optional[str] = Field(default="#3388FF", pattern=r"^#[0-9a-fA-F]{6}$")


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    player_id: str
    username: str
    color_hex: str


# Player Schemas
class PlayerResponse(BaseModel):
    id: str
    username: str
    email: str
    color_hex: str
    total_territory_area: float
    total_territory_area_km2: float
    coins: int
    created_at: datetime


class PlayerUpdateRequest(BaseModel):
    username: Optional[str] = Field(None, min_length=3, max_length=30)
    color_hex: Optional[str] = Field(None, pattern=r"^#[0-9a-fA-F]{6}$")


# Route Schemas
class RouteStartRequest(BaseModel):
    activity_type: str = Field(default="walk", pattern=r"^(walk|jog|run)$")


class RouteStartResponse(BaseModel):
    route_id: str
    player_id: str
    activity_type: str
    started_at: datetime


class PingPoint(BaseModel):
    lat: float = Field(..., ge=-90.0, le=90.0)
    lng: float = Field(..., ge=-180.0, le=180.0)
    timestamp: datetime


class RoutePingBatchRequest(BaseModel):
    pings: List[PingPoint]


class OwnershipDelta(BaseModel):
    h3_index: str
    new_owner_id: str
    previous_owner_id: Optional[str] = None
    score: float
    color_hex: str
    geojson: Dict[str, Any]


class RoutePingBatchResponse(BaseModel):
    processed_pings: int
    touched_cells_count: int
    claimed_or_conquered_cells: List[OwnershipDelta]


class RouteEndResponse(BaseModel):
    route_id: str
    player_id: str
    activity_type: str
    started_at: datetime
    ended_at: datetime
    distance_meters: float
    cells_touched_count: int
    cells_captured_count: int


class CloseLoopRequest(BaseModel):
    loop_points: List[PingPoint] = Field(..., min_length=4)
    activity_type: Optional[str] = Field(default="walk", pattern=r"^(walk|jog|run)$")


class CloseLoopResponse(BaseModel):
    enclosed_cells_count: int
    enclosed_area_m2: float
    captured_cells: List[OwnershipDelta]
    message: str


# Territory Schemas
class TerritoryCellResponse(BaseModel):
    h3_index: str
    owner_id: Optional[str] = None
    owner_username: Optional[str] = None
    owner_color_hex: Optional[str] = None
    owner_score: float = 0.0
    last_claimed_at: Optional[datetime] = None
    geojson: Dict[str, Any]


class CellContestant(BaseModel):
    player_id: str
    username: str
    color_hex: str
    score: float
    last_activity_at: datetime


class CellDetailResponse(BaseModel):
    h3_index: str
    owner_id: Optional[str] = None
    owner_username: Optional[str] = None
    owner_color_hex: Optional[str] = None
    owner_score: float = 0.0
    last_claimed_at: Optional[datetime] = None
    geojson: Dict[str, Any]
    contestants: List[CellContestant]


# Leaderboard Schemas
class LeaderboardEntry(BaseModel):
    rank: int
    player_id: str
    username: str
    color_hex: str
    total_territory_area_m2: float
    total_territory_area_km2: float


class LeaderboardResponse(BaseModel):
    scope: str
    entries: List[LeaderboardEntry]


# Notification Schemas
class NotificationResponse(BaseModel):
    id: str
    title: str
    message: str
    h3_index: Optional[str] = None
    displaced_by: Optional[str] = None
    created_at: datetime
    is_read: bool
