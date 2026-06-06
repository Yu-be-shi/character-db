-- Create enum type "gender_enum"
CREATE TYPE "gender_enum" AS ENUM ('male', 'female', 'other', 'unknown');
-- Create "races" table
CREATE TABLE "races" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "name" character varying(50) NOT NULL,
  PRIMARY KEY ("id"),
  CONSTRAINT "races_name_key" UNIQUE ("name")
);
-- Create "core_characters" table
CREATE TABLE "core_characters" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "name" character varying(100) NOT NULL,
  "description" text NULL,
  "race_id" uuid NOT NULL,
  "gender" "gender_enum" NOT NULL DEFAULT 'unknown',
  "birth_date" date NULL,
  "birth_place" character varying(150) NULL,
  "height_cm" smallint NULL,
  "weight_kg" smallint NULL,
  "body_fat_percentage" numeric(4,1) NULL,
  "size_top" smallint NULL,
  "size_middle" smallint NULL,
  "size_bottom" smallint NULL,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
  "deleted_at" timestamptz NULL,
  PRIMARY KEY ("id"),
  CONSTRAINT "core_characters_race_id_fkey" FOREIGN KEY ("race_id") REFERENCES "races" ("id") ON UPDATE NO ACTION ON DELETE NO ACTION,
  CONSTRAINT "core_characters_body_fat_percentage_check" CHECK ((body_fat_percentage >= (0)::numeric) AND (body_fat_percentage <= (100)::numeric)),
  CONSTRAINT "core_characters_height_cm_check" CHECK (height_cm > 0),
  CONSTRAINT "core_characters_size_bottom_check" CHECK (size_bottom > 0),
  CONSTRAINT "core_characters_size_middle_check" CHECK (size_middle > 0),
  CONSTRAINT "core_characters_size_top_check" CHECK (size_top > 0),
  CONSTRAINT "core_characters_weight_kg_check" CHECK (weight_kg > 0)
);
-- Create index "idx_core_characters_gender" to table: "core_characters"
CREATE INDEX "idx_core_characters_gender" ON "core_characters" ("gender");
-- Create index "idx_core_characters_race_id" to table: "core_characters"
CREATE INDEX "idx_core_characters_race_id" ON "core_characters" ("race_id");
-- Drop old "characters" table (replaced by core_characters + races)
DROP TABLE IF EXISTS "characters";
-- Create view "v1_characters" (deleted_at IS NULL filter for soft-delete)
CREATE VIEW "v1_characters" AS
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
