#!/usr/bin/env bash
# 実プラグインと同じ <plugin>/bin 構成のモックプラグインディレクトリを作る。
# 呼び出し元の setup() で使えるよう TMP/PLUGIN/BIN をグローバル変数として設定する。
setup_plugin_scaffold() {
  # macOS では mktemp が /var/folders（/private/var へのシンボリックリンク）を返し、
  # git が物理パスに解決してパス比較が破綻するため物理パスに正規化する
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  PLUGIN="$TMP/plugin"
  BIN="$PLUGIN/bin"
  mkdir -p "$BIN"
  cp "$BATS_TEST_DIRNAME/../bin/lib.sh" "$BIN/lib.sh"
}

# jq だけを含む隔離された PATH 用ディレクトリを $TMP/isolated-bin に作る。
# jq の実体が置かれたディレクトリを丸ごと PATH に含めると、同じディレクトリに
# 実在する copilot/codex まで誤検出してしまうため、jq だけをシムとして孤立させる。
isolate_jq_only() {
  mkdir -p "$TMP/isolated-bin"
  ln -s "$(command -v jq)" "$TMP/isolated-bin/jq"
}
