from fastapi import APIRouter, Depends, HTTPException, status
from typing import List
from app.schemas import NotificationResponse
from app.api.deps import get_current_player
from app.db import store

router = APIRouter(prefix="/notifications", tags=["Notifications"])


@router.get("", response_model=List[NotificationResponse])
async def list_notifications(current_player: dict = Depends(get_current_player)):
    """Fetch all notifications and displaced alerts for the current player."""
    player_id = current_player["id"]
    notifs = await store.get_player_notifications(player_id)
    return [
        NotificationResponse(
            id=n["id"],
            title=n["title"],
            message=n["message"],
            h3_index=n.get("h3_index"),
            displaced_by=n.get("displaced_by"),
            created_at=n["created_at"],
            is_read=n.get("is_read", False),
        )
        for n in notifs
    ]


@router.post("/{notification_id}/read")
async def mark_as_read(
    notification_id: str,
    current_player: dict = Depends(get_current_player),
):
    """Mark a notification as read."""
    player_id = current_player["id"]
    success = await store.mark_notification_read(player_id, notification_id)
    if not success:
        raise HTTPException(status_code=404, detail="Notification not found")
    return {"status": "ok", "marked_read": notification_id}
