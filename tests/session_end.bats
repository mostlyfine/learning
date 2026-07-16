#!/usr/bin/env bats

load helpers

setup() {
  setup_plugin_scaffold
  PROJECT="$TMP/project"
  DATA="$PROJECT/.learning"
  mkdir -p "$PROJECT/.claude"
  cp "$BATS_TEST_DIRNAME/../bin/session-end.sh" "$BIN/session-end.sh"
  # observe.sh スタブ: 呼び出し引数をプラグインルートに記録するだけ
  cat >"$BIN/observe.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$(cd "$(dirname "$0")/.." && pwd)/observe-invoked.txt"
STUB
  chmod +x "$BIN/session-end.sh" "$BIN/observe.sh"
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
  run bash -c 'printf "%s" "$1" | "$2"' _ "$1" "$BIN/session-end.sh"
}

@test "happy path: observer が transcript と cwd を引数に起動される" {
  t=$(make_transcript 12)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -f "$PLUGIN/observe-invoked.txt" ]
  [ "$(sed -n 1p "$PLUGIN/observe-invoked.txt")" = "$t" ]
  [ "$(sed -n 2p "$PLUGIN/observe-invoked.txt")" = "$PROJECT" ]
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
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
}

@test "短小セッション: ターン数が10未満なら起動しない" {
  t=$(make_transcript 9)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
}

@test "プロジェクト外: cwd に .claude も CLAUDE.md もなければ起動しない" {
  t=$(make_transcript 12)
  mkdir -p "$TMP/plain"
  run_hook "$(hook_input "$t" "$TMP/plain")"
  [ "$status" -eq 0 ]
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
}

@test "transcript が存在しなければ起動しない" {
  run_hook "$(hook_input "$TMP/no-such.jsonl" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
}

@test "stdin が不正な JSON でも exit 0 で起動しない" {
  run bash -c 'echo "not json" | "$1"' _ "$BIN/session-end.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
}

@test "新しいロックがあれば起動しない" {
  t=$(make_transcript 12)
  mkdir -p "$DATA"
  date +%s >"$DATA/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
}

@test "stale ロック（30分超）は奪取して起動する" {
  t=$(make_transcript 12)
  mkdir -p "$DATA"
  echo "$(($(date +%s) - 1801))" >"$DATA/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -f "$PLUGIN/observe-invoked.txt" ]
}

@test "ロック内容が数値でなければ stale 扱いで起動する" {
  t=$(make_transcript 12)
  mkdir -p "$DATA"
  echo "garbage" >"$DATA/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -f "$PLUGIN/observe-invoked.txt" ]
}

@test "observer がエラー終了しても hook は exit 0" {
  t=$(make_transcript 12)
  cat >"$BIN/observe.sh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$BIN/observe.sh"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
}

@test "session_id がなければ第3引数は unknown になる" {
  t=$(make_transcript 12)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$(sed -n 3p "$PLUGIN/observe-invoked.txt")" = "unknown" ]
}

@test "Claude 入力: session_id が第3引数として渡される" {
  t=$(make_transcript 12)
  input=$(jq -n --arg t "$t" --arg c "$PROJECT" \
    '{hook_event_name:"SessionEnd", session_id:"cl-1", transcript_path:$t, cwd:$c}')
  run_hook "$input"
  [ "$(sed -n 3p "$PLUGIN/observe-invoked.txt")" = "cl-1" ]
}

@test "camelCase 入力（Copilot agentStop）: transcriptPath/sessionId で起動する" {
  t=$(make_transcript 12)
  input=$(jq -n --arg t "$t" --arg c "$PROJECT" \
    '{sessionId:"cop-1", timestamp:1, cwd:$c, transcriptPath:$t}')
  run_hook "$input"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$PLUGIN/observe-invoked.txt")" = "$t" ]
  [ "$(sed -n 2p "$PLUGIN/observe-invoked.txt")" = "$PROJECT" ]
  [ "$(sed -n 3p "$PLUGIN/observe-invoked.txt")" = "cop-1" ]
}

@test "Cursor 入力: workspace_roots と conversation_id で起動する" {
  t=$(make_transcript 12)
  input=$(jq -n --arg t "$t" --arg c "$PROJECT" \
    '{hook_event_name:"stop", conversation_id:"cur-1", workspace_roots:[$c], transcript_path:$t}')
  run_hook "$input"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$PLUGIN/observe-invoked.txt")" = "$PROJECT" ]
  [ "$(sed -n 3p "$PLUGIN/observe-invoked.txt")" = "cur-1" ]
}

@test "非Claude形式 transcript: 行数フォールバックで12行なら起動する" {
  f="$TMP/other.jsonl"
  : >"$f"
  for ((i = 0; i < 12; i++)); do
    echo '{"role":"user","content":"x"}' >>"$f"
  done
  run_hook "$(hook_input "$f" "$PROJECT")"
  [ -f "$PLUGIN/observe-invoked.txt" ]
}

@test "非Claude形式 transcript: 9行なら起動しない" {
  f="$TMP/other.jsonl"
  : >"$f"
  for ((i = 0; i < 9; i++)); do
    echo '{"role":"user","content":"x"}' >>"$f"
  done
  run_hook "$(hook_input "$f" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
}

@test "増分ガード: 同一 transcript の再実行では起動しない" {
  t=$(make_transcript 12)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ -f "$PLUGIN/observe-invoked.txt" ]
  rm -f "$PLUGIN/observe-invoked.txt" "$DATA/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
}

@test "増分ガード: MIN_TURNS 以上ターンが増えれば再分析する" {
  t=$(make_transcript 12)
  run_hook "$(hook_input "$t" "$PROJECT")"
  rm -f "$PLUGIN/observe-invoked.txt" "$DATA/.lock"
  for ((i = 0; i < 10; i++)); do
    echo '{"type":"user","message":{"content":"more"}}' >>"$t"
  done
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ -f "$PLUGIN/observe-invoked.txt" ]
}

@test "AGENTS.md のみのプロジェクトでも起動する" {
  t=$(make_transcript 12)
  mkdir -p "$TMP/agents-proj"
  touch "$TMP/agents-proj/AGENTS.md"
  run_hook "$(hook_input "$t" "$TMP/agents-proj")"
  [ -f "$PLUGIN/observe-invoked.txt" ]
}

@test "git worktree: データはメイン作業ツリーの .learning に集約される" {
  t=$(make_transcript 12)
  git -C "$PROJECT" init -q
  git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  WT="$TMP/wt"
  git -C "$PROJECT" worktree add -q "$WT" -b feature
  mkdir -p "$WT/.claude"
  run_hook "$(hook_input "$t" "$WT")"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$PLUGIN/observe-invoked.txt")" = "$PROJECT" ]
  [ -f "$DATA/.lock" ]
  [ ! -d "$WT/.learning" ]
}

@test "git repo 直下のセッションは従来どおり cwd の .learning を使う" {
  t=$(make_transcript 12)
  git -C "$PROJECT" init -q
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$PLUGIN/observe-invoked.txt")" = "$PROJECT" ]
  [ -f "$DATA/.lock" ]
}

@test "エンジン設定（config）が無ければ起動しない" {
  t=$(make_transcript 12)
  rm -f "$PLUGIN/.learning/config"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
}

@test "unknown engine: analyzed.tsv に記録せず起動もせず、案内が observer.log に残る" {
  t=$(make_transcript 12)
  printf 'engine=typo\n' >"$PLUGIN/.learning/config"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
  [ ! -f "$DATA/analyzed.tsv" ]
  grep -q "unknown engine: typo" "$DATA/logs/observer.log"
  grep -q "/learning:setup" "$DATA/logs/observer.log"
}

@test "unknown engine のセッションは設定修正後に分析される（学習機会を失わない）" {
  t=$(make_transcript 12)
  printf 'engine=typo\n' >"$PLUGIN/.learning/config"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
  printf 'engine=claude\n' >"$PLUGIN/.learning/config"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ -f "$PLUGIN/observe-invoked.txt" ]
}

@test "config の engine 行が空でも起動せず未設定の案内が残る" {
  t=$(make_transcript 12)
  printf 'model=haiku\n' >"$PLUGIN/.learning/config"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
  [ ! -f "$DATA/analyzed.tsv" ]
  grep -q "engine not configured" "$DATA/logs/observer.log"
}

@test "lib.sh が欠落していても exit 0 で観察を諦める" {
  t=$(make_transcript 12)
  rm -f "$BIN/lib.sh"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$PLUGIN/observe-invoked.txt" ]
  [[ "$output" == *"observation disabled"* ]]
}
