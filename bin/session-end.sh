#!/usr/bin/env bash
# SessionEnd/Stop hook: セッション transcript の学習分析（observer）を起動する。
# Claude Code / VS Code / Codex / Copilot / Cursor の hook 入力方言を正規化して受ける。
# 学習系の失敗はセッション終了を妨げてはならないため、常に exit 0 する。
set -u

MIN_TURNS="${LEARNING_SKILLS_MIN_TURNS:-10}"
LOCK_STALE_SECONDS=1800

main() {
  # 再帰防止: observer 自身のセッションでは何もしない
  [ "${LEARNING_SKILLS_OBSERVER:-}" = "1" ] && return 0

  local input transcript_path cwd session_id
  input=$(cat) || return 0
  # 入力フィールドの正規化: Claude/VS Code/Codex は snake_case、Copilot は camelCase、
  # Cursor は cwd の代わりに workspace_roots を渡す
  transcript_path=$(jq -r '.transcript_path // .transcriptPath // empty' <<<"$input" 2>/dev/null) || return 0
  cwd=$(jq -r '.cwd // (.workspace_roots // [])[0] // empty' <<<"$input" 2>/dev/null) || return 0
  session_id=$(jq -r '.session_id // .sessionId // .conversation_id // "unknown"' <<<"$input" 2>/dev/null) || return 0
  { [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; } || return 0
  { [ -n "$cwd" ] && [ -d "$cwd" ]; } || return 0

  # プロジェクト外のセッションは学習対象外
  local marker in_project=0
  for marker in .claude CLAUDE.md AGENTS.md .cursor .codex .github; do
    if [ -e "$cwd/$marker" ]; then
      in_project=1
      break
    fi
  done
  [ "$in_project" = "1" ] || return 0

  # 短小セッションには学習素材がない。Claude 形式で数えられない transcript は
  # 総行数で近似する（各エージェントの transcript 形式は安定 API ではない）
  local turns
  turns=$(jq -r 'select(.type == "user" or .type == "assistant") | .type' \
    "$transcript_path" 2>/dev/null | wc -l | tr -d ' ')
  [ "${turns:-0}" -gt 0 ] || turns=$(wc -l <"$transcript_path" | tr -d ' ')
  [ "${turns:-0}" -ge "$MIN_TURNS" ] || return 0

  # git worktree からのセッションはメイン作業ツリーに集約する（worktree ごとに
  # .learning が分散すると confidence が育たず、worktree 削除で学習データが消える）
  local common_dir project_root
  project_root="$cwd"
  common_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [ -n "$common_dir" ] && [ -d "$(dirname "$common_dir")" ]; then
    project_root=$(dirname "$common_dir")
  fi

  # ランタイムデータは .claude 外に置く（headless の claude は .claude 配下に書き込めない）
  local script_dir plugin_root data_dir lock_file state_file now
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  source "$script_dir/lib.sh"
  plugin_root=$(resolve_plugin_root "$script_dir")
  data_dir="$project_root/.learning"
  lock_file="$data_dir/.lock"
  state_file="$data_dir/analyzed.tsv"
  now=$(date +%s)

  # エンジン未設定なら何もしない（analyzed.tsv に記録して学習機会を失うのを防ぐため
  # 増分ガードより前で判定する）。設定は /learning:recall の初回セットアップで作られる
  [ -f "$plugin_root/.learning/config" ] || return 0

  # 増分ガード: ターン単位で発火するイベント（Stop/agentStop/stop）による
  # 同一 transcript の再分析は、前回分析から MIN_TURNS 以上増えたときだけ許す
  local last
  last=$(awk -F'\t' -v p="$transcript_path" '$1 == p { v = $2 } END { print v }' \
    "$state_file" 2>/dev/null)
  [[ "${last:-}" =~ ^[0-9]+$ ]] || last=0
  [ $((turns - last)) -ge "$MIN_TURNS" ] || return 0

  # 多重起動防止。observer 異常終了で学習が止まらないよう stale ロックは奪取する
  if [ -f "$lock_file" ]; then
    local ts age
    ts=$(cat "$lock_file" 2>/dev/null)
    [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
    age=$((now - ts))
    [ "$age" -gt "$LOCK_STALE_SECONDS" ] || return 0
  fi
  mkdir -p "$data_dir/logs"
  echo "$now" >"$lock_file"

  # 分析済みターン数をロック保持中に記録し、observer 完了前の再発火を抑止する
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
