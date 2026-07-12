#!/usr/bin/env bash
# observer 起動スクリプト: transcript を claude -p で分析し Instinct を蓄積する。
# session-end.sh からバックグラウンドで起動される前提。stdout/stderr は
# 呼び出し元によって logs/observer.log にリダイレクトされる。
set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
base_dir=$(cd "$script_dir/.." && pwd)
lock_file="$base_dir/.lock"
trap 'rm -f "$lock_file"' EXIT

transcript_path="${1:?transcript path required}"
project_dir="${2:?project dir required}"

instincts_dir="$base_dir/instincts"
mkdir -p "$instincts_dir"

prompt=$(<"$base_dir/prompts/observer.md")
prompt="${prompt//\{\{TRANSCRIPT_PATH\}\}/$transcript_path}"
prompt="${prompt//\{\{INSTINCTS_DIR\}\}/$instincts_dir}"
prompt="${prompt//\{\{TODAY\}\}/$(date +%F)}"

model="${LEARNING_SKILLS_MODEL:-haiku}"

cd "$project_dir" || exit 0
if ! LEARNING_SKILLS_OBSERVER=1 claude -p "$prompt" --model "$model" \
    --allowedTools "Read,Write,Edit,Glob,Grep"; then
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] observer failed: transcript=$transcript_path"
fi
exit 0
