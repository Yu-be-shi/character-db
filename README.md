# character-db

キャラクターデータ用 PostgreSQL の **スキーマの唯一の正（source of truth）** と、
そのマイグレーションを管理するリポジトリ。

複数の API（Go・Python など）がこの DB を共有するため、スキーマはここで一元管理し、
各 API はマイグレーションを持たず接続と CRUD のみを行う。

## このリポジトリの責務

- `schema.sql` … テーブル・ENUM・インデックスの宣言的定義（Atlas が管理する「あるべき姿」）
- `migrations/` … `schema.sql` との差分から **Atlas** が自動生成するマイグレーション
- `views/` … ビュー・関数等の冪等SQL（`CREATE OR REPLACE` 等。Atlas 管理外）
- `seeds/` … マスタ初期データの冪等SQL（`INSERT ... ON CONFLICT DO NOTHING` 等。Atlas 管理外）
- `squawk.toml` … 安全リンタ squawk の設定（除外ルールと理由）
- `Dockerfile` … 空の PostgreSQL サーバーのイメージ定義
- `Dockerfile.migrate` … 適用用イメージ。`atlas migrate apply`（テーブル）→ `psql` で `views/*.sql`
  → `psql` で `seeds/*.sql` を冪等適用する（`migrate-entrypoint.sh`）

### スキーマ管理は「ハイブリッド」方式（すべて無料）

Atlas 無料版はビュー・関数・トリガーと `migrate lint` が Pro（有料）専用なので、**対象ごとに
道具を分ける**:

| 対象 | 道具 | 補足 |
|---|---|---|
| テーブル・ENUM・インデックス | **Atlas（宣言的差分）** | `schema.sql` が唯一の正。ALTER/DROP/型変更を安全に自動生成 |
| ビュー・関数・トリガー | **`views/*.sql` の冪等SQL** | `CREATE OR REPLACE` 等。何度適用しても安全。`make migration` の差分計算に巻き込まれない（Atlas 管理外なので Pro ゲートも踏まない） |
| マスタ初期データ | **`seeds/*.sql` の冪等SQL** | `INSERT ... ON CONFLICT DO NOTHING` 等。Atlas はデータ（行）を管理しないため分離。`core_characters.race_id` は NOT NULL 必須でアプリの作成フォームが `races` 一覧に依存するため、最低限のマスタ（`races`）をここで投入する |
| 安全リンタ | **squawk（無料）** | `make lint`。`migrations` + `views` + `seeds` の破壊的変更・ロック等を検出 |

Atlas は `schema.sql`（テーブルのみ）を見て差分するため、`migrations/` への手書き追記はしない
（直したいときは `schema.sql` を直して再生成）。ビューの「あるべき定義」は `views/` に置く。
列の並び替え・型変更など `CREATE OR REPLACE VIEW` で不可能な変更が要るときは、ファイル先頭で
`DROP VIEW IF EXISTS ...` を明示してから作り直す。

## 責務の分担

| 責務 | 担当 |
|---|---|
| スキーマ定義・マイグレーション生成/適用 | **このリポジトリ（character-db）** |
| PostgreSQL コンテナ起動・ネットワーク定義 | `character-db-infra`（ローカル）/ RDS（本番） |
| キャラクターデータの読み書き（CRUD） | 各 API（例: `apis/character-api-go`）※マイグレーションは持たない |

> キャラクターの所有者（owner）概念はここに持ち込まない。ユーザーとキャラクターの
> 紐付けは application 側（MySQL / Prisma の `UserCharacter`）が管理する。

## スキーマ変更手順

```bash
# ── テーブル・ENUM・インデックス（Atlas）──
# 1. schema.sql を編集する（あるべき姿を書く）
make migration name=<説明>   # migrations/<timestamp>_<説明>.sql を差分から自動生成
# 2. 生成された差分SQLを確認（修正が要るときは schema.sql を直して再生成する）
make hash                    # migrations/atlas.sum を更新してコミット

# ── ビュー・関数（冪等SQL）──
# views/*.sql を編集（CREATE OR REPLACE 等）

# ── マスタ初期データ（冪等SQL）──
# seeds/*.sql を編集（INSERT ... ON CONFLICT DO NOTHING 等）

# ── 安全点検（squawk）──
make lint                    # migrations / views / seeds の SQL を静的解析
```

差分計算には使い捨ての一時 Postgres（dev database）を使う。`docker` さえあれば動き、
起動中の character-db や手動作成の空DBには依存しない:

