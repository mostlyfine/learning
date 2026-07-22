#!/usr/bin/env bats

load helpers

setup() {
  setup_plugin_scaffold
  PROJECT="$TMP/project"
  DATA="$PROJECT/.learning"
  INSTINCTS="$DATA/instincts"
  mkdir -p "$PROJECT/.claude" "$INSTINCTS"
  printf 'engine=claude\n' >"$DATA/config"
  cp "$BATS_TEST_DIRNAME/../bin/session-start.sh" "$BIN/session-start.sh"
  chmod +x "$BIN/session-start.sh"
}

teardown() { rm -rf "$TMP"; }

# $1: id, $2: status, $3: confidence
make_instinct() {
  cat >"$INSTINCTS/$1.md" <<EOF
---
id: $1
type: correction
status: $2
confidence: $3
evidence_count: 1
promote_to: rules
created: 2026-01-01
updated: 2026-01-01
---

# Trigger
dummy

# Action
dummy

# Evidence
- 2026-01-01 (s1): dummy
EOF
}

hook_input() {
  jq -n --arg c "$1" '{hook_event_name:"SessionStart", source:"startup", cwd:$c}'
}

run_hook() {
  run bash -c 'printf "%s" "$1" | "$2"' _ "$1" "$BIN/session-start.sh"
}

@test "昇格資格1件: 案内が出る" {
  make_instinct ready-one active 0.7
  run_hook "$(hook_input "$PROJECT")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<learning-preflight>"* ]]
  [[ "$output" == *"昇格資格のある Instinct: 1 件"* ]]
}

@test "昇格資格0件・approaching1件: 出力なし" {
  make_instinct almost active 0.6
  run_hook "$(hook_input "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "昇格資格1件・approaching1件: 両方表示される" {
  make_instinct ready-one active 0.8
  make_instinct almost active 0.55
  run_hook "$(hook_input "$PROJECT")"
  [[ "$output" == *"昇格資格のある Instinct: 1 件"* ]]
  [[ "$output" == *"あと一歩（confidence 0.5〜0.69）: 1 件"* ]]
}

@test "status: promoted は対象外" {
  make_instinct done-one promoted 0.9
  run_hook "$(hook_input "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "status: rejected は対象外" {
  make_instinct rejected-one rejected 0.9
  run_hook "$(hook_input "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "confidence が数値でなければ無視する" {
  cat >"$INSTINCTS/broken.md" <<'EOF'
---
id: broken
status: active
confidence: N/A
---
EOF
  run_hook "$(hook_input "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "config が無ければ出力しない" {
  make_instinct ready-one active 0.8
  rm -f "$DATA/config"
  run_hook "$(hook_input "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "instincts ディレクトリが無ければ出力しない" {
  rm -rf "$INSTINCTS"
  run_hook "$(hook_input "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "instincts が空なら出力しない" {
  run_hook "$(hook_input "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "cwd が無ければ exit 0 で何もしない" {
  run bash -c 'echo "{}" | "$1"' _ "$BIN/session-start.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stdin が不正な JSON でも exit 0" {
  run bash -c 'echo "not json" | "$1"' _ "$BIN/session-start.sh"
  [ "$status" -eq 0 ]
}

@test "lib.sh が欠落していても exit 0" {
  make_instinct ready-one active 0.8
  rm -f "$BIN/lib.sh"
  run_hook "$(hook_input "$PROJECT")"
  [ "$status" -eq 0 ]
}

@test "jq が無ければ exit 0 で stderr に警告を出す" {
  make_instinct ready-one active 0.8
  run env PATH=/usr/bin:/bin bash -c 'printf "%s" "$1" | "$2"' \
    _ "$(hook_input "$PROJECT")" "$BIN/session-start.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"required command not found: jq"* ]]
  [[ "$output" != *"<learning-preflight>"* ]]
}

@test "git worktree: メイン作業ツリーの instincts を見る" {
  make_instinct ready-one active 0.9
  git -C "$PROJECT" init -q
  git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  WT="$TMP/wt"
  git -C "$PROJECT" worktree add -q "$WT" -b feature
  mkdir -p "$WT/.claude"
  run_hook "$(hook_input "$WT")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"昇格資格のある Instinct: 1 件"* ]]
}
