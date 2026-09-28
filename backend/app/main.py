from datetime import datetime, timezone
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.config import settings
from app.api.auth import router as auth_router
from app.api.players import router as players_router
from app.api.routes import router as routes_router
from app.api.territory import router as territory_router
from app.api.leaderboard import router as leaderboard_router
from app.api.notifications import router as notifications_router
from app.api.websocket import router as ws_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Initialize cache / spatial tables if needed
    yield
    # Shutdown


app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="Territory Run - GPS-based real-time territory conquest game backend API",
    lifespan=lifespan,
)

# CORS Middleware (supports mobile app and web preview)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# API Routers
app.include_router(auth_router)
app.include_router(players_router)
app.include_router(routes_router)
app.include_router(territory_router)
app.include_router(leaderboard_router)
app.include_router(notifications_router)
app.include_router(ws_router)


@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "Territory Run API",
        "version": settings.VERSION,
        "h3_resolution": settings.H3_RESOLUTION,
        "half_life_days": settings.RECENCY_HALF_LIFE_DAYS,
        "server_time": datetime.now(timezone.utc).isoformat(),
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
