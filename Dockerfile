FROM postgres:16-alpine

# カスタム設定が必要になった場合はここに追加する
# COPY config/postgresql.conf /etc/postgresql/postgresql.conf

# テーブル構造（マイグレーション）は Repo1（character-api）が管理する。
# ここには初期化スクリプト（initdb）を置かない。
