#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  # プラグインは対象プロジェクトの外（プラグインキャッシュ相当）に置かれる
  LEARNING="$TMP/plugin/skills/learning"
  DATA="$TMP/project/.learning"
  mkdir -p "$LEARNING/scripts" "$LEARNING/prompts" "$DATA" "$TMP/bin"
  cp "$BATS_TEST_DIRNAME/../skills/learning/scripts/observe.sh" \
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

@test "claude を -p 付き・既定モデル haiku で起動する" {
  run_observe
  [ "$status" -eq 0 ]
  grep -qx -- "-p" "$TMP/claude-args.txt"
  [ "$(arg_after --model)" = "haiku" ]
  [ "$(arg_after --allowedTools)" = "Read,Glob,Grep,Write(.learning/instincts/**),Edit(.learning/instincts/**)" ]
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
