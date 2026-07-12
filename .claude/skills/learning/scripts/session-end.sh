#!/usr/bin/env bash
# SessionEnd hook: セッション transcript の学習分析（observer）を起動する。
# 学習系の失敗はセッション終了を妨げてはならないため、常に exit 0 する。
set -u

MIN_TURNS="${LEARNING_SKILLS_MIN_TURNS:-10}"
LOCK_STALE_SECONDS=1800

main() {
  # 再帰防止: observer 自身の claude -p セッションでは何もしない
  [ "${LEARNING_SKILLS_OBSERVER:-}" = "1" ] && return 0

  local input transcript_path cwd
  input=$(cat) || return 0
  transcript_path=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null) || return 0
  cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null) || return 0
  { [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; } || return 0
  { [ -n "$cwd" ] && [ -d "$cwd" ]; } || return 0

  # プロジェクト外のセッションは学習対象外
  [ -d "$cwd/.claude" ] || [ -f "$cwd/CLAUDE.md" ] || return 0

  # 短小セッションには学習素材がない
  local turns
  turns=$(jq -r 'select(.type == "user" or .type == "assistant") | .type' \
    "$transcript_path" 2>/dev/null | wc -l | tr -d ' ')
  [ "${turns:-0}" -ge "$MIN_TURNS" ] || return 0

  local script_dir base_dir lock_file now
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  base_dir=$(cd "$script_dir/.." && pwd)
  lock_file="$base_dir/.lock"
  now=$(date +%s)

  # 多重起動防止。observer 異常終了で学習が止まらないよう stale ロックは奪取する
  if [ -f "$lock_file" ]; then
    local ts age
    ts=$(cat "$lock_file" 2>/dev/null)
    [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
    age=$((now - ts))
    [ "$age" -gt "$LOCK_STALE_SECONDS" ] || return 0
  fi
  echo "$now" >"$lock_file"

  mkdir -p "$base_dir/logs"
  if [ "${LEARNING_SKILLS_SYNC:-}" = "1" ]; then
    "$script_dir/observe.sh" "$transcript_path" "$cwd" \
      >>"$base_dir/logs/observer.log" 2>&1 || true
  else
    nohup "$script_dir/observe.sh" "$transcript_path" "$cwd" \
      >>"$base_dir/logs/observer.log" 2>&1 &
  fi
  return 0
}

main || true
exit 0
