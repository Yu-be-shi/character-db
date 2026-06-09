-- updated_at 自動更新トリガー（冪等SQL。Atlas 管理外）。
--   ・core_characters は複数の書き手（Go / Python API・psql 直アクセス）が共有するため、
--     アプリ層に頼らず DB 側で UPDATE のたびに updated_at = NOW() を強制する。
--   ・CREATE OR REPLACE FUNCTION ＋ DROP TRIGGER IF EXISTS で何度適用しても安全。
--   ・character-db-migrate が `atlas migrate apply`（テーブル）の後にこれを適用する。
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_core_characters_set_updated_at ON core_characters;
CREATE TRIGGER trg_core_characters_set_updated_at
    BEFORE UPDATE ON core_characters
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