- **atlas CLI をホストに入れている場合** … `docker://postgres/16/dev` を指定し、atlas が
  一時 Postgres を自動で起動/破棄する（ホストの docker CLI を利用）。
- **atlas CLI が無いホスト** … Makefile が専用ネットワーク上に一時 Postgres を起動し、
  atlas を `arigaio/atlas` コンテナで実行して同ネットワークから接続する（完了後に自動破棄）。
  ※ atlas-only イメージには docker CLI が無く `docker://` が使えないため、この方式を取る。

複数 API が共有するため、**カラム削除・リネームは全 API が対応済みになってから行う**こと。

## イメージビルド

`character-db-infra` の docker-compose.yml がこのリポジトリの Dockerfile / Dockerfile.migrate
を参照してビルドする。

```bash
# character-db-infra ディレクトリから実行
docker compose up -d            # PostgreSQL 起動 + マイグレーション適用
```

## 読み書きのコントラクト（全 API 共通）

複数 API が同じ DB を共有するため、「読み方」「書き方」をここで固定する。

### 読み取り

- 一覧・参照は **`v1_characters` ビュー**を使う（`WHERE deleted_at IS NULL` 適用済み・
  `version` / `updated_at` を含む）。テーブル直読みする場合も論理削除（`deleted_at IS NULL`）を
  必ず適用すること。

### 書き込み（生の UPDATE / DELETE を書かない）

更新・削除の手順的な不変条件（楽観ロック・論理削除）は **DB 関数に集約**してあり、
各言語の API は関数を呼ぶだけにする:

| 操作 | 関数 | 説明 |
|---|---|---|
| 全置換更新 | `update_character(p_id, p_expected_version, ...)` | `FOR UPDATE` で行ロック → 版検査 → 更新 + `version + 1`。`p_expected_version` が NULL なら版検査なし |
| 論理削除 | `soft_delete_character(p_id, p_expected_version DEFAULT NULL)` | `deleted_at` を設定（物理 DELETE しない）。版指定時は update と同じ契約 |

### エラー契約（カスタム SQLSTATE）

| SQLSTATE | 意味 | API が返すべき HTTP |
|---|---|---|
| `CH404` | 対象が不在 or 削除済み | 404 Not Found |
| `CH412` | 楽観ロックの版不一致 | 412 Precondition Failed |

構造の不変条件（ENUM・CHECK・FK・UNIQUE）は DB が標準 SQLSTATE（`22P02` / `23514` /
`23503` / `23505`）で弾くため、関数では扱わない。各 API はこれらを各言語のエラー型に変換する。

これらの振る舞いは CI（`tests/behavior.sql`）でリグレッション検知している。

## 適用（character-db-migrate）の接続情報

`migrate-entrypoint.sh` は接続先を次の優先順で受け取る（いずれも atlas が解釈できる
`postgres://...` URL 形式であること）:

1. command 引数 `--url=<DSN>`（ローカル compose はこの形）
2. 環境変数 `DB_DSN`（本番 ECS。exec 形式の command は `$(VAR)` を展開しないため環境変数で渡す）

views / seeds は `psql -1`（ファイル単位の単一トランザクション）で適用するため、
`DROP FUNCTION → CREATE FUNCTION` を含むファイルでも「関数が無い瞬間」を稼働中の API に見せない。

## CI とスキーマ更新通知

- **CI（`.github/workflows/ci.yml`）** … PR ごとに (1) `atlas migrate validate`（`make hash`
  忘れの検知）、(2) squawk、(3) 本番同等 migrate イメージでの適用テスト、(4) `tests/behavior.sql`
  による振る舞いテスト、(5) `schema.sql` と `migrations/` の乖離チェック（`make migration`
  忘れの検知）を行う。**`schema.sql` を編集したら `make migration` と `make hash` を忘れない**こと。
- **更新通知（`.github/workflows/notify-consumers.yml`）** … スキーマ関連ファイルが develop に
  マージされると、Repository Variable `CONSUMER_REPOS` に列挙された消費者リポジトリへ
  `repository_dispatch`（`character-db-updated`）を送る。受け取った API 側は自動で submodule
  bump + codegen 再実行 + 追従 PR 作成を行う（例: character-api-go の `schema-sync.yml`）。
  API を増やすときは `CONSUMER_REPOS` に追記するだけでよい。

## views/ の命名規約

`views/*.sql` は **辞書順（グロブ順）に適用**されるため、依存順に数値プレフィクスを付ける:
`00_`（トリガー等の基盤）→ `10_`（関数）→ `v1_`（公開ビュー。`v` は数値より後に並ぶ）。
新しいファイルを足すときは適用順に注意すること。
