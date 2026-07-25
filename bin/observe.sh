#!/usr/bin/env bash
# Observer launcher: analyzes the transcript via claude -p and accumulates Instincts.
# Assumes it is started in the background by session-end.sh; stdout/stderr are
# redirected to logs/observer.log by the caller.
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

# Runtime data lives outside .claude (headless claude can't write under .claude)
data_dir="$project_dir/.learning"
lock_file="$data_dir/.lock"
trap 'rm -f "$lock_file"' EXIT

# Engine and model are read from the project's .learning/config (created by /learning:setup).
# Validate first so a misconfiguration leaves no side effects from directory creation
# or prompt processing
config_file="$data_dir/config"
engine=$(read_config_value "$config_file" engine)
model=$(read_config_value "$config_file" model)
if ! is_valid_engine "$engine"; then
  log_engine_guidance "$engine"
  exit 0
fi
check_required_command "$engine" || exit 0

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
# ${model:+...} is intentionally left unquoted (the whole argument disappears when empty).
# The per-engine default models are also documented in skills/setup/SKILL.md's
# procedure and the README's engine table (keep all three in sync when changing)
case "$engine" in
  claude)
    # A Write(path) rule doesn't match the file-permission check (an Edit(path) rule
    # covers all file-editing tools including Write), so only Edit is specified here
    LEARNING_SKILLS_OBSERVER=1 claude -p "$prompt" --model "${model:-haiku}" \
      --allowedTools "Read,Glob,Grep,Edit(.learning/instincts/**)"
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
    # Unreachable after is_valid_engine passes; a safety net to catch drift
    # between VALID_ENGINES and the case arms
    log_engine_guidance "$engine"
    exit 0
    ;;
esac || echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] observer failed: transcript=$transcript_path"
exit 0
