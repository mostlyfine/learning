#!/usr/bin/env bash
# observer 起動スクリプト: transcript を claude -p で分析し Instinct を蓄積する。
# session-end.sh からバックグラウンドで起動される前提。stdout/stderr は
# 呼び出し元によって logs/observer.log にリダイレクトされる。
set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin_root=$(cd "$script_dir/.." && pwd)

transcript_path="${1:?transcript path required}"
project_dir="${2:?project dir required}"
session_id="${3:-unknown}"

# ランタイムデータは .claude 外に置く（headless の claude は .claude 配下に書き込めない）
data_dir="$project_dir/.learning"
lock_file="$data_dir/.lock"
trap 'rm -f "$lock_file"' EXIT

instincts_dir="$data_dir/instincts"
mkdir -p "$instincts_dir"
[ -f "$data_dir/.gitignore" ] || echo '*' >"$data_dir/.gitignore"

prompt_file="$plugin_root/hooks/prompts/observer.md"
if [ ! -f "$prompt_file" ]; then
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] observer prompt missing: $prompt_file"
  exit 0
fi

prompt=$(<"$prompt_file")
prompt="${prompt//\{\{TRANSCRIPT_PATH\}\}/$transcript_path}"
prompt="${prompt//\{\{INSTINCTS_DIR\}\}/$instincts_dir}"
prompt="${prompt//\{\{TODAY\}\}/$(date +%F)}"
prompt="${prompt//\{\{SESSION_ID\}\}/$session_id}"

# エンジンとモデルはプラグイン内の設定ファイル（/learning:status の初回セットアップで
# 作成されるメモリー）から読む
config_file="$plugin_root/.learning/config"
engine=""
model=""
if [ -f "$config_file" ]; then
  engine=$(sed -n 's/^engine=//p' "$config_file" | tail -1)
  model=$(sed -n 's/^model=//p' "$config_file" | tail -1)
fi
if [ -z "$engine" ]; then
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] engine not configured; run /learning:status to set up"
  exit 0
fi

cd "$project_dir" || exit 0
# ${model:+...} は意図的に unquoted（空なら引数ごと消える）
case "$engine" in
  claude)
    LEARNING_SKILLS_OBSERVER=1 claude -p "$prompt" --model "${model:-haiku}" \
      --allowedTools "Read,Glob,Grep,Write(.learning/instincts/**),Edit(.learning/instincts/**)"
    ;;
  codex)
    LEARNING_SKILLS_OBSERVER=1 codex exec --skip-git-repo-check --sandbox workspace-write \
      ${model:+--model "$model"} "$prompt"
    ;;
  copilot)
    LEARNING_SKILLS_OBSERVER=1 copilot -p "$prompt" ${model:+--model "$model"} \
      --allow-tool 'write(.learning/instincts/**)' --no-ask-user -s
    ;;
  *)
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] unknown engine: $engine (valid: claude, codex, copilot); run /learning:status to fix the config"
    exit 0
    ;;
esac || echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] observer failed: transcript=$transcript_path"
exit 0
