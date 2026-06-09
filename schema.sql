-- キャラクターDBのあるべきスキーマ定義
-- このファイルを編集して `make migration name=<説明>` を実行すると
-- migrations/ に差分SQLが自動生成される

CREATE TYPE gender_enum AS ENUM ('male', 'female', 'other', 'unknown');

CREATE TABLE races (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE core_characters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    description TEXT,

    race_id UUID NOT NULL REFERENCES races(id),
    gender gender_enum NOT NULL DEFAULT 'unknown',

    birth_date DATE,
    birth_place VARCHAR(150),

    height_cm SMALLINT CHECK (height_cm > 0),
    weight_kg SMALLINT CHECK (weight_kg > 0),
    body_fat_percentage NUMERIC(4, 1) CHECK (body_fat_percentage >= 0 AND body_fat_percentage <= 100),

    size_top SMALLINT CHECK (size_top > 0),
    size_middle SMALLINT CHECK (size_middle > 0),
    size_bottom SMALLINT CHECK (size_bottom > 0),

    -- 楽観ロック用バージョン。更新のたびに +1 する（API が WHERE version=? で競合検知）。
    version BIGINT NOT NULL DEFAULT 1,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_core_characters_race_id ON core_characters(race_id);
CREATE INDEX idx_core_characters_gender ON core_characters(gender);
