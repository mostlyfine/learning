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
