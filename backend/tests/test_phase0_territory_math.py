import math
from datetime import datetime, timezone, timedelta
import pytest
from shapely import wkt
import h3

from app.core.territory_math import (
    DEFAULT_H3_RESOLUTION,
    DEFAULT_HALF_LIFE_DAYS,
    DEFAULT_HYSTERESIS_FACTOR,
    get_activity_weight,
    calculate_recency_decay,
    latlng_to_h3,
    h3_to_postgis_wkt,
    h3_to_geojson_geometry,
    haversine_distance_meters,
    compute_speed_kmh,
    evaluate_ownership_flip,
)
from app.core.anti_cheat import AntiCheatValidator, AntiCheatError
from app.core.engine import TerritorySimulationEngine


# Helper to generate synthetic GPS pings along a linear path
def generate_synthetic_route(
    start_lat: float,
    start_lng: float,
    num_points: int,
    step_meters: float,
    speed_kmh: float,
    start_time: datetime,
) -> list:
    """
    Generates realistic sequential GPS pings moving north-east.
    step_meters: distance between successive pings in meters
    speed_kmh: walking/running speed
    """
    speed_mps = speed_kmh / 3.6
    time_per_step_sec = step_meters / speed_mps if speed_mps > 0 else 1.0

    pings = []
    lat_deg_per_meter = 1.0 / 111320.0
    lng_deg_per_meter = 1.0 / (111320.0 * math.cos(math.radians(start_lat)))

    current_lat = start_lat
    current_lng = start_lng
    current_time = start_time

    for _ in range(num_points):
        pings.append({
            "lat": round(current_lat, 6),
            "lng": round(current_lng, 6),
            "timestamp": current_time,
        })
        # Move step_meters roughly north-east
        current_lat += (step_meters * 0.707) * lat_deg_per_meter
        current_lng += (step_meters * 0.707) * lng_deg_per_meter
        current_time += timedelta(seconds=time_per_step_sec)

    return pings


# -------------------------------------------------------------------------
# Test Cases
# -------------------------------------------------------------------------

def test_activity_weights():
    assert get_activity_weight("walk") == 1.0
    assert get_activity_weight("WALK") == 1.0
    assert get_activity_weight("jog") == 1.3
    assert get_activity_weight("run") == 1.6
    assert get_activity_weight("unknown") == 1.0


def test_recency_decay_exact_values():
    t0 = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    
    # 0 days elapsed -> 1.0
    assert calculate_recency_decay(t0, t0, half_life_days=14.0) == 1.0

    # 14 days elapsed -> exactly 0.5 (one half-life)
    t_14d = t0 + timedelta(days=14)
    decay_14d = calculate_recency_decay(t0, t_14d, half_life_days=14.0)
    assert pytest.approx(decay_14d, rel=1e-5) == 0.5

    # 28 days elapsed -> exactly 0.25 (two half-lives)
    t_28d = t0 + timedelta(days=28)
    decay_28d = calculate_recency_decay(t0, t_28d, half_life_days=14.0)
    assert pytest.approx(decay_28d, rel=1e-5) == 0.25

    # 7 days elapsed -> 2^(-0.5) = 1/sqrt(2) ≈ 0.7071
    t_7d = t0 + timedelta(days=7)
    decay_7d = calculate_recency_decay(t0, t_7d, half_life_days=14.0)
    assert pytest.approx(decay_7d, rel=1e-4) == math.sqrt(0.5)


def test_postgis_wkt_and_geojson_geometry():
    lat, lng = 40.785091, -73.968285  # Central Park, NY
    cell = latlng_to_h3(lat, lng, resolution=DEFAULT_H3_RESOLUTION)

    # PostGIS WKT
    wkt_str = h3_to_postgis_wkt(cell)
    assert wkt_str.startswith("SRID=4326;POLYGON((")
    assert wkt_str.endswith("))")

    # Validate with Shapely
    pure_wkt = wkt_str.replace("SRID=4326;", "")
    polygon = wkt.loads(pure_wkt)
    assert polygon.is_valid
    assert not polygon.is_empty
    # Hexagon boundary has 6 vertices + 1 closing vertex = 7 coordinates
    assert len(polygon.exterior.coords) == 7

    # GeoJSON
    geojson = h3_to_geojson_geometry(cell)
    assert geojson["type"] == "Polygon"
    assert len(geojson["coordinates"][0]) == 7


