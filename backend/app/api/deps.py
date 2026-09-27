from fastapi import Depends, HTTPException, status
from app.core.security import oauth2_scheme, decode_access_token
from app.db import store


async def get_current_player(token: str = Depends(oauth2_scheme)) -> dict:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    player_id = decode_access_token(token)
    if not player_id:
        raise credentials_exception

    player = await store.get_player_by_id(player_id)
    if not player:
        raise credentials_exception

    return player
