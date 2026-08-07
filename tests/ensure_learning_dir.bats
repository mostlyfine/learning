#!/usr/bin/env bats

load helpers

setup() {
  setup_plugin_scaffold
  PROJECT="$TMP/project"
  DATA="$PROJECT/.learning"
  mkdir -p "$PROJECT"
  cp "$BATS_TEST_DIRNAME/../bin/ensure-learning-dir.sh" "$BIN/ensure-learning-dir.sh"
  chmod +x "$BIN/ensure-learning-dir.sh"
}

teardown() { rm -rf "$TMP"; }

@test ".learning ディレクトリと .gitignore を作成する" {
  run "$BIN/ensure-learning-dir.sh" "$PROJECT"
  [ "$status" -eq 0 ]
  [ -d "$DATA" ]
  [ "$(cat "$DATA/.gitignore")" = "*" ]
}

@test "既存の .learning ディレクトリ・.gitignore を壊さない" {
  mkdir -p "$DATA/instincts"
  printf 'custom\n' >"$DATA/.gitignore"
  run "$BIN/ensure-learning-dir.sh" "$PROJECT"
  [ "$status" -eq 0 ]
  [ -d "$DATA/instincts" ]
  [ "$(cat "$DATA/.gitignore")" = "custom" ]
}

@test "project root 引数が無ければエラー終了する" {
  run "$BIN/ensure-learning-dir.sh"
  [ "$status" -ne 0 ]
}
