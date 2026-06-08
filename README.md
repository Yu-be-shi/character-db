# character-db

キャラクターデータ用 PostgreSQL の **スキーマの唯一の正（source of truth）** と、
そのマイグレーションを管理するリポジトリ。

複数の API（Go・Python など）がこの DB を共有するため、スキーマはここで一元管理し、
各 API はマイグレーションを持たず接続と CRUD のみを行う。

## このリポジトリの責務

- `schema.sql` … 「あるべきスキーマ」の宣言的定義（テーブル・ビュー・インデックス・ENUM）
- `migrations/` … `schema.sql` との差分から **Atlas** が自動生成するマイグレーション
- `Dockerfile` … 空の PostgreSQL サーバーのイメージ定義
- `Dockerfile.migrate` … `atlas migrate apply` を実行するマイグレーション適用用イメージ

ENUM やビュー（例: `v1_characters`）を含め、DB 上のあらゆるオブジェクトは
`schema.sql` に宣言する。Atlas は宣言に無いオブジェクトを差分で削除するため、
マイグレーションファイルへの手書き追記は行わない。

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
# 1. schema.sql を編集する（あるべき姿を書く）
make migration name=<説明>   # migrations/<timestamp>_<説明>.sql を差分から自動生成
# 3. 生成された差分SQLを確認（修正が要るときは schema.sql を直して再生成する）
make hash                    # migrations/atlas.sum を更新してコミット
```

Atlas CLI が無い環境では Makefile が `arigaio/atlas` の Docker イメージで代替する。
差分計算には `atlas_dev`（計算専用の空 DB）を使う。

複数 API が共有するため、**カラム削除・リネームは全 API が対応済みになってから行う**こと。

## イメージビルド

`character-db-infra` の docker-compose.yml がこのリポジトリの Dockerfile / Dockerfile.migrate
を参照してビルドする。

```bash
# character-db-infra ディレクトリから実行
docker compose up -d            # PostgreSQL 起動 + マイグレーション適用
```
