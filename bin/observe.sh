#!/usr/bin/env bash
# observer 起動スクリプト: transcript を claude -p で分析し Instinct を蓄積する。
# session-end.sh からバックグラウンドで起動される前提。stdout/stderr は
# 呼び出し元によって logs/observer.log にリダイレクトされる。
set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lib.sh" 2>/dev/null || {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] lib.sh missing: $script_dir/lib.sh"
  exit 0
}
plugin_root=$(resolve_plugin_root "$script_dir")

transcript_path="${1:?transcript path required}"
project_dir="${2:?project dir required}"
session_id="${3:-unknown}"

# ランタイムデータは .claude 外に置く（headless の claude は .claude 配下に書き込めない）
data_dir="$project_dir/.learning"
lock_file="$data_dir/.lock"
trap 'rm -f "$lock_file"' EXIT

# エンジンとモデルはプラグイン内の設定ファイル（/learning:setup で作成される）から読む。
# 誤設定時にディレクトリ作成やプロンプト処理の副作用を残さないよう最初に検証する
config_file="$plugin_root/.learning/config"
engine=$(read_config_value "$config_file" engine)
model=$(read_config_value "$config_file" model)
if ! is_valid_engine "$engine"; then
  log_engine_guidance "$engine"
  exit 0
fi

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

cd "$project_dir" || exit 0
# ${model:+...} は意図的に unquoted（空なら引数ごと消える）。
# エンジン別の既定モデルは skills/setup/SKILL.md の手順と README のエンジン表にも
# 記載がある（変更時は3箇所を同期する）
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
    # is_valid_engine 通過後は到達しない安全弁（VALID_ENGINES と case 腕の乖離検出用）
    log_engine_guidance "$engine"
    exit 0
    ;;
esac || echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] observer failed: transcript=$transcript_path"
exit 0
