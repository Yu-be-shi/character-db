-- DB 関数・トリガー・ビューの「振る舞い」テスト（CI 専用）。
--
-- 適用テスト（atlas → views → seeds）が通った後の DB に対して psql で実行する。
-- 複数 API が依存するエラー契約（CH404 / CH412）と不変条件（version +1・updated_at
-- 自動更新・論理削除の読み書き）をリグレッション検知する。
-- すべての検査が通れば正常終了し、失敗時は例外で psql が非 0 終了する（ON_ERROR_STOP=1）。
--
-- ※ 本番 DB に流しても作ったデータを自分で消す設計だが、実行は CI のテスト DB のみを想定。

DO $$
DECLARE
    v_race_id    UUID;
    v_char_id    UUID;
    v_res        core_characters;
    v_count      INT;
    v_caught     BOOLEAN;
BEGIN
    -- 準備: テスト専用の race とキャラクター。
    INSERT INTO races (name) VALUES ('_behavior_test_race') RETURNING id INTO v_race_id;
    INSERT INTO core_characters (name, race_id, gender)
        VALUES ('_behavior_test_char', v_race_id, 'female')
        RETURNING id INTO v_char_id;

    -- 1. update_character: 正しい version で更新 → version 1→2。
    --   （updated_at トリガーの前進はトランザクション内では NOW() が固定で観測できないため、
    --     この DO ブロックの外＝別トランザクションで検査する。末尾参照。）
    v_res := update_character(v_char_id, 1, '_renamed', NULL, v_race_id, 'female',
                              NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    IF v_res.version <> 2 THEN
        RAISE EXCEPTION 'update_character: version が +1 されていない (got %)', v_res.version;
    END IF;
    IF v_res.name <> '_renamed' THEN
        RAISE EXCEPTION 'update_character: name が更新されていない';
    END IF;

    -- 2. update_character: 古い version → SQLSTATE CH412（楽観ロック競合）。
    v_caught := FALSE;
    BEGIN
        PERFORM update_character(v_char_id, 1, 'x', NULL, v_race_id, 'female',
                                 NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    EXCEPTION WHEN SQLSTATE 'CH412' THEN
        v_caught := TRUE;
    END;
    IF NOT v_caught THEN
        RAISE EXCEPTION 'update_character: 版不一致で CH412 が上がらない';
    END IF;

    -- 3. v1_characters: 生存中は見え、version / updated_at を含む。
    SELECT count(*) INTO v_count FROM v1_characters WHERE id = v_char_id AND version = 2;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'v1_characters: 生存行が見えない/version が読めない';
    END IF;

    -- 4. soft_delete_character: 版不一致は CH412（v_char_id は現在 version=2）。
    v_caught := FALSE;
    BEGIN
        PERFORM soft_delete_character(v_char_id, 1);
    EXCEPTION WHEN SQLSTATE 'CH412' THEN
        v_caught := TRUE;
    END;
    IF NOT v_caught THEN
        RAISE EXCEPTION 'soft_delete_character: 版不一致で CH412 が上がらない';
    END IF;

    -- 5. soft_delete_character: 版省略（NULL）で削除でき、v1_characters から消える。
    PERFORM soft_delete_character(v_char_id);
    SELECT count(*) INTO v_count FROM v1_characters WHERE id = v_char_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'v1_characters: 論理削除済みの行が見えている';
    END IF;

    -- 6. 削除済み/不在に対する再操作は CH404。
    v_caught := FALSE;
    BEGIN
        PERFORM soft_delete_character(v_char_id);
    EXCEPTION WHEN SQLSTATE 'CH404' THEN
        v_caught := TRUE;
    END;
    IF NOT v_caught THEN
        RAISE EXCEPTION 'soft_delete_character: 削除済みで CH404 が上がらない';
    END IF;
    v_caught := FALSE;
    BEGIN
        PERFORM update_character(v_char_id, NULL, 'x', NULL, v_race_id, 'female',
                                 NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    EXCEPTION WHEN SQLSTATE 'CH404' THEN
        v_caught := TRUE;
    END;
    IF NOT v_caught THEN
        RAISE EXCEPTION 'update_character: 削除済みで CH404 が上がらない';
    END IF;

    -- 7. 構造の不変条件は DB が標準 SQLSTATE で弾く（例: 不正な gender = 22P02）。
    v_caught := FALSE;
    BEGIN
        INSERT INTO core_characters (name, race_id, gender)
            VALUES ('_bad_gender', v_race_id, 'robot');
    EXCEPTION WHEN invalid_text_representation THEN
        v_caught := TRUE;
    END;
    IF NOT v_caught THEN
        RAISE EXCEPTION 'gender_enum: 不正値が弾かれていない';
    END IF;

    -- 後片付け（テストデータを残さない）。
    DELETE FROM core_characters WHERE id = v_char_id;
    DELETE FROM races WHERE id = v_race_id;

    RAISE NOTICE 'behavior.sql: DO block checks passed';
END;
$$;

-- 8. set_updated_at トリガー: 別トランザクションの UPDATE で updated_at が前進する。
--    （psql の自動コミットにより、ここからの各文はそれぞれ別トランザクション）
INSERT INTO races (name) VALUES ('_behavior_trigger_race');
INSERT INTO core_characters (name, race_id, gender)
    SELECT '_behavior_trigger_char', id, 'unknown' FROM races WHERE name = '_behavior_trigger_race';

SELECT c.id AS tid, c.updated_at AS before_ts, c.race_id AS rid
  FROM core_characters c WHERE c.name = '_behavior_trigger_char' \gset

SELECT update_character(:'tid'::uuid, 1, '_behavior_trigger_char2', NULL, :'rid'::uuid, 'unknown',
                        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);

SELECT (updated_at > :'before_ts'::timestamptz) AS trigger_ok
  FROM core_characters WHERE id = :'tid'::uuid \gset
\if :trigger_ok
    \echo 'behavior.sql: updated_at trigger check passed'
\else
    \warn 'set_updated_at トリガー: updated_at が前進していない'
    SELECT 1/0; -- 強制的に失敗させる（ON_ERROR_STOP=1 で非 0 終了）
\endif

-- 後片付け
DELETE FROM core_characters WHERE id = :'tid'::uuid;
DELETE FROM races WHERE name = '_behavior_trigger_race';

\echo 'behavior.sql: all checks passed'
