FROM postgres:18-alpine

# カスタム設定が必要になった場合はここに追加する
# COPY config/postgresql.conf /etc/postgresql/postgresql.conf

# これは「空の PostgreSQL サーバー」のイメージ定義のみ。
# スキーマ（schema.sql）とマイグレーションはこのリポジトリの Atlas が管理し、
# 適用は別イメージ Dockerfile.migrate（character-db-migrate サービス）が行う。
# そのため、ここには初期化スクリプト（initdb）を置かない。
