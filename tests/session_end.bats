#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  PROJECT="$TMP/project"
  LEARNING="$PROJECT/.claude/skills/learning"
  mkdir -p "$LEARNING/scripts"
  cp "$BATS_TEST_DIRNAME/../.claude/skills/learning/scripts/session-end.sh" \
    "$LEARNING/scripts/session-end.sh"
  # observe.sh スタブ: 呼び出し引数を記録するだけ
  cat >"$LEARNING/scripts/observe.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$(cd "$(dirname "$0")/.." && pwd)/observe-invoked.txt"
STUB
  chmod +x "$LEARNING/scripts/session-end.sh" "$LEARNING/scripts/observe.sh"
  export LEARNING_SKILLS_SYNC=1
  unset LEARNING_SKILLS_OBSERVER 2>/dev/null || true
}

teardown() { rm -rf "$TMP"; }

# $1: user/assistant 行の合計数
make_transcript() {
  local n="$1" f="$TMP/transcript.jsonl" i
  : >"$f"
  for ((i = 0; i < n; i++)); do
    if ((i % 2 == 0)); then
      echo '{"type":"user","message":{"content":"hello"}}' >>"$f"
    else
      echo '{"type":"assistant","message":{"content":"hi"}}' >>"$f"
    fi
  done
  echo '{"type":"summary","summary":"noise"}' >>"$f"
  echo "$f"
}

# $1: transcript_path, $2: cwd
hook_input() {
  jq -n --arg t "$1" --arg c "$2" \
    '{hook_event_name:"SessionEnd", reason:"exit", transcript_path:$t, cwd:$c}'
}

run_hook() {
  run bash -c 'printf "%s" "$1" | "$2"' _ "$1" "$LEARNING/scripts/session-end.sh"
}

@test "happy path: observer が transcript と cwd を引数に起動される" {
  t=$(make_transcript 12)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -f "$LEARNING/observe-invoked.txt" ]
  [ "$(sed -n 1p "$LEARNING/observe-invoked.txt")" = "$t" ]
  [ "$(sed -n 2p "$LEARNING/observe-invoked.txt")" = "$PROJECT" ]
}

@test "happy path: epoch 秒が入ったロックファイルが作成される" {
  t=$(make_transcript 12)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ -f "$LEARNING/.lock" ]
  [[ "$(cat "$LEARNING/.lock")" =~ ^[0-9]+$ ]]
}

@test "再帰防止: LEARNING_SKILLS_OBSERVER=1 なら起動しない" {
  t=$(make_transcript 12)
  export LEARNING_SKILLS_OBSERVER=1
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "短小セッション: ターン数が10未満なら起動しない" {
  t=$(make_transcript 9)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "プロジェクト外: cwd に .claude も CLAUDE.md もなければ起動しない" {
  t=$(make_transcript 12)
  mkdir -p "$TMP/plain"
  run_hook "$(hook_input "$t" "$TMP/plain")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "transcript が存在しなければ起動しない" {
  run_hook "$(hook_input "$TMP/no-such.jsonl" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "stdin が不正な JSON でも exit 0 で起動しない" {
  run bash -c 'echo "not json" | "$1"' _ "$LEARNING/scripts/session-end.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "新しいロックがあれば起動しない" {
  t=$(make_transcript 12)
  date +%s >"$LEARNING/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "stale ロック（30分超）は奪取して起動する" {
  t=$(make_transcript 12)
  echo "$(($(date +%s) - 1801))" >"$LEARNING/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -f "$LEARNING/observe-invoked.txt" ]
}

@test "ロック内容が数値でなければ stale 扱いで起動する" {
  t=$(make_transcript 12)
  echo "garbage" >"$LEARNING/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -f "$LEARNING/observe-invoked.txt" ]
}

@test "observer がエラー終了しても hook は exit 0" {
  t=$(make_transcript 12)
  cat >"$LEARNING/scripts/observe.sh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$LEARNING/scripts/observe.sh"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
}
