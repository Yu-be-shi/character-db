.PHONY: migration hash lint

# ホストに atlas CLI があればそれを使う。無ければ arigaio/atlas コンテナで代替する。
# 差分計算用の dev database（使い捨て Postgres）の用意し方が両者で異なる:
#   - atlas CLI あり : atlas が docker:// で一時 Postgres を自動起動/破棄する
#                      （ホストの docker CLI を使うので追加設定不要）
#   - atlas CLI なし : この Makefile が専用ネットワーク上に一時 Postgres を起動し、
#                      atlas はコンテナで実行して同ネットワークから接続する
#                      （atlas-only イメージには docker CLI が無く docker:// が使えないため）
#
# ※ 役割分担（Atlas 無料版はビュー/関数/トリガーと migrate lint が Pro 専用のため）:
#   - テーブル・ENUM・インデックス … この Makefile の Atlas（宣言的差分）が管理
#   - ビュー・関数・トリガー       … views/*.sql に冪等SQL（CREATE OR REPLACE 等）で記述し、
#                                     character-db-migrate が atlas apply 後に psql で適用
#   - 安全リンタ                   … make lint（squawk・無料）
ATLAS := $(shell which atlas 2>/dev/null)

# atlas CLI あり時の dev-url（atlas が docker で一時 Postgres を自動起動/破棄）
HOST_DEV_URL := docker://postgres/16/dev?search_path=public

# squawk（マイグレーション安全リンタ）実行用イメージ。squawk バイナリは glibc なので
# musl の alpine では動かない。glibc 系の node イメージを使う。
SQUAWK_IMG := node:20-slim

# atlas CLI なし時に使う一時 Postgres の設定
ATLAS_IMG  := arigaio/atlas:latest
PG_IMAGE   := postgres:16
NET        := atlas-migrate-net
PG_NAME    := atlas-dev-pg
# コンテナ実行時の dev-url（同一 docker ネットワーク内なのでコンテナ名で解決する）
DEV_DB_URL := postgres://atlas:atlas@$(PG_NAME):5432/dev?sslmode=disable&search_path=public

# スキーマ変更手順:
# 1. テーブル等: schema.sql を編集 → make migration name=<説明>（差分を自動生成）→ make hash
#    （生成SQLの修正が要るときは schema.sql を直して再生成。手書き追記はしない）
# 2. ビュー/関数: views/*.sql を編集（CREATE OR REPLACE 等の冪等SQL。Atlas 管理外）
# 3. make lint で安全点検（squawk）
# 適用は character-db-migrate が「atlas apply（テーブル）→ psql で views 適用」を行う。

migration:
ifndef name
	$(error 使用方法: make migration name=<説明>)
endif
ifdef ATLAS
	atlas migrate diff $(name) \
		--dir "file://migrations" \
		--to "file://schema.sql" \
		--dev-url "$(HOST_DEV_URL)"
else
	@echo "▶ atlas CLI 未検出 → 使い捨て Postgres を起動して atlas をコンテナ実行します"
	@set -e; \
	cleanup() { \
		docker rm -f $(PG_NAME) >/dev/null 2>&1 || true; \
		docker network rm $(NET) >/dev/null 2>&1 || true; \
	}; \
	trap cleanup EXIT INT TERM; \
	docker network create $(NET) >/dev/null 2>&1 || true; \
	docker run -d --rm --name $(PG_NAME) --network $(NET) \
		-e POSTGRES_USER=atlas -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=dev \
		$(PG_IMAGE) >/dev/null; \
	echo "▶ 一時 Postgres の起動を待機中..."; \
	for i in $$(seq 1 60); do \
		if docker exec $(PG_NAME) psql -U atlas -d dev -c 'select 1' >/dev/null 2>&1; then break; fi; \
		sleep 1; \
	done; \
	docker run --rm --network $(NET) -v "$(PWD):/workspace" -w /workspace \
		$(ATLAS_IMG) migrate diff $(name) \
		--dir "file://migrations" \
		--to "file://schema.sql" \
		--dev-url "$(DEV_DB_URL)"
endif

hash:
ifdef ATLAS
	atlas migrate hash --dir "file://migrations"
else
	docker run --rm -v "$(PWD):/workspace" -w /workspace \
		$(ATLAS_IMG) migrate hash --dir "file://migrations"
endif

# lint: マイグレーション/ビューの SQL を squawk で安全点検する（無料・ロック/破壊的変更等）。
# 除外ルールとその理由は squawk.toml を参照。docker さえあれば動く。
lint:
	docker run --rm -v "$(PWD):/work" -w /work $(SQUAWK_IMG) \
		sh -c "npx --yes squawk-cli@latest -c squawk.toml migrations/*.sql views/*.sql"