def test_hysteresis_ownership_flip_logic():
    # 1. Unclaimed cell -> challenger claims immediately
    flipped, owner, score = evaluate_ownership_flip(
        current_owner_id=None,
        current_owner_score=0.0,
        challenger_id="playerA",
        challenger_score=1.0,
    )
    assert flipped is True
    assert owner == "playerA"
    assert score == 1.0

    # 2. Challenger ties or is within 15% -> NO flip (1.0 vs 1.10 is < 1.15 * 1.0)
    flipped, owner, score = evaluate_ownership_flip(
        current_owner_id="playerA",
        current_owner_score=1.0,
        challenger_id="playerB",
        challenger_score=1.10,
        hysteresis_factor=1.15,
    )
    assert flipped is False
    assert owner == "playerA"

    # 3. Challenger is exactly at 1.15x -> strictly > required, so NO flip
    flipped, owner, score = evaluate_ownership_flip(
        current_owner_id="playerA",
        current_owner_score=1.0,
        challenger_id="playerB",
        challenger_score=1.15,
        hysteresis_factor=1.15,
    )
    assert flipped is False

    # 4. Challenger exceeds 15% (e.g. 1.16 or jogger weight 1.30 > 1.15) -> FLIP!
    flipped, owner, score = evaluate_ownership_flip(
        current_owner_id="playerA",
        current_owner_score=1.0,
        challenger_id="playerB",
        challenger_score=1.30,
        hysteresis_factor=1.15,
    )
    assert flipped is True
    assert owner == "playerB"
    assert score == 1.30


def test_anti_cheat_speed_rejection():
    validator = AntiCheatValidator(max_speed_kmh=25.0)
    t0 = datetime(2026, 6, 1, 8, 0, 0, tzinfo=timezone.utc)

    # Valid running route at 12 km/h
    valid_pings = generate_synthetic_route(
        start_lat=37.7749,
        start_lng=-122.4194,
        num_points=10,
        step_meters=20.0,
        speed_kmh=12.0,
        start_time=t0,
    )
    validated = validator.validate_pings(valid_pings)
    assert len(validated) == 10

    # Cheat attempt: Car speed at 60 km/h
    speeding_pings = generate_synthetic_route(
        start_lat=37.7749,
        start_lng=-122.4194,
        num_points=5,
        step_meters=100.0,
        speed_kmh=60.0,
        start_time=t0,
    )
    with pytest.raises(AntiCheatError) as exc_info:
        validator.validate_pings(speeding_pings)
    assert "Excessive speed detected" in str(exc_info.value)


def test_anti_cheat_teleport_rejection():
    validator = AntiCheatValidator()
    t0 = datetime(2026, 6, 1, 8, 0, 0, tzinfo=timezone.utc)

    # Two points 5 km apart with 10 minutes interval (speed is low, but teleporting across non-adjacent cells)
    teleport_pings = [
        {"lat": 37.7749, "lng": -122.4194, "timestamp": t0},
        {"lat": 37.8200, "lng": -122.4194, "timestamp": t0 + timedelta(minutes=15)},
    ]
    with pytest.raises(AntiCheatError) as exc_info:
        validator.validate_pings(teleport_pings)
    assert "Discontinuous cell jump detected" in str(exc_info.value)


