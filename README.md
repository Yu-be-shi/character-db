# character-db

Repo1（character-api）専用の PostgreSQL コンテナ定義。

## このリポジトリの責務

- PostgreSQL コンテナのイメージ定義のみ
- テーブル構造（DDL・マイグレーション）は **一切管理しない**

## テーブル管理の分担

| 責務 | 担当 |
|---|---|
| コンテナ起動・ネットワーク定義 | Repo4（infra-compose） |
| テーブル作成・マイグレーション実行 | Repo1（character-api） |
| カラム定義・インデックス追加 | Repo1 のマイグレーションファイル |

## ユーザー情報について

このDBはユーザー情報を**一切持たない**。
ユーザーデータは Repo2（user-dashboard）の MySQL で管理する。

## イメージビルド

Repo4 の docker-compose.yml がこのリポジトリの Dockerfile を参照してビルドする。

```bash
# Repo4 ディレクトリから実行
docker compose build character-db
```
