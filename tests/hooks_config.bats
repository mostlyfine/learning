#!/usr/bin/env bats
# hook 設定ファイルが参照するスクリプトパスの実在を検証する。
# スクリプト移動時に複数の設定ファイルの手動同期が漏れると、フックは exit 0 で
# 沈黙するため該当プラットフォームの観察だけが無言で無効化される（その回帰検出）。

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

# $1: 設定ファイル, $2: コマンドを取り出す jq フィルタ, $3: 置換するプレースホルダ
assert_hook_commands_exist() {
  local count=0 cmd path
  while IFS= read -r cmd; do
    count=$((count + 1))
    path="${cmd//\"/}"
    path="${path//$3/$REPO}"
    [ -x "$path" ]
  done < <(jq -r "$2" "$1")
  [ "$count" -gt 0 ]
}

@test "hooks/hooks.json (Claude形式): 全 command のスクリプトが実在し実行可能" {
  assert_hook_commands_exist "$REPO/hooks/hooks.json" \
    '.. | .command? // empty' '${CLAUDE_PLUGIN_ROOT}'
}

@test "hooks.json (Copilot形式): 全 bash のスクリプトが実在し実行可能" {
  assert_hook_commands_exist "$REPO/hooks.json" \
    '.. | .bash? // empty' '${CLAUDE_PLUGIN_ROOT}'
}

@test "hooks/configs/cursor-hooks.json: 全 command のスクリプトが実在し実行可能" {
  assert_hook_commands_exist "$REPO/hooks/configs/cursor-hooks.json" \
    '.. | .command? // empty' '/ABSOLUTE/PATH/TO/learning-skills'
}
