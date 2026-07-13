#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  PROJECT="$TMP/project"
  # プラグインは対象プロジェクトの外（プラグインキャッシュ相当）に置かれる。
  # 実プラグインと同じ <plugin>/hooks/{scripts,prompts} 構成にする
  PLUGIN="$TMP/plugin"
  LEARNING="$PLUGIN/hooks"
  DATA="$PROJECT/.learning"
  mkdir -p "$LEARNING/scripts" "$PLUGIN/.learning" "$PROJECT/.claude"
  cp "$BATS_TEST_DIRNAME/../hooks/scripts/session-end.sh" \
    "$LEARNING/scripts/session-end.sh"
  # エンジン設定（メモリー）: 未設定だと observer は起動しない
  printf 'engine=claude\n' >"$PLUGIN/.learning/config"
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

@test "happy path: epoch 秒が入ったロックファイルが .learning に作成される" {
  t=$(make_transcript 12)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ -f "$DATA/.lock" ]
  [[ "$(cat "$DATA/.lock")" =~ ^[0-9]+$ ]]
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
  mkdir -p "$DATA"
  date +%s >"$DATA/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "stale ロック（30分超）は奪取して起動する" {
  t=$(make_transcript 12)
  mkdir -p "$DATA"
  echo "$(($(date +%s) - 1801))" >"$DATA/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -f "$LEARNING/observe-invoked.txt" ]
}

@test "ロック内容が数値でなければ stale 扱いで起動する" {
  t=$(make_transcript 12)
  mkdir -p "$DATA"
  echo "garbage" >"$DATA/.lock"
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

@test "session_id がなければ第3引数は unknown になる" {
  t=$(make_transcript 12)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$(sed -n 3p "$LEARNING/observe-invoked.txt")" = "unknown" ]
}

@test "Claude 入力: session_id が第3引数として渡される" {
  t=$(make_transcript 12)
  input=$(jq -n --arg t "$t" --arg c "$PROJECT" \
    '{hook_event_name:"SessionEnd", session_id:"cl-1", transcript_path:$t, cwd:$c}')
  run_hook "$input"
  [ "$(sed -n 3p "$LEARNING/observe-invoked.txt")" = "cl-1" ]
}

@test "camelCase 入力（Copilot agentStop）: transcriptPath/sessionId で起動する" {
  t=$(make_transcript 12)
  input=$(jq -n --arg t "$t" --arg c "$PROJECT" \
    '{sessionId:"cop-1", timestamp:1, cwd:$c, transcriptPath:$t}')
  run_hook "$input"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$LEARNING/observe-invoked.txt")" = "$t" ]
  [ "$(sed -n 2p "$LEARNING/observe-invoked.txt")" = "$PROJECT" ]
  [ "$(sed -n 3p "$LEARNING/observe-invoked.txt")" = "cop-1" ]
}

@test "Cursor 入力: workspace_roots と conversation_id で起動する" {
  t=$(make_transcript 12)
  input=$(jq -n --arg t "$t" --arg c "$PROJECT" \
    '{hook_event_name:"stop", conversation_id:"cur-1", workspace_roots:[$c], transcript_path:$t}')
  run_hook "$input"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$LEARNING/observe-invoked.txt")" = "$PROJECT" ]
  [ "$(sed -n 3p "$LEARNING/observe-invoked.txt")" = "cur-1" ]
}

@test "非Claude形式 transcript: 行数フォールバックで12行なら起動する" {
  f="$TMP/other.jsonl"
  : >"$f"
  for ((i = 0; i < 12; i++)); do
    echo '{"role":"user","content":"x"}' >>"$f"
  done
  run_hook "$(hook_input "$f" "$PROJECT")"
  [ -f "$LEARNING/observe-invoked.txt" ]
}

@test "非Claude形式 transcript: 9行なら起動しない" {
  f="$TMP/other.jsonl"
  : >"$f"
  for ((i = 0; i < 9; i++)); do
    echo '{"role":"user","content":"x"}' >>"$f"
  done
  run_hook "$(hook_input "$f" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "増分ガード: 同一 transcript の再実行では起動しない" {
  t=$(make_transcript 12)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ -f "$LEARNING/observe-invoked.txt" ]
  rm -f "$LEARNING/observe-invoked.txt" "$DATA/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "増分ガード: MIN_TURNS 以上ターンが増えれば再分析する" {
  t=$(make_transcript 12)
  run_hook "$(hook_input "$t" "$PROJECT")"
  rm -f "$LEARNING/observe-invoked.txt" "$DATA/.lock"
  for ((i = 0; i < 10; i++)); do
    echo '{"type":"user","message":{"content":"more"}}' >>"$t"
  done
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ -f "$LEARNING/observe-invoked.txt" ]
}

@test "AGENTS.md のみのプロジェクトでも起動する" {
  t=$(make_transcript 12)
  mkdir -p "$TMP/agents-proj"
  touch "$TMP/agents-proj/AGENTS.md"
  run_hook "$(hook_input "$t" "$TMP/agents-proj")"
  [ -f "$LEARNING/observe-invoked.txt" ]
}

@test "エンジン設定（config）が無ければ起動しない" {
  t=$(make_transcript 12)
  rm -f "$PLUGIN/.learning/config"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}
