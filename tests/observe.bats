#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  LEARNING="$TMP/project/.claude/skills/learning"
  mkdir -p "$LEARNING/scripts" "$LEARNING/prompts" "$TMP/bin"
  cp "$BATS_TEST_DIRNAME/../.claude/skills/learning/scripts/observe.sh" \
    "$LEARNING/scripts/observe.sh"
  chmod +x "$LEARNING/scripts/observe.sh"
  # プロンプトのフィクスチャ（プレースホルダ置換を検証できる最小内容）
  printf 'T={{TRANSCRIPT_PATH}} I={{INSTINCTS_DIR}} D={{TODAY}}\n' \
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
  date +%s >"$LEARNING/.lock"
}

teardown() { rm -rf "$TMP"; }

run_observe() {
  run "$LEARNING/scripts/observe.sh" "$TMP/transcript.jsonl" "$TMP/project"
}

# 記録された引数リストから、指定フラグの次の値を返す
arg_after() {
  awk -v flag="$1" '$0 == flag { getline; print; exit }' "$TMP/claude-args.txt"
}

@test "claude を -p 付き・既定モデル haiku で起動する" {
  run_observe
  [ "$status" -eq 0 ]
  grep -qx -- "-p" "$TMP/claude-args.txt"
  [ "$(arg_after --model)" = "haiku" ]
  [ "$(arg_after --allowedTools)" = "Read,Write,Edit,Glob,Grep" ]
}

@test "LEARNING_SKILLS_MODEL でモデルを上書きできる" {
  export LEARNING_SKILLS_MODEL=opus
  run_observe
  [ "$(arg_after --model)" = "opus" ]
}

@test "プロンプトのプレースホルダが実パスに置換される" {
  run_observe
  prompt="$(arg_after -p)"
  [[ "$prompt" == *"T=$TMP/transcript.jsonl"* ]]
  [[ "$prompt" == *"I=$LEARNING/instincts"* ]]
  [[ "$prompt" == *"D=$(date +%F)"* ]]
}

@test "claude は LEARNING_SKILLS_OBSERVER=1 の環境で起動される" {
  run_observe
  [ "$(cat "$TMP/claude-env.txt")" = "1" ]
}

@test "instincts ディレクトリが作成される" {
  run_observe
  [ -d "$LEARNING/instincts" ]
}

@test "成功時にロックが削除される" {
  run_observe
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/.lock" ]
}

@test "claude 失敗時もロックが削除されエラーがログに出る" {
  export STUB_CLAUDE_EXIT=1
  run_observe
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/.lock" ]
  [[ "$output" == *"observer failed"* ]]
}
