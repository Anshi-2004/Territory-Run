import pytest
from httpx import AsyncClient, ASGITransport
from datetime import datetime, timezone, timedelta
from app.main import app
from tests.test_phase0_territory_math import generate_synthetic_route


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.mark.asyncio
async def test_full_mvp_workflow():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Healthcheck
        resp = await client.get("/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "healthy"

        # 2. Register Player 1 (Runner Alice)
        reg1 = await client.post("/auth/register", json={
            "email": "alice@example.com",
            "username": "AliceRunner",
            "password": "password123",
            "color_hex": "#00E5FF",
        })
        assert reg1.status_code == 201
        data1 = reg1.json()
        assert "access_token" in data1
        token1 = data1["access_token"]
        player1_id = data1["player_id"]
        headers1 = {"Authorization": f"Bearer {token1}"}

        # 3. Register Player 2 (Runner Bob)
        reg2 = await client.post("/auth/register", json={
            "email": "bob@example.com",
            "username": "BobChallenger",
            "password": "password123",
            "color_hex": "#FF007F",
        })
        assert reg2.status_code == 201
        token2 = reg2.json()["access_token"]
        player2_id = reg2.json()["player_id"]
        headers2 = {"Authorization": f"Bearer {token2}"}

        # 4. Verify /players/me
        me_resp = await client.get("/players/me", headers=headers1)
        assert me_resp.status_code == 200
        assert me_resp.json()["username"] == "AliceRunner"

        # 5. Alice starts a walking session
        start_resp = await client.post("/routes/start", json={"activity_type": "walk"}, headers=headers1)
        assert start_resp.status_code == 201
        route1_id = start_resp.json()["route_id"]

        # 6. Alice pings GPS telemetry (walking at 5 km/h)
        t0 = datetime(2026, 6, 1, 10, 0, 0, tzinfo=timezone.utc)
        alice_pings = generate_synthetic_route(
            start_lat=37.7749,
            start_lng=-122.4194,
            num_points=20,
            step_meters=20.0,
            speed_kmh=5.0,
            start_time=t0,
        )
        ping_payload = {
            "pings": [
                {"lat": p["lat"], "lng": p["lng"], "timestamp": p["timestamp"].isoformat()}
                for p in alice_pings
            ]
        }
        ping_resp1 = await client.post(f"/routes/{route1_id}/ping", json=ping_payload, headers=headers1)
        assert ping_resp1.status_code == 200
        pdata1 = ping_resp1.json()
        assert pdata1["touched_cells_count"] >= 1
        assert len(pdata1["claimed_or_conquered_cells"]) >= 1
        claimed_cells = [c["h3_index"] for c in pdata1["claimed_or_conquered_cells"]]

        # 7. Query Viewport Territory Cells
        cells_resp = await client.get("/territory/cells?bbox=-122.45,37.75,-122.40,37.80")
        assert cells_resp.status_code == 200
        owned_cells = cells_resp.json()
        assert len(owned_cells) >= 1
        assert any(c["owner_id"] == player1_id for c in owned_cells)

        # 8. Alice ends session
        end_resp1 = await client.post(f"/routes/{route1_id}/end", headers=headers1)
        assert end_resp1.status_code == 200
        assert end_resp1.json()["distance_meters"] > 0

        # 9. Anti-Cheat test: Bob tries to submit pings with 70 km/h (driving speed)
        bob_start = await client.post("/routes/start", json={"activity_type": "run"}, headers=headers2)
        route2_id = bob_start.json()["route_id"]

        speed_pings = generate_synthetic_route(
            start_lat=37.7749,
            start_lng=-122.4194,
            num_points=5,
            step_meters=100.0,
            speed_kmh=70.0,
            start_time=t0 + timedelta(hours=1),
        )
        cheat_payload = {
            "pings": [
                {"lat": p["lat"], "lng": p["lng"], "timestamp": p["timestamp"].isoformat()}
                for p in speed_pings
            ]
        }
        cheat_resp = await client.post(f"/routes/{route2_id}/ping", json=cheat_payload, headers=headers2)
        assert cheat_resp.status_code == 400
        assert "Anti-cheat violation" in cheat_resp.json()["detail"]

        # 10. Bob legitimately jogs (weight 1.3) through Alice's cells -> conquers territory!
        bob_legit_pings = generate_synthetic_route(
            start_lat=37.7749,
            start_lng=-122.4194,
            num_points=20,
            step_meters=20.0,
            speed_kmh=10.0,
            start_time=t0 + timedelta(hours=2),
        )
        bob_payload = {
            "pings": [
                {"lat": p["lat"], "lng": p["lng"], "timestamp": p["timestamp"].isoformat()}
                for p in bob_legit_pings
            ]
        }
        bob_ping_resp = await client.post(f"/routes/{route2_id}/ping", json=bob_payload, headers=headers2)
        assert bob_ping_resp.status_code == 200
        bob_deltas = bob_ping_resp.json()["claimed_or_conquered_cells"]
        # Bob conquered Alice's cells because jog weight 1.3 > 1.15 * 1.0
        assert len(bob_deltas) >= 1
        assert any(d["new_owner_id"] == player2_id and d["previous_owner_id"] == player1_id for d in bob_deltas)

        # 11. Verify Alice receives a "Territory Lost" notification
        notifs_resp = await client.get("/notifications", headers=headers1)
        assert notifs_resp.status_code == 200
        alice_notifs = notifs_resp.json()
        assert len(alice_notifs) >= 1
        assert "captured" in alice_notifs[0]["message"]
        notif_id = alice_notifs[0]["id"]

        # Mark notification as read
        read_resp = await client.post(f"/notifications/{notif_id}/read", headers=headers1)
        assert read_resp.status_code == 200

        # 12. Check City Leaderboard
        lb_resp = await client.get("/leaderboard/city")
        assert lb_resp.status_code == 200
        lb_data = lb_resp.json()
        assert len(lb_data["entries"]) >= 2
        # Bob is #1 on leaderboard
        assert lb_data["entries"][0]["player_id"] == player2_id
        assert lb_data["entries"][0]["rank"] == 1


@pytest.mark.asyncio
async def test_close_loop_territory_enclosure():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        reg = await client.post("/auth/register", json={
            "email": "looper@example.com",
            "username": "Looper",
            "password": "password123",
            "color_hex": "#00FFCC",
        })
        token = reg.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        start_resp = await client.post("/routes/start", json={"activity_type": "run"}, headers=headers)
        route_id = start_resp.json()["route_id"]

        now = datetime.now(timezone.utc)
        loop_points = [
            {"lat": 37.770, "lng": -122.420, "timestamp": now.isoformat()},
            {"lat": 37.775, "lng": -122.420, "timestamp": now.isoformat()},
            {"lat": 37.775, "lng": -122.415, "timestamp": now.isoformat()},
            {"lat": 37.770, "lng": -122.415, "timestamp": now.isoformat()},
            {"lat": 37.770, "lng": -122.420, "timestamp": now.isoformat()},
        ]

        resp = await client.post(
            f"/routes/{route_id}/close_loop",
            json={"loop_points": loop_points, "activity_type": "run"},
            headers=headers,
        )

        assert resp.status_code == 200
        data = resp.json()
        assert data["enclosed_cells_count"] >= 1
        assert data["enclosed_area_m2"] > 0
        assert len(data["captured_cells"]) >= 1
