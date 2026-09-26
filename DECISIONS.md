# Territory Run — Architectural & Game Design Decisions

This document records the foundational parameters, architectural choices, and configuration defaults established for **Territory Run**. These can be tuned or migrated as the project evolves.

---

## 1. Core Game Rules & Spatial Indexing

| Parameter | Default Value | Rationale & Notes |
|---|---|---|
| **H3 Resolution** | `9` (edge length ≈ 174m, area ≈ 0.1 km²) | Balances pedestrian fidelity with database storage and network bandwidth. Resolution 9 hexagons are optimal for jogging and walking routes without creating millions of microscopic cells. Revisit to resolution 8 (broader cells) or 10 (finer granularity) based on playtesting. |
| **Recency Decay Half-Life** | `14 days` (`1,209,600` seconds) | Activity scores decay exponentially via $\lambda = \frac{\ln(2)}{t_{1/2}}$. A 14-day half-life rewards active defense and regular running while giving players a fair grace period before territory becomes vulnerable. |
| **Ownership-Flip Hysteresis Buffer** | `15%` (`1.15x`) | A challenger's score on a cell must strictly exceed `1.15 * current_owner_score` to flip ownership. This prevents rapid flickering and flip-flopping caused by GPS noise or parallel runs. |
| **Activity Weight Multipliers** | Walk: `1.0`<br>Jog: `1.3`<br>Run: `1.6` | Rewards higher aerobic exertion while keeping the game accessible to walkers. |
| **Speed Anti-Cheat Ceiling** | `25.0 km/h` sustained | Pedestrian running cutoff. Segments implying sustained speeds over 25 km/h are flagged or rejected to prevent cycling/driving spoofing in v1. |

---

## 2. Infrastructure & Tile Providers

| Component | Default Selection | Notes & Alternatives |
|---|---|---|
| **Map Rendering** | `flutter_map` + OpenStreetMap (OSM) tile servers | Fully free and open-source. Requires zero paid API keys or credit cards. Attribution included per OSM guidelines. For heavy production traffic, self-host via OpenMapTiles + TileServer GL. |
| **Geospatial Database** | PostgreSQL 16 + PostGIS 3.4 | Industry-standard spatial SQL for high-performance geometry queries, spatial indexing (GIST), and polygon boundaries. |
| **Fast In-Memory Cache** | Redis / Valkey 7+ | Caches hot cell contest scores, real-time leaderboard sorted sets, and handles pub/sub for WebSocket broadcasts. |
| **Authentication** | Self-rolled JWT (HMAC-SHA256, bcrypt) | Email/Password login. Eliminates vendor lock-in and eliminates paid Apple/Google developer accounts needed for social login during development and MVP. |
| **Push Notifications** | FCM / In-App Notification Feed fallback | In v1 development and MVP testing, alerts are routed to in-app event log and websockets; FCM credentials configured for device push notifications. |
