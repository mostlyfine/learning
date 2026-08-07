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

@test "ensure_learning_gitignore は無ければ * で作成し、あれば上書きしない" {
  source "$BATS_TEST_DIRNAME/../bin/lib.sh"
  ensure_learning_gitignore "$TMP"
  [ "$(cat "$TMP/.gitignore")" = "*" ]
  printf 'custom\n' >"$TMP/.gitignore"
  ensure_learning_gitignore "$TMP"
  [ "$(cat "$TMP/.gitignore")" = "custom" ]
}

@test "ensure_learning_dir はディレクトリと gitignore を作成する" {
  source "$BATS_TEST_DIRNAME/../bin/lib.sh"
  ensure_learning_dir "$TMP/.learning"
  [ -d "$TMP/.learning" ]
  [ "$(cat "$TMP/.learning/.gitignore")" = "*" ]
}

@test "ensure_learning_dir は既存の gitignore を上書きしない" {
  source "$BATS_TEST_DIRNAME/../bin/lib.sh"
  mkdir -p "$TMP/.learning"
  printf 'custom\n' >"$TMP/.learning/.gitignore"
  ensure_learning_dir "$TMP/.learning"
  [ "$(cat "$TMP/.learning/.gitignore")" = "custom" ]
}

@test "check_required_command は存在するコマンドなら0を返し何も出力しない" {
  source "$BATS_TEST_DIRNAME/../bin/lib.sh"
  run check_required_command bash
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check_required_command は存在しないコマンドなら1を返し stderr に警告を出す" {
  source "$BATS_TEST_DIRNAME/../bin/lib.sh"
  run check_required_command no-such-command-xyz
  [ "$status" -eq 1 ]
  [[ "$output" == *"required command not found: no-such-command-xyz"* ]]
}

@test "detect_agent_engine は CLAUDECODE=1 なら claude を返す（copilot/codexがPATHにあっても最優先）" {
  mkdir -p "$TMP/bin"
  for c in copilot codex; do
    printf '#!/usr/bin/env bash\n' >"$TMP/bin/$c"
    chmod +x "$TMP/bin/$c"
  done
  run env CLAUDECODE=1 bash -c 'PATH="'"$TMP"'/bin"; . "'"$BATS_TEST_DIRNAME"'/../bin/lib.sh"; detect_agent_engine'
  [ "$output" = "claude" ]
}

@test "detect_agent_engine は CLAUDECODE 未設定で copilot が PATH にあれば copilot を返す" {
  mkdir -p "$TMP/bin"
  printf '#!/usr/bin/env bash\n' >"$TMP/bin/copilot"
  chmod +x "$TMP/bin/copilot"
  run env -u CLAUDECODE bash -c 'PATH="'"$TMP"'/bin"; . "'"$BATS_TEST_DIRNAME"'/../bin/lib.sh"; detect_agent_engine'
  [ "$output" = "copilot" ]
}

@test "detect_agent_engine は copilot が無く codex だけ PATH にあれば codex を返す" {
  mkdir -p "$TMP/bin"
  printf '#!/usr/bin/env bash\n' >"$TMP/bin/codex"
  chmod +x "$TMP/bin/codex"
  run env -u CLAUDECODE bash -c 'PATH="'"$TMP"'/bin"; . "'"$BATS_TEST_DIRNAME"'/../bin/lib.sh"; detect_agent_engine'
  [ "$output" = "codex" ]
}

@test "detect_agent_engine は copilot と codex が両方あれば copilot を優先する" {
  mkdir -p "$TMP/bin"
  for c in copilot codex; do
    printf '#!/usr/bin/env bash\n' >"$TMP/bin/$c"
    chmod +x "$TMP/bin/$c"
  done
  run env -u CLAUDECODE bash -c 'PATH="'"$TMP"'/bin"; . "'"$BATS_TEST_DIRNAME"'/../bin/lib.sh"; detect_agent_engine'
  [ "$output" = "copilot" ]
}

@test "detect_agent_engine は何も見つからなければ空を返す" {
  mkdir -p "$TMP/bin"
  run env -u CLAUDECODE bash -c 'PATH="'"$TMP"'/bin"; . "'"$BATS_TEST_DIRNAME"'/../bin/lib.sh"; detect_agent_engine'
  [ -z "$output" ]
}

@test "default_model_for_engine はエンジンごとの既定モデルを返す（codexは空）" {
  source "$BATS_TEST_DIRNAME/../bin/lib.sh"
  [ "$(default_model_for_engine claude)" = "haiku" ]
  [ "$(default_model_for_engine copilot)" = "claude-haiku-4.5" ]
  [ -z "$(default_model_for_engine codex)" ]
}

@test "resolve_model_for_engine は LEARNING_SKILLS_MODEL があればそれを優先する" {
  run env LEARNING_SKILLS_MODEL=custom-model bash -c '. "'"$BATS_TEST_DIRNAME"'/../bin/lib.sh"; resolve_model_for_engine claude'
  [ "$output" = "custom-model" ]
}

@test "resolve_model_for_engine は LEARNING_SKILLS_MODEL が無ければ既定モデルを返す" {
  run env -u LEARNING_SKILLS_MODEL bash -c '. "'"$BATS_TEST_DIRNAME"'/../bin/lib.sh"; resolve_model_for_engine claude'
  [ "$output" = "haiku" ]
  run env -u LEARNING_SKILLS_MODEL bash -c '. "'"$BATS_TEST_DIRNAME"'/../bin/lib.sh"; resolve_model_for_engine codex'
  [ -z "$output" ]
}

@test "log_engine_guidance は検出できなかった旨の案内を出す" {
  source "$BATS_TEST_DIRNAME/../bin/lib.sh"
  run log_engine_guidance
  [[ "$output" == *"no supported engine detected"* ]]
  [[ "$output" != *"/learning:setup"* ]]
}
