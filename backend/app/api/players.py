from fastapi import APIRouter, Depends, HTTPException, status
from app.schemas import PlayerResponse, PlayerUpdateRequest
from app.api.deps import get_current_player
from app.db import store

router = APIRouter(prefix="/players", tags=["Players"])


@router.get("/me", response_model=PlayerResponse)
async def get_me(current_player: dict = Depends(get_current_player)):
    """Retrieve profile and statistics of the authenticated player."""
    player_id = current_player["id"]
    player = await store.get_player_by_id(player_id)
    if not player:
        raise HTTPException(status_code=404, detail="Player not found")

    area_m2 = player.get("total_territory_area", 0.0)
    return PlayerResponse(
        id=player["id"],
        username=player["username"],
        email=player["email"],
        color_hex=player["color_hex"],
        total_territory_area=round(area_m2, 2),
        total_territory_area_km2=round(area_m2 / 1_000_000, 4),
        coins=player.get("coins", 0),
        created_at=player["created_at"],
    )


@router.patch("/me", response_model=PlayerResponse)
async def update_me(
    req: PlayerUpdateRequest,
    current_player: dict = Depends(get_current_player),
):
    """Update authenticated player's username or color hex."""
    player_id = current_player["id"]
    try:
        updated = await store.update_player(
            player_id=player_id,
            username=req.username,
            color_hex=req.color_hex,
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    area_m2 = updated.get("total_territory_area", 0.0)
    return PlayerResponse(
        id=updated["id"],
        username=updated["username"],
        email=updated["email"],
        color_hex=updated["color_hex"],
        total_territory_area=round(area_m2, 2),
        total_territory_area_km2=round(area_m2 / 1_000_000, 4),
        coins=updated.get("coins", 0),
        created_at=updated["created_at"],
    )
