"""
Territory Run — Phase 0 Territory Math & Spatial Validation Runner
Executes comprehensive synthetic GPS route simulations to validate:
  - H3 spatial indexing resolution 9 snapping
  - Exponential recency decay half-life (14 days)
  - Ownership flip 15% hysteresis rule
  - Anti-cheat speed & teleportation checks
  - PostGIS Polygon WKT geometry formatting
"""
import sys
import os
from datetime import datetime, timezone, timedelta
from shapely import wkt
import h3

# Ensure app is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__))))

from app.core.territory_math import (
    DEFAULT_H3_RESOLUTION,
    DEFAULT_HALF_LIFE_DAYS,
    DEFAULT_HYSTERESIS_FACTOR,
    latlng_to_h3,
    h3_to_postgis_wkt,
    calculate_recency_decay,
    get_activity_weight,
    evaluate_ownership_flip,
)
from app.core.anti_cheat import AntiCheatValidator, AntiCheatError
from app.core.engine import TerritorySimulationEngine
from tests.test_phase0_territory_math import generate_synthetic_route


def print_banner(text: str):
    print("\n" + "=" * 65)
    print(f"  {text}")
    print("=" * 65)


def run_phase0_validation():
    print_banner("PHASE 0: H3 + PostGIS Territory Math Validation")

    # 1. H3 Indexing & PostGIS Geometry
    print("\n[1/5] Validating H3 Resolution 9 and PostGIS WKT Generation...")
    sample_lat, sample_lng = 40.785091, -73.968285
    cell = latlng_to_h3(sample_lat, sample_lng, resolution=DEFAULT_H3_RESOLUTION)
    wkt_str = h3_to_postgis_wkt(cell)
    pure_wkt = wkt_str.replace("SRID=4326;", "")
    geom = wkt.loads(pure_wkt)

    print(f"  * Sample Point: ({sample_lat}, {sample_lng})")
    print(f"  * H3 Index (Res 9): {cell}")
    print(f"  * PostGIS WKT: {wkt_str[:45]}...")
    print(f"  * Valid Geometry: {geom.is_valid} (exterior coords: {len(geom.exterior.coords)})")
    assert geom.is_valid and len(geom.exterior.coords) == 7
    print("  --> PASS: H3 to PostGIS Polygon geometry verified.")

    # 2. Recency Decay
    print("\n[2/5] Validating Exponential Half-Life (14 Days) Decay Curve...")
    now = datetime(2026, 6, 1, 12, 0, 0, tzinfo=timezone.utc)
    decay_0 = calculate_recency_decay(now, now, 14.0)
    decay_7 = calculate_recency_decay(now, now + timedelta(days=7), 14.0)
    decay_14 = calculate_recency_decay(now, now + timedelta(days=14), 14.0)
    decay_28 = calculate_recency_decay(now, now + timedelta(days=28), 14.0)

    print(f"  * t = 0 days:  decay = {decay_0:.4f} (expected 1.0000)")
    print(f"  * t = 7 days:  decay = {decay_7:.4f} (expected ~0.7071)")
    print(f"  * t = 14 days: decay = {decay_14:.4f} (expected 0.5000)")
    print(f"  * t = 28 days: decay = {decay_28:.4f} (expected 0.2500)")
    assert abs(decay_14 - 0.5) < 1e-5
    assert abs(decay_28 - 0.25) < 1e-5
    print("  --> PASS: Recency decay math matches 14-day exponential half-life.")

    # 3. Ownership Flip & Hysteresis Rule
    print("\n[3/5] Validating 15% Ownership Hysteresis Buffer Rule...")
    # Challenger score 1.10 vs Owner 1.00 (within 15%)
    flipped, owner, _ = evaluate_ownership_flip("PlayerA", 1.00, "PlayerB", 1.10, 1.15)
    print(f"  * Challenger 1.10 vs Owner 1.00 (10% increase): Flipped = {flipped} (Expected False)")
    assert not flipped and owner == "PlayerA"

    # Challenger score 1.25 vs Owner 1.00 (exceeds 15%)
    flipped, owner, score = evaluate_ownership_flip("PlayerA", 1.00, "PlayerB", 1.25, 1.15)
    print(f"  * Challenger 1.25 vs Owner 1.00 (25% increase): Flipped = {flipped}, New Owner = {owner} (Expected True, PlayerB)")
    assert flipped and owner == "PlayerB"
    print("  --> PASS: Ownership flip strictly enforces 15% hysteresis buffer.")

    # 4. Anti-Cheat Engine Checks
    print("\n[4/5] Validating Anti-Cheat Checks (Speed Limit & Teleportation)...")
    validator = AntiCheatValidator(max_speed_kmh=25.0)
    t0 = datetime(2026, 6, 1, 9, 0, 0, tzinfo=timezone.utc)

    # Valid run
    valid_route = generate_synthetic_route(37.7749, -122.4194, 10, 20.0, 11.5, t0)
    validated = validator.validate_pings(valid_route)
    print(f"  * Valid 11.5 km/h run: {len(validated)} pings accepted.")

    # Speed violation (driving / cycling spoofing at 55 km/h)
    spoof_route = generate_synthetic_route(37.7749, -122.4194, 5, 100.0, 55.0, t0)
    caught_speed = False
    try:
        validator.validate_pings(spoof_route)
    except AntiCheatError as e:
        caught_speed = True
        print(f"  * Caught vehicle speed spoof: '{e}'")
    assert caught_speed

    # Teleport violation (discontinuous cell jump)
    teleport_route = [
        {"lat": 37.7749, "lng": -122.4194, "timestamp": t0},
        {"lat": 37.8500, "lng": -122.4194, "timestamp": t0 + timedelta(minutes=5)},
    ]
    caught_teleport = False
    try:
        validator.validate_pings(teleport_route)
    except AntiCheatError as e:
        caught_teleport = True
        print(f"  * Caught teleportation attempt: '{e}'")
    assert caught_teleport
    print("  --> PASS: Anti-cheat rules successfully block speeders and teleporters.")

    # 5. Full Simulation with Displaced Player Notifications
    print("\n[5/5] Validating End-to-End Simulation & Displaced Player Push Alerts...")
    engine = TerritorySimulationEngine()
    engine.register_player("user_1", "RunnerOne", "#00F0FF")
    engine.register_player("user_2", "RunnerTwo", "#FF0055")

    # Step A: RunnerOne claims territory (walk, weight 1.0)
    pings_1 = generate_synthetic_route(40.7580, -73.9855, 30, 20.0, 5.0, t0)
    res_1 = engine.process_route_pings("user_1", "walk", pings_1, t0 + timedelta(minutes=15))
    print(f"  * RunnerOne completed walk: {len(res_1['touched_cells'])} cells claimed.")
    assert len(res_1["touched_cells"]) > 0

    # Step B: RunnerTwo contests cells with jog (weight 1.3) -> takes over
    t_contest = t0 + timedelta(hours=1)
    pings_2 = generate_synthetic_route(40.7580, -73.9855, 30, 20.0, 10.0, t_contest)
    res_2 = engine.process_route_pings("user_2", "jog", pings_2, t_contest + timedelta(minutes=15))
    print(f"  * RunnerTwo jogged route: {len(res_2['ownership_changes'])} cells conquered!")
    assert len(res_2["ownership_changes"]) > 0

    # Step C: Check displaced notifications
    print(f"  * Displaced notifications enqueued: {len(engine.notification_queue)}")
    assert len(engine.notification_queue) > 0
    notif = engine.notification_queue[0]
    print(f"    - Recipient: {notif['recipient_id']} (RunnerOne)")
    print(f"    - Title: {notif['title']}")
    print(f"    - Message: {notif['message']}")

    # Step D: Check leaderboard
    lb = engine.get_leaderboard()
    print("\n  Leaderboard Standings:")
    for entry in lb:
        print(f"    #{entry['rank']} {entry['username']}: {entry['total_territory_area_km2']} km² ({entry['total_territory_area_m2']} m²)")

    assert lb[0]["player_id"] == "user_2"
    print("\n--> ALL PHASE 0 ACCEPTANCE CRITERIA VERIFIED SUCCESSFULLY! <--\n")


if __name__ == "__main__":
    run_phase0_validation()
