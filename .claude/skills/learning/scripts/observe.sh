#!/usr/bin/env bash
# observer 起動スクリプト: transcript を claude -p で分析し Instinct を蓄積する。
# session-end.sh からバックグラウンドで起動される前提。stdout/stderr は
# 呼び出し元によって logs/observer.log にリダイレクトされる。
set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
base_dir=$(cd "$script_dir/.." && pwd)

transcript_path="${1:?transcript path required}"
project_dir="${2:?project dir required}"

# ランタイムデータは .claude 外に置く（headless の claude は .claude 配下に書き込めない）
data_dir="$project_dir/.learning"
lock_file="$data_dir/.lock"
trap 'rm -f "$lock_file"' EXIT

instincts_dir="$data_dir/instincts"
mkdir -p "$instincts_dir"
[ -f "$data_dir/.gitignore" ] || echo '*' >"$data_dir/.gitignore"

prompt_file="$base_dir/prompts/observer.md"
if [ ! -f "$prompt_file" ]; then
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] observer prompt missing: $prompt_file"
  exit 0
fi

prompt=$(<"$prompt_file")
prompt="${prompt//\{\{TRANSCRIPT_PATH\}\}/$transcript_path}"
prompt="${prompt//\{\{INSTINCTS_DIR\}\}/$instincts_dir}"
prompt="${prompt//\{\{TODAY\}\}/$(date +%F)}"

model="${LEARNING_SKILLS_MODEL:-haiku}"

cd "$project_dir" || exit 0
if ! LEARNING_SKILLS_OBSERVER=1 claude -p "$prompt" --model "$model" \
    --allowedTools "Read,Glob,Grep,Write(.learning/instincts/**),Edit(.learning/instincts/**)"; then
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] observer failed: transcript=$transcript_path"
fi
exit 0
