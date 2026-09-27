from fastapi import APIRouter, Depends, HTTPException, status
from app.schemas import (
    RouteStartRequest,
    RouteStartResponse,
    RoutePingBatchRequest,
    RoutePingBatchResponse,
    OwnershipDelta,
    RouteEndResponse,
)
from app.api.deps import get_current_player
from app.db import store, ws_manager
from app.core.anti_cheat import AntiCheatError

router = APIRouter(prefix="/routes", tags=["Routes"])


@router.post("/start", response_model=RouteStartResponse, status_code=status.HTTP_201_CREATED)
async def start_route(
    req: RouteStartRequest,
    current_player: dict = Depends(get_current_player),
):
    """Begins a tracked GPS session, returning the active route_id."""
    player_id = current_player["id"]
    route = await store.start_route(player_id, req.activity_type)
    return RouteStartResponse(
        route_id=route["id"],
        player_id=player_id,
        activity_type=route["activity_type"],
        started_at=route["started_at"],
    )


@router.post("/{route_id}/ping", response_model=RoutePingBatchResponse)
async def ping_route(
    route_id: str,
    req: RoutePingBatchRequest,
    current_player: dict = Depends(get_current_player),
):
    """
    Submits a batch of GPS telemetry pings.
    Enforces server-side anti-cheat, calculates touched H3 cells,
    updates contests, evaluates ownership flips, and pushes real-time broadcasts.
    """
    route = await store.get_route(route_id)
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")
    if route["player_id"] != current_player["id"]:
        raise HTTPException(status_code=403, detail="Not authorized to update this route")

    pings_data = [
        {"lat": p.lat, "lng": p.lng, "timestamp": p.timestamp}
        for p in req.pings
    ]

    try:
        res = await store.record_pings(route_id, pings_data)
    except AntiCheatError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Anti-cheat violation: {str(e)}",
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )

    ownership_deltas = []
    for chg in res["ownership_changes"]:
        delta = OwnershipDelta(
            h3_index=chg["h3_index"],
            new_owner_id=chg["new_owner_id"],
            previous_owner_id=chg["previous_owner_id"],
            score=round(chg["score"], 3),
            color_hex=current_player.get("color_hex", "#3388FF"),
            geojson=chg["geojson"],
        )
        ownership_deltas.append(delta)

        # Broadcast via WebSocket to map viewers
        await ws_manager.broadcast_cell_delta(delta.model_dump())

        # If displaced another player, dispatch real-time player alert
        if chg["previous_owner_id"] and chg["previous_owner_id"] != chg["new_owner_id"]:
            alert_msg = {
                "title": "Territory Lost!",
                "message": f"Your cell was captured by {current_player.get('username', 'another player')}!",
                "h3_index": chg["h3_index"],
                "displaced_by": current_player["id"],
                "timestamp": chg["timestamp"],
            }
            await ws_manager.send_player_alert(chg["previous_owner_id"], alert_msg)

    return RoutePingBatchResponse(
        processed_pings=len(pings_data),
        touched_cells_count=res["touched_cells_count"],
        claimed_or_conquered_cells=ownership_deltas,
    )


@router.post("/{route_id}/end", response_model=RouteEndResponse)
async def end_route(
    route_id: str,
    current_player: dict = Depends(get_current_player),
):
    """Finalizes a route tracking session, computing total distance and stats."""
    route = await store.get_route(route_id)
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")
    if route["player_id"] != current_player["id"]:
        raise HTTPException(status_code=403, detail="Not authorized to end this route")

    final_route = await store.end_route(route_id)
    return RouteEndResponse(
        route_id=final_route["id"],
        player_id=final_route["player_id"],
        activity_type=final_route["activity_type"],
        started_at=final_route["started_at"],
        ended_at=final_route["ended_at"],
        distance_meters=round(final_route.get("distance_m", 0.0), 2),
        cells_touched_count=len(final_route.get("touched_cells", set())),
        cells_captured_count=len(final_route.get("captured_cells", set())),
    )