def test_full_territory_conquest_simulation():
    """
    End-to-end simulation of Section 3 & 6:
      - Player 1 (Alice) walks through cells, claiming them.
      - Player 2 (Bob) walks through the same cells; does not take over because 1.0 is not > 1.15 * 1.0.
      - Bob jogs through the cells (weight 1.3); flips ownership to Bob.
      - Alice receives displacement push notifications.
      - Leaderboard reflects accurate territory areas.
    """
    engine = TerritorySimulationEngine(
        h3_resolution=DEFAULT_H3_RESOLUTION,
        half_life_days=14.0,
        hysteresis_factor=1.15,
    )

    p1_id = "player-alice-uuid"
    p2_id = "player-bob-uuid"
    engine.register_player(p1_id, "Alice", color_hex="#FF3366")
    engine.register_player(p2_id, "Bob", color_hex="#33CC66")

    base_time = datetime(2026, 7, 1, 7, 0, 0, tzinfo=timezone.utc)

    # 1. Alice walks along a 500m path (speed 5 km/h)
    alice_pings = generate_synthetic_route(
        start_lat=40.7850,
        start_lng=-73.9682,
        num_points=25,
        step_meters=20.0,
        speed_kmh=5.0,
        start_time=base_time,
    )

    res1 = engine.process_route_pings(
        player_id=p1_id,
        activity_type="walk",
        pings=alice_pings,
        current_time=base_time + timedelta(minutes=10),
    )

    touched_cells = res1["touched_cells"]
    assert len(touched_cells) >= 2
    # All touched cells are now owned by Alice
    for cell in touched_cells:
        assert engine.territory_cells[cell]["owner_id"] == p1_id
    assert engine.players[p1_id]["total_territory_area"] > 0
    alice_initial_area = engine.players[p1_id]["total_territory_area"]

    # 2. Bob walks the exact same route immediately after
    bob_walk_time = base_time + timedelta(minutes=30)
    bob_walk_pings = generate_synthetic_route(
        start_lat=40.7850,
        start_lng=-73.9682,
        num_points=25,
        step_meters=20.0,
        speed_kmh=5.0,
        start_time=bob_walk_time,
    )

    res2 = engine.process_route_pings(
        player_id=p2_id,
        activity_type="walk",
        pings=bob_walk_pings,
        current_time=bob_walk_time + timedelta(minutes=10),
    )

    # Ownership should NOT have flipped because Bob (walk=1.0) <= 1.15 * Alice (1.0)
    assert len(res2["ownership_changes"]) == 0
    for cell in touched_cells:
        assert engine.territory_cells[cell]["owner_id"] == p1_id

    # 3. Bob now jogs (weight 1.3) through the same route
    bob_jog_time = base_time + timedelta(hours=2)
    bob_jog_pings = generate_synthetic_route(
        start_lat=40.7850,
        start_lng=-73.9682,
        num_points=25,
        step_meters=20.0,
        speed_kmh=9.0,
        start_time=bob_jog_time,
    )

    res3 = engine.process_route_pings(
        player_id=p2_id,
        activity_type="jog",
        pings=bob_jog_pings,
        current_time=bob_jog_time + timedelta(minutes=10),
    )

    # Bob's score accumulates (1.0 from walk + 1.3 from jog = 2.3)
    # 2.3 > 1.15 * 1.0 (Alice's score) -> Ownership MUST FLIP to Bob!
    assert len(res3["ownership_changes"]) > 0
    for cell in touched_cells:
        assert engine.territory_cells[cell]["owner_id"] == p2_id

    # Alice's territory area drops, Bob's territory area rises
    assert engine.players[p1_id]["total_territory_area"] == 0.0
    assert engine.players[p2_id]["total_territory_area"] >= alice_initial_area

    # 4. Check Displaced Player notification was enqueued for Alice
    assert len(engine.notification_queue) > 0
    alice_notifs = [n for n in engine.notification_queue if n["recipient_id"] == p1_id]
    assert len(alice_notifs) > 0
    assert "captured" in alice_notifs[0]["message"]

    # 5. Check Leaderboard ranking
    lb = engine.get_leaderboard()
    assert len(lb) == 2
    assert lb[0]["player_id"] == p2_id  # Bob is Rank 1
    assert lb[1]["player_id"] == p1_id  # Alice is Rank 2
