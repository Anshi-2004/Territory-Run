-- Territory Run Database Schema
-- Matches Section 4 of Build Brief exactly

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    color_hex TEXT NOT NULL DEFAULT '#3388FF',
    clan_id UUID,
    total_territory_area NUMERIC DEFAULT 0,
    coins INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID REFERENCES players(id),
    activity_type TEXT CHECK (activity_type IN ('walk','jog','run')),
    path GEOMETRY(LineString, 4326),
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    distance_m NUMERIC
);

CREATE TABLE IF NOT EXISTS territory_cells (
    h3_index TEXT PRIMARY KEY,
    owner_id UUID REFERENCES players(id),
    owner_score NUMERIC NOT NULL DEFAULT 0,
    last_claimed_at TIMESTAMPTZ,
    geom GEOMETRY(Polygon, 4326)
);

CREATE TABLE IF NOT EXISTS cell_contests (
    h3_index TEXT REFERENCES territory_cells(h3_index),
    player_id UUID REFERENCES players(id),
    score NUMERIC NOT NULL DEFAULT 0,
    last_activity_at TIMESTAMPTZ,
    PRIMARY KEY (h3_index, player_id)
);

CREATE INDEX IF NOT EXISTS idx_routes_path ON routes USING GIST (path);
CREATE INDEX IF NOT EXISTS idx_cells_geom ON territory_cells USING GIST (geom);

-- Extra table for push alerts / notification feeds in MVP
CREATE TABLE IF NOT EXISTS player_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID REFERENCES players(id),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    h3_index TEXT,
    displaced_by UUID REFERENCES players(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    is_read BOOLEAN DEFAULT false
);
