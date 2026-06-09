#!/bin/sh
# character-db-migrate の実行スクリプト。
#   1) atlas migrate apply … テーブル・ENUM・インデックス（Atlas 管理の宣言的マイグレーション）
#   2) psql で views/*.sql を冪等適用 … ビュー・関数（CREATE OR REPLACE 等。Atlas 管理外）
#   3) psql で seeds/*.sql を冪等適用 … マスタ初期データ（ON CONFLICT DO NOTHING 等。Atlas 管理外）
#
# DB 接続先は command 引数の `--url=...` から取得する（ローカル compose・本番 ECS とも
# この形で渡しているため、compose / Terraform を変更せずに済む）。
set -e

DB_URL=""
for arg in "$@"; do
	case "$arg" in
		--url=*) DB_URL="${arg#--url=}" ;;
	esac
done
if [ -z "$DB_URL" ]; then
	echo "migrate-entrypoint: --url=<DSN> が必要です" >&2
	exit 1
fi

echo "==> [1/3] atlas migrate apply（テーブル等）"
atlas migrate apply --dir "file:///migrations" "$@"

echo "==> [2/3] ビュー/関数の冪等適用（views/*.sql）"
for f in /views/*.sql; do
	[ -e "$f" ] || continue   # views が空でも失敗しない
	echo "    -> $f"
	psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$f"
done

echo "==> [3/3] マスタ初期データの冪等適用（seeds/*.sql）"
for f in /seeds/*.sql; do
	[ -e "$f" ] || continue   # seeds が空でも失敗しない
	echo "    -> $f"
	psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$f"
done

echo "==> マイグレーション完了"
