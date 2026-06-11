# セキュリティポリシー

## 脆弱性の報告
脆弱性を見つけた場合は、公開 Issue ではなく非公開（リポジトリオーナーへの連絡 / GitHub Security Advisory）で報告してください。

## 自動スキャン（このリポジトリに実在するもの）
- 秘密情報：gitleaks（CI）
- SQL の安全点検：squawk（`make lint` / CI。破壊的変更・ロック等）
- 適用・振る舞い検証：CI が本番同等の migrate イメージで適用テストと `tests/behavior.sql` を実行
- 依存更新：dependabot（Docker ベースイメージ / GitHub Actions）

## 原則
- シークレットはコミットしない（DB 認証情報は `character-db-infra` の Secrets Manager / 各 compose の `.env` で管理）。
- スキーマの破壊的変更（カラム削除・リネーム）は全 API が対応済みになってから行う（expand→contract）。
- 書き込みの不変条件（楽観ロック・論理削除）は DB 関数（`views/10_character_write_functions.sql`）に集約し、各 API に生の UPDATE / DELETE を書かせない。
