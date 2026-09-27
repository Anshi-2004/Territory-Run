from fastapi import APIRouter, HTTPException, status
from app.schemas import RegisterRequest, LoginRequest, TokenResponse
from app.core.security import get_password_hash, verify_password, create_access_token
from app.db import store

router = APIRouter(prefix="/auth", tags=["Auth"])


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(req: RegisterRequest):
    """
    Registers a new player with email, username, and password.
    Returns authentication JWT token.
    """
    try:
        pw_hash = get_password_hash(req.password)
        player = await store.create_player(
            email=req.email,
            username=req.username,
            password_hash=pw_hash,
            color_hex=req.color_hex or "#3388FF",
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )

    token = create_access_token(subject=player["id"])
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        player_id=player["id"],
        username=player["username"],
        color_hex=player["color_hex"],
    )


@router.post("/login", response_model=TokenResponse)
async def login(req: LoginRequest):
    """
    Authenticates a player with email & password, returning JWT bearer token.
    """
    player = await store.get_player_by_email(req.email)
    if not player or not verify_password(req.password, player["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    token = create_access_token(subject=player["id"])
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        player_id=player["id"],
        username=player["username"],
        color_hex=player["color_hex"],
    )
