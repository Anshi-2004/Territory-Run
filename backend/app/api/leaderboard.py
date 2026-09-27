from fastapi import APIRouter, HTTPException, status
from app.schemas import LeaderboardResponse, LeaderboardEntry
from app.db import store

router = APIRouter(prefix="/leaderboard", tags=["Leaderboard"])


@router.get("/{scope}", response_model=LeaderboardResponse)
async def get_leaderboard(scope: str = "local"):
    """
    Returns the leaderboard ranked by total territory area descending.
    Scope can be: local | city | country | global
    """
    valid_scopes = {"local", "city", "country", "global"}
    if scope.lower() not in valid_scopes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid scope '{scope}'. Allowed: {', '.join(valid_scopes)}",
        )

    entries = await store.get_leaderboard(scope=scope.lower())
    return LeaderboardResponse(
        scope=scope.lower(),
        entries=[
            LeaderboardEntry(
                rank=e["rank"],
                player_id=e["player_id"],
                username=e["username"],
                color_hex=e["color_hex"],
                total_territory_area_m2=e["total_territory_area_m2"],
                total_territory_area_km2=e["total_territory_area_km2"],
            )
            for e in entries
        ],
    )
