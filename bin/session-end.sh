#!/usr/bin/env bash
# SessionEnd/Stop hook: launches the learning analysis (observer) on the session transcript.
# Normalizes hook input dialects across Claude Code / VS Code / Codex / Copilot / Cursor.
# Learning-related failures must never block session end, so this always exits 0.
set -u

MIN_TURNS="${LEARNING_SKILLS_MIN_TURNS:-10}"
LOCK_STALE_SECONDS=1800

main() {
  # Recursion guard: do nothing in the observer's own session
  [ "${LEARNING_SKILLS_OBSERVER:-}" = "1" ] && return 0

  local script_dir input transcript_path cwd session_id
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  source "$script_dir/lib.sh" 2>/dev/null || {
    echo "learning-skills: $script_dir/lib.sh not found; observation disabled" >&2
    return 0
  }
  check_required_command jq || return 0

  input=$(cat) || return 0
  # Normalize input fields: Claude/VS Code/Codex use snake_case, Copilot uses camelCase,
  # and Cursor passes workspace_roots instead of cwd
  transcript_path=$(jq -r '.transcript_path // .transcriptPath // empty' <<<"$input" 2>/dev/null) || return 0
  cwd=$(jq -r '.cwd // (.workspace_roots // [])[0] // empty' <<<"$input" 2>/dev/null) || return 0
  session_id=$(jq -r '.session_id // .sessionId // .conversation_id // "unknown"' <<<"$input" 2>/dev/null) || return 0
  { [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; } || return 0
  { [ -n "$cwd" ] && [ -d "$cwd" ]; } || return 0

  # Sessions outside a project are not eligible for learning
  local marker in_project=0
  for marker in .claude CLAUDE.md AGENTS.md .cursor .codex .github; do
    if [ -e "$cwd/$marker" ]; then
      in_project=1
      break
    fi
  done
  [ "$in_project" = "1" ] || return 0

  # Short sessions have no learning material. For transcripts that can't be counted
  # in Claude's format, approximate with total line count (each agent's transcript
  # format is not a stable API)
  local turns
  turns=$(jq -r 'select(.type == "user" or .type == "assistant") | .type' \
    "$transcript_path" 2>/dev/null | wc -l | tr -d ' ')
  [ "${turns:-0}" -gt 0 ] || turns=$(wc -l <"$transcript_path" | tr -d ' ')
  [ "${turns:-0}" -ge "$MIN_TURNS" ] || return 0

  # Runtime data lives outside .claude (headless claude can't write under .claude)
  local project_root data_dir lock_file state_file now
  # Sessions from a git worktree are aggregated into the main worktree (if .learning
  # were scattered per worktree, confidence would never grow, and learning data
  # would be lost when the worktree is removed)
  project_root=$(resolve_project_root "$cwd")
  data_dir="$project_root/.learning"
  lock_file="$data_dir/.lock"
  state_file="$data_dir/analyzed.tsv"
  now=$(date +%s)

  # If there's no config yet, try to auto-configure from a reliable host-agent
  # signal (currently only Claude Code) so observation works without ever running
  # /learning:setup manually. If no such signal exists, do nothing as before —
  # config is otherwise created by /learning:setup. Never overwrite a config that
  # already exists (even if empty or invalid), since that may be a deliberate
  # user/setup choice. If config exists but the engine is empty or invalid, leave
  # guidance in observer.log and do nothing (both are decided before the
  # incremental guard, so a missed engine setup doesn't get recorded in
  # analyzed.tsv and lose a learning opportunity).
  local config_file engine
  config_file="$data_dir/config"
  if [ ! -f "$config_file" ]; then
    local detected
    detected=$(detect_agent_engine)
    [ -n "$detected" ] || return 0
    mkdir -p "$data_dir"
    printf 'engine=%s\nmodel=%s\n' "$detected" "$DEFAULT_MODEL_CLAUDE" >"$config_file"
    ensure_learning_gitignore "$data_dir"
  fi
  engine=$(read_config_value "$config_file" engine)
  if ! is_valid_engine "$engine"; then
    mkdir -p "$data_dir/logs"
    log_engine_guidance "$engine" >>"$data_dir/logs/observer.log"
    return 0
  fi

  # Incremental guard: re-analysis of the same transcript by per-turn events
  # (Stop/agentStop/stop) is only allowed once turns have grown by MIN_TURNS
  # or more since the last analysis
  local last
  last=$(awk -F'\t' -v p="$transcript_path" '$1 == p { v = $2 } END { print v }' \
    "$state_file" 2>/dev/null)
  [[ "${last:-}" =~ ^[0-9]+$ ]] || last=0
  [ $((turns - last)) -ge "$MIN_TURNS" ] || return 0

  # Prevent concurrent runs. A stale lock is seized so an observer crash doesn't halt learning
  if [ -f "$lock_file" ]; then
    local ts age
    ts=$(cat "$lock_file" 2>/dev/null)
    [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
    age=$((now - ts))
    [ "$age" -gt "$LOCK_STALE_SECONDS" ] || return 0
  fi
  mkdir -p "$data_dir/logs"
  echo "$now" >"$lock_file"

  # Record the analyzed turn count while holding the lock, to suppress re-firing before the observer finishes
  if [ -f "$state_file" ]; then
    awk -F'\t' -v p="$transcript_path" '$1 != p' "$state_file" >"$state_file.tmp"
  else
    : >"$state_file.tmp"
  fi
  printf '%s\t%s\n' "$transcript_path" "$turns" >>"$state_file.tmp"
  mv "$state_file.tmp" "$state_file"

  if [ "${LEARNING_SKILLS_SYNC:-}" = "1" ]; then
    "$script_dir/observe.sh" "$transcript_path" "$project_root" "$session_id" \
      >>"$data_dir/logs/observer.log" 2>&1 || true
  else
    nohup "$script_dir/observe.sh" "$transcript_path" "$project_root" "$session_id" \
      >>"$data_dir/logs/observer.log" 2>&1 &
  fi
  return 0
}

main || true
exit 0
