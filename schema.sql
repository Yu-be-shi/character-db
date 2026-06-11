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

    -- 楽観ロック用バージョン。版検査と +1 は DB 関数 update_character / soft_delete_character
    -- （views/10_character_write_functions.sql）が行い、各 API は関数を呼ぶだけ。
    version BIGINT NOT NULL DEFAULT 1,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_core_characters_race_id ON core_characters(race_id);

-- 一覧取得（v1_characters / API の List）は常に「生存行を created_at, id 順」で読む。
-- 削除済み行をスキャンしない部分インデックスでこのアクセスパスを直接支える。
-- ※ gender 単独のインデックスは ENUM 4 値の低カーディナリティで実用上使われないため持たない。
CREATE INDEX idx_core_characters_active_created_at
    ON core_characters (created_at, id) WHERE deleted_at IS NULL;
