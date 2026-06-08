.PHONY: migration hash

# Atlas CLI がなければ Docker イメージで代替
ATLAS := $(shell which atlas 2>/dev/null)
ifdef ATLAS
  ATLAS_CMD := atlas
else
  ATLAS_CMD := docker run --rm --network host -v "$(PWD):/workspace" -w /workspace arigaio/atlas:latest
endif

# PostgreSQL 接続先 (atlas_dev はマイグレーション計算専用の空DB)
DEV_URL := postgres://characters:characters@localhost:5432/atlas_dev?search_path=public&sslmode=disable

# スキーマ変更手順:
# 1. schema.sql を編集する（テーブル・ビュー含め「あるべき姿」をすべてここに書く）
# 2. make migration name=<説明> を実行 → migrations/ に差分SQLが自動生成される
# 3. 生成された差分SQLを確認する（編集が必要なら schema.sql 側を直して再生成すること。
#    Atlas は schema.sql に無いオブジェクトを DROP するため、VIEW 等をマイグレーション
#    ファイルに手書きしてはならない）
# 4. make hash でチェックサムを更新してコミットする

migration:
ifndef name
	$(error 使用方法: make migration name=<説明>)
endif
	$(ATLAS_CMD) migrate diff $(name) \
		--dir "file://migrations" \
		--to "file://schema.sql" \
		--dev-url "$(DEV_URL)"

hash:
	$(ATLAS_CMD) migrate hash --dir "file://migrations"
