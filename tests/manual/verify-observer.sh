#!/usr/bin/env bash
# observer プロンプトの受け入れ検証（実 API を消費する。手動実行専用）。
# 一時プロジェクトを作り、フィクスチャ transcript を実際に分析させて
# 期待する Instinct が生成されるかを確認する。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'echo "作業ディレクトリ: ${work}（確認後に手動で削除してください）"' EXIT

project="$work/project"
mkdir -p "$project/.claude" "$project/.learning"
# プラグインは対象プロジェクトの外（プラグインキャッシュ相当）に置かれる。
# 実レイアウトどおり <plugin_root>/bin と <plugin_root>/hooks を再現する
cp -R "$repo_root/bin" "$work/bin"
cp -R "$repo_root/hooks" "$work/hooks"
# エンジン設定（メモリー）: bin から見たプラグインルートは $work
mkdir -p "$work/.learning"
printf 'engine=claude\nmodel=haiku\n' >"$work/.learning/config"

echo "=== observer を実行中（engine=claude, model=haiku）==="
date +%s >"$project/.learning/.lock"
"$work/bin/observe.sh" \
  "$repo_root/tests/fixtures/sample-transcript.jsonl" "$project"

echo "=== 生成された Instinct ==="
ls -la "$project/.learning/instincts/" || true
shopt -s nullglob
for f in "$project/.learning/instincts/"*.md; do
  echo "--- $f ---"
  cat "$f"
done

echo "=== 別セッション相当の transcript で再実行（強化の検証） ==="
date +%s >"$project/.learning/.lock"
"$work/bin/observe.sh" \
  "$repo_root/tests/fixtures/sample-transcript-2.jsonl" "$project"

echo "=== 強化後の frontmatter ==="
grep -H -E '^(confidence|evidence_count):' "$project/.learning/instincts/"*.md || true

cat <<'CHECKLIST'

=== 受け入れチェックリスト（目視確認） ===
[ ] correction 型の Instinct が生成されている（pip ではなく uv を使う）
[ ] error-solution 型の Instinct が生成されている（uv add 後に uv sync）
[ ] 各ファイルの frontmatter に id/type/status/confidence/evidence_count/promote_to/created/updated が揃っている
[ ] 1回目の実行後、confidence が 0.3、status が active である
[ ] 2回目（別セッション相当）の実行後、confidence 0.5・evidence_count 2 に強化され、ファイル数は増えていない
[ ] 無関係・自明な Instinct が生成されていない
CHECKLIST
