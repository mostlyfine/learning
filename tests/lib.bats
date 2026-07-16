#!/usr/bin/env bats

setup() {
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
}

teardown() { rm -rf "$TMP"; }

@test "resolve_plugin_root はスクリプトディレクトリの1階層上を返す" {
  mkdir -p "$TMP/plugin/bin"
  source "$BATS_TEST_DIRNAME/../bin/lib.sh"
  result="$(resolve_plugin_root "$TMP/plugin/bin")"
  [ "$result" = "$TMP/plugin" ]
}

@test "read_config_value は key=value の最後の値を返し、欠落時は空を返す" {
  source "$BATS_TEST_DIRNAME/../bin/lib.sh"
  printf 'engine=claude\nmodel=haiku\nengine=codex\n' >"$TMP/config"
  [ "$(read_config_value "$TMP/config" engine)" = "codex" ]
  [ "$(read_config_value "$TMP/config" model)" = "haiku" ]
  [ -z "$(read_config_value "$TMP/config" missing)" ]
  [ -z "$(read_config_value "$TMP/no-such-file" engine)" ]
}

@test "is_valid_engine は claude/codex/copilot のみ受理する" {
  source "$BATS_TEST_DIRNAME/../bin/lib.sh"
  is_valid_engine claude
  is_valid_engine codex
  is_valid_engine copilot
  ! is_valid_engine gpt
  ! is_valid_engine ""
}

@test "log_engine_guidance は空なら未設定案内、不正値なら有効値一覧を出す" {
  source "$BATS_TEST_DIRNAME/../bin/lib.sh"
  run log_engine_guidance ""
  [[ "$output" == *"engine not configured"* ]]
  [[ "$output" == *"/learning:setup"* ]]
  run log_engine_guidance gpt
  [[ "$output" == *"unknown engine: gpt"* ]]
  [[ "$output" == *"claude, codex, copilot"* ]]
  [[ "$output" == *"/learning:setup"* ]]
}
