#!/usr/bin/env bash
# observer プロンプトの受け入れ検証（実 API を消費する。手動実行専用）。
# 一時プロジェクトを作り、フィクスチャ transcript を実際に分析させて
# 期待する Instinct が生成されるかを確認する。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'echo "作業ディレクトリ: $work（確認後に手動で削除してください）"' EXIT

project="$work/project"
mkdir -p "$project/.claude"
cp -R "$repo_root/.claude/skills" "$project/.claude/skills"
rm -rf "$project/.claude/skills/learning/instincts" "$project/.claude/skills/learning/logs"

echo "=== observer を実行中（モデル: ${LEARNING_SKILLS_MODEL:-haiku}）==="
date +%s >"$project/.claude/skills/learning/.lock"
"$project/.claude/skills/learning/scripts/observe.sh" \
  "$repo_root/tests/fixtures/sample-transcript.jsonl" "$project"

echo "=== 生成された Instinct ==="
ls -la "$project/.claude/skills/learning/instincts/" || true
shopt -s nullglob
for f in "$project/.claude/skills/learning/instincts/"*.md; do
  echo "--- $f ---"
  cat "$f"
done

cat <<'CHECKLIST'

=== 受け入れチェックリスト（目視確認） ===
[ ] correction 型の Instinct が生成されている（pip ではなく uv を使う）
[ ] error-solution 型の Instinct が生成されている（uv add 後に uv sync）
[ ] 各ファイルの frontmatter に id/type/status/confidence/evidence_count/promote_to/created/updated が揃っている
[ ] confidence が 0.3、status が active である
[ ] 無関係・自明な Instinct が生成されていない
[ ] もう一度このスクリプトの observe.sh 実行部分だけ再実行すると、新規作成ではなく既存の confidence が 0.5 に強化される
CHECKLIST
