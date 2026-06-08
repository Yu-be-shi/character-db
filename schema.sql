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

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_core_characters_race_id ON core_characters(race_id);
CREATE INDEX idx_core_characters_gender ON core_characters(gender);

-- v1_characters: 複数 API（Go / Python 等）が共有する安定読み取りコントラクト（v1）。
-- ・soft-delete（deleted_at IS NULL）でフィルタ済みの行のみを返す
-- ・races を JOIN して race 名を展開する
-- ・gender に応じた size_top のラベルを付与する
-- このビューもスキーマの一部なので schema.sql に必ず宣言する（Atlas はここに
-- 無いオブジェクトを差分で DROP するため、ビューはマイグレーションに手書きしないこと）。
CREATE VIEW v1_characters AS
SELECT
    c.id,
    c.name,
    c.description,
    r.name AS race,
    c.gender,
    c.birth_date,
    c.birth_place,
    c.height_cm,
    c.weight_kg,
    c.body_fat_percentage,
    CASE
        WHEN c.gender = 'female' THEN 'バスト'
        WHEN c.gender = 'male'   THEN 'チェスト'
        ELSE '胸囲'
    END AS size_top_label,
    c.size_top    AS top_value,
    c.size_middle AS waist_value,
    c.size_bottom AS hip_value,
    c.created_at
FROM core_characters c
JOIN races r ON c.race_id = r.id
WHERE c.deleted_at IS NULL;
