import asyncio
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from app.db import ws_manager

router = APIRouter(tags=["Realtime WebSockets"])


@router.websocket("/ws/map/{bbox}")
async def websocket_map_viewport(websocket: WebSocket, bbox: str):
    """
    WebSocket endpoint for real-time map cell updates.
    Client subscribes by specifying its viewport bbox: minLng,minLat,maxLng,maxLat.
    Whenever a cell inside this viewport flips ownership, deltas are pushed immediately.
    """
    try:
        parts = [float(x.strip()) for x in bbox.split(",")]
        if len(parts) != 4:
            await websocket.close(code=1008, reason="Invalid bbox parameters")
            return
        bbox_tuple = (parts[0], parts[1], parts[2], parts[3])
    except Exception:
        await websocket.close(code=1008, reason="Invalid bbox parameters")
        return

    await ws_manager.connect_map(websocket, bbox_tuple)
    try:
        # Keep socket open and receive any viewport updates/pings from client
        while True:
            data = await websocket.receive_text()
            # If client updates bbox: e.g. "update_bbox:-74,40,-73,41"
            if data.startswith("update_bbox:"):
                new_bbox_str = data.split(":", 1)[1]
                try:
                    p = [float(x.strip()) for x in new_bbox_str.split(",")]
                    if len(p) == 4:
                        ws_manager.map_connections[websocket] = (p[0], p[1], p[2], p[3])
                except Exception:
                    pass
            elif data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        await ws_manager.disconnect_map(websocket)
    except Exception:
        await ws_manager.disconnect_map(websocket)


@router.websocket("/ws/player/{player_id}")
async def websocket_player_notifications(websocket: WebSocket, player_id: str):
    """
    WebSocket endpoint for real-time player push notifications (e.g. territory captured alerts).
    """
    await ws_manager.connect_player(websocket, player_id)
    try:
        while True:
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        await ws_manager.disconnect_player(websocket, player_id)
    except Exception:
        await ws_manager.disconnect_player(websocket, player_id)
