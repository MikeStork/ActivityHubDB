-- =========================================
-- ActivityHub - PostgreSQL schema
-- =========================================

-- Opcjonalnie: UUID
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =========================================
-- ENUMS
-- =========================================

CREATE TYPE user_role AS ENUM (
    'user',
    'moderator',
    'admin'
);

CREATE TYPE activity_status AS ENUM (
    'draft',
    'open',
    'full',
    'ongoing',
    'finished',
    'cancelled'
);

CREATE TYPE participation_status AS ENUM (
    'joined',
    'waitlist',
    'left',
    'removed'
);

-- =========================================
-- USERS
-- =========================================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,

    first_name VARCHAR(100),
    last_name VARCHAR(100),

    role user_role NOT NULL DEFAULT 'user',

    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,

    profile_image_url TEXT,
    bio TEXT,

    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =========================================
-- ACTIVITIES / ROOMS
-- =========================================

CREATE TABLE activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    title VARCHAR(150) NOT NULL,
    description TEXT,

    status activity_status NOT NULL DEFAULT 'draft',

    -- termin
    activity_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME,

    -- limit uczestników
    max_participants INTEGER,
    CHECK (max_participants IS NULL OR max_participants > 0),

    -- lokalizacja - tekstowa
    place_name VARCHAR(255),         -- np. "Pasaż Grunwaldzki", "Boisko PWr"
    address_line VARCHAR(255),       -- np. "pl. Grunwaldzki 22"
    city VARCHAR(100),
    postal_code VARCHAR(20),
    country VARCHAR(100) DEFAULT 'Poland',

    -- lokalizacja - mapowa
    latitude NUMERIC(9,6),
    longitude NUMERIC(9,6),

    -- opcjonalne metadane z OpenStreetMap / Nominatim / Overpass
    osm_place_id BIGINT,
    osm_osm_type VARCHAR(10),        -- np. node / way / relation
    osm_osm_id BIGINT,
    osm_display_name TEXT,

    -- opcjonalny gotowy link
    external_map_url TEXT,

    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),

    CHECK (
        (latitude IS NULL AND longitude IS NULL)
        OR
        (latitude IS NOT NULL AND longitude IS NOT NULL)
    ),

    CHECK (
        latitude IS NULL OR (latitude >= -90 AND latitude <= 90)
    ),

    CHECK (
        longitude IS NULL OR (longitude >= -180 AND longitude <= 180)
    ),

    CHECK (
        end_time IS NULL OR end_time > start_time
    )
);

-- =========================================
-- PARTICIPANTS
-- =========================================

CREATE TABLE activity_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    participation_status participation_status NOT NULL DEFAULT 'joined',

    joined_at TIMESTAMP NOT NULL DEFAULT NOW(),

    UNIQUE (activity_id, user_id)
);

-- =========================================
-- TAGS (opcjonalnie, ale bardzo przydatne)
-- =========================================

CREATE TABLE tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE activity_tags (
    activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (activity_id, tag_id)
);

-- =========================================
-- INDEXES
-- =========================================

CREATE INDEX idx_activities_creator_id ON activities(creator_id);
CREATE INDEX idx_activities_status ON activities(status);
CREATE INDEX idx_activities_date ON activities(activity_date);
CREATE INDEX idx_activities_city ON activities(city);
CREATE INDEX idx_activities_lat_lon ON activities(latitude, longitude);

CREATE INDEX idx_activity_participants_activity_id ON activity_participants(activity_id);
CREATE INDEX idx_activity_participants_user_id ON activity_participants(user_id);
CREATE INDEX idx_activity_participants_status ON activity_participants(participation_status);

-- =========================================
-- UPDATED_AT trigger
-- =========================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_activities_updated_at
BEFORE UPDATE ON activities
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =========================================
-- VIEW z gotowym linkiem do OpenStreetMap
-- =========================================

CREATE OR REPLACE VIEW activities_with_osm_link AS
SELECT
    a.*,
    CASE
        WHEN a.latitude IS NOT NULL AND a.longitude IS NOT NULL THEN
            'https://www.openstreetmap.org/?mlat=' || a.latitude ||
            '&mlon=' || a.longitude ||
            '#map=16/' || a.latitude || '/' || a.longitude
        ELSE NULL
    END AS openstreetmap_url
FROM activities a;