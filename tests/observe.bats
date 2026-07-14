#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  # プラグインは対象プロジェクトの外（プラグインキャッシュ相当）に置かれる。
  # 実プラグインと同じ <plugin>/hooks/{scripts,prompts} 構成にする
  PLUGIN="$TMP/plugin"
  LEARNING="$PLUGIN/hooks"
  DATA="$TMP/project/.learning"
  mkdir -p "$LEARNING/scripts" "$LEARNING/prompts" "$PLUGIN/.learning" "$DATA" "$TMP/bin"
  cp "$BATS_TEST_DIRNAME/../hooks/scripts/observe.sh" \
    "$LEARNING/scripts/observe.sh"
  chmod +x "$LEARNING/scripts/observe.sh"
  # エンジン設定（メモリー）: model 行なしの claude は haiku 既定
  printf 'engine=claude\n' >"$PLUGIN/.learning/config"
  # プロンプトのフィクスチャ（プレースホルダ置換を検証できる最小内容）
  printf 'T={{TRANSCRIPT_PATH}} I={{INSTINCTS_DIR}} D={{TODAY}} S={{SESSION_ID}}\n' \
    >"$LEARNING/prompts/observer.md"
  # claude スタブ: 引数と環境変数を記録する
  cat >"$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${STUB_DIR:?}/claude-args.txt"
echo "${LEARNING_SKILLS_OBSERVER:-unset}" >"${STUB_DIR:?}/claude-env.txt"
exit "${STUB_CLAUDE_EXIT:-0}"
STUB
  chmod +x "$TMP/bin/claude"
  export PATH="$TMP/bin:$PATH"
  export STUB_DIR="$TMP"
  echo '{"type":"user","message":{"content":"x"}}' >"$TMP/transcript.jsonl"
  date +%s >"$DATA/.lock"
}

teardown() { rm -rf "$TMP"; }

run_observe() {
  run "$LEARNING/scripts/observe.sh" "$TMP/transcript.jsonl" "$TMP/project"
}

# 記録された引数リストから、指定フラグの次の値を返す
arg_after() {
  awk -v flag="$1" '$0 == flag { getline; print; exit }' "$TMP/claude-args.txt"
}

# $1: エンジン名。引数と環境変数を記録するスタブを PATH に置く
make_engine_stub() {
  cat >"$TMP/bin/$1" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${STUB_DIR:?}/engine-args.txt"
echo "${LEARNING_SKILLS_OBSERVER:-unset}" >"${STUB_DIR:?}/engine-env.txt"
STUB
  chmod +x "$TMP/bin/$1"
}

# engine-args.txt から、指定フラグの次の値を返す
arg_in_engine() {
  awk -v flag="$1" '$0 == flag { getline; print; exit }' "$TMP/engine-args.txt"
}

@test "claude を -p 付き・既定モデル haiku で起動する" {
  run_observe
  [ "$status" -eq 0 ]
  grep -qx -- "-p" "$TMP/claude-args.txt"
  [ "$(arg_after --model)" = "haiku" ]
  [ "$(arg_after --allowedTools)" = "Read,Glob,Grep,Write(.learning/instincts/**),Edit(.learning/instincts/**)" ]
}

@test "config の model 行でモデルを上書きできる" {
  printf 'engine=claude\nmodel=opus\n' >"$PLUGIN/.learning/config"
  run_observe
  [ "$(arg_after --model)" = "opus" ]
}

@test "プロンプトのプレースホルダが実パスに置換される" {
  run_observe
  prompt="$(arg_after -p)"
  [[ "$prompt" == *"T=$TMP/transcript.jsonl"* ]]
  [[ "$prompt" == *"I=$DATA/instincts"* ]]
  [[ "$prompt" == *"D=$(date +%F)"* ]]
}

@test "claude は LEARNING_SKILLS_OBSERVER=1 の環境で起動される" {
  run_observe
  [ "$(cat "$TMP/claude-env.txt")" = "1" ]
}

@test "instincts ディレクトリが .learning 配下に作成される" {
  run_observe
  [ -d "$DATA/instincts" ]
}

@test ".learning/.gitignore が全除外の内容で作成される" {
  run_observe
  [ -f "$DATA/.gitignore" ]
  [ "$(cat "$DATA/.gitignore")" = "*" ]
}

@test "成功時にロックが削除される" {
  run_observe
  [ "$status" -eq 0 ]
  [ ! -f "$DATA/.lock" ]
}

@test "claude 失敗時もロックが削除されエラーがログに出る" {
  export STUB_CLAUDE_EXIT=1
  run_observe
  [ "$status" -eq 0 ]
  [ ! -f "$DATA/.lock" ]
  [[ "$output" == *"observer failed"* ]]
}

@test "プロンプトファイルが存在しない場合は claude を起動せずロックを削除する" {
  rm -f "$LEARNING/prompts/observer.md"
  run_observe
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/claude-args.txt" ]
  [ ! -f "$DATA/.lock" ]
  [[ "$output" == *"observer prompt missing"* ]]
}

@test "config が無ければエンジンを起動せずログを出してロックを削除する" {
  rm -f "$PLUGIN/.learning/config"
  run_observe
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/claude-args.txt" ]
  [ ! -f "$DATA/.lock" ]
  [[ "$output" == *"engine not configured"* ]]
}

@test "engine=codex: codex exec が sandbox 付き・model なしで起動される" {
  make_engine_stub codex
  printf 'engine=codex\n' >"$PLUGIN/.learning/config"
  run_observe
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/claude-args.txt" ]
  [ "$(sed -n 1p "$TMP/engine-args.txt")" = "exec" ]
  grep -qx -- "--sandbox" "$TMP/engine-args.txt"
  [ "$(arg_in_engine --sandbox)" = "workspace-write" ]
  ! grep -qx -- "--model" "$TMP/engine-args.txt"
  [ "$(cat "$TMP/engine-env.txt")" = "1" ]
}

@test "engine=codex: config の model 行があれば --model が付く" {
  make_engine_stub codex
  printf 'engine=codex\nmodel=gpt-5.4-mini\n' >"$PLUGIN/.learning/config"
  run_observe
  [ "$(arg_in_engine --model)" = "gpt-5.4-mini" ]
}

@test "engine=copilot: copilot -p が --no-ask-user と --model 付きで起動される" {
  make_engine_stub copilot
  printf 'engine=copilot\nmodel=claude-haiku-4.5\n' >"$PLUGIN/.learning/config"
  run_observe
  [ "$status" -eq 0 ]
  grep -qx -- "-p" "$TMP/engine-args.txt"
  grep -qx -- "--no-ask-user" "$TMP/engine-args.txt"
  [ "$(arg_in_engine --model)" = "claude-haiku-4.5" ]
  [ "$(cat "$TMP/engine-env.txt")" = "1" ]
}

@test "未知のエンジンは実行せず有効値の案内をログに出して exit 0 する" {
  make_engine_stub myengine
  printf 'engine=myengine\n' >"$PLUGIN/.learning/config"
  run_observe
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/claude-args.txt" ]
  [ ! -f "$TMP/engine-args.txt" ]
  [[ "$output" == *"unknown engine: myengine"* ]]
  [[ "$output" == *"claude, codex, copilot"* ]]
  [[ "$output" == *"/learning:status"* ]]
}

@test "{{SESSION_ID}} が第3引数で置換される" {
  run "$LEARNING/scripts/observe.sh" "$TMP/transcript.jsonl" "$TMP/project" "sess-42"
  prompt="$(arg_after -p)"
  [[ "$prompt" == *"S=sess-42"* ]]
}

@test "{{SESSION_ID}} は第3引数がなければ unknown になる" {
  run_observe
  prompt="$(arg_after -p)"
  [[ "$prompt" == *"S=unknown"* ]]
}
