# character-db

キャラクターデータ用 PostgreSQL の **スキーマの唯一の正（source of truth）** と、
そのマイグレーションを管理するリポジトリ。

複数の API（Go・Python など）がこの DB を共有するため、スキーマはここで一元管理し、
各 API はマイグレーションを持たず接続と CRUD のみを行う。

## このリポジトリの責務

- `schema.sql` … テーブル・ENUM・インデックスの宣言的定義（Atlas が管理する「あるべき姿」）
- `migrations/` … `schema.sql` との差分から **Atlas** が自動生成するマイグレーション
- `views/` … ビュー・関数等の冪等SQL（`CREATE OR REPLACE` 等。Atlas 管理外）
- `squawk.toml` … 安全リンタ squawk の設定（除外ルールと理由）
- `Dockerfile` … 空の PostgreSQL サーバーのイメージ定義
- `Dockerfile.migrate` … 適用用イメージ。`atlas migrate apply`（テーブル）→ `psql` で `views/*.sql`
  を冪等適用する（`migrate-entrypoint.sh`）

### スキーマ管理は「ハイブリッド」方式（すべて無料）

Atlas 無料版はビュー・関数・トリガーと `migrate lint` が Pro（有料）専用なので、**対象ごとに
道具を分ける**:

| 対象 | 道具 | 補足 |
|---|---|---|
| テーブル・ENUM・インデックス | **Atlas（宣言的差分）** | `schema.sql` が唯一の正。ALTER/DROP/型変更を安全に自動生成 |
| ビュー・関数・トリガー | **`views/*.sql` の冪等SQL** | `CREATE OR REPLACE` 等。何度適用しても安全。`make migration` の差分計算に巻き込まれない（Atlas 管理外なので Pro ゲートも踏まない） |
| 安全リンタ | **squawk（無料）** | `make lint`。破壊的変更・ロック等を検出 |

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

# ── 安全点検（squawk）──
make lint                    # migrations と views の SQL を静的解析
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
