from fastapi import APIRouter, Query, HTTPException, status
from typing import List, Optional
from app.schemas import TerritoryCellResponse, CellDetailResponse
from app.db import store

router = APIRouter(prefix="/territory", tags=["Territory"])


@router.get("/cells", response_model=List[TerritoryCellResponse])
async def get_cells_in_viewport(
    bbox: Optional[str] = Query(
        None,
        description="Comma-separated bounding box: minLng,minLat,maxLng,maxLat",
    ),
    minLng: Optional[float] = None,
    minLat: Optional[float] = None,
    maxLng: Optional[float] = None,
    maxLat: Optional[float] = None,
):
    """
    Returns all owned territory cells within the requested map viewport.
    Accepts either 'bbox' parameter or individual minLng, minLat, maxLng, maxLat.
    """
    if bbox:
        try:
            parts = [float(x.strip()) for x in bbox.split(",")]
            if len(parts) == 4:
                minLng, minLat, maxLng, maxLat = parts
            else:
                raise ValueError()
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid bbox format. Expected: minLng,minLat,maxLng,maxLat",
            )

    # Defaults to entire globe if not constrained
    minLng = minLng if minLng is not None else -180.0
    minLat = minLat if minLat is not None else -90.0
    maxLng = maxLng if maxLng is not None else 180.0
    maxLat = maxLat if maxLat is not None else 90.0

    cells = await store.get_cells_in_bbox(minLng, minLat, maxLng, maxLat)
    return [
        TerritoryCellResponse(
            h3_index=c["h3_index"],
            owner_id=c["owner_id"],
            owner_username=c["owner_username"],
            owner_color_hex=c["owner_color_hex"],
            owner_score=c["owner_score"],
            last_claimed_at=c["last_claimed_at"],
            geojson=c["geojson"],
        )
        for c in cells
    ]


@router.get("/cell/{h3_index}", response_model=CellDetailResponse)
async def get_cell_detail(h3_index: str):
    """
    Returns full ownership details, boundary polygon, and contestant scores for a given H3 cell.
    """
    detail = await store.get_cell_detail(h3_index)
    if not detail:
        raise HTTPException(status_code=404, detail="Cell not found or invalid H3 index")

    return CellDetailResponse(**detail)
