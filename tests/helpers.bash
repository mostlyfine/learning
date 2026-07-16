#!/usr/bin/env bash
# 実プラグインと同じ <plugin>/bin 構成のモックプラグインディレクトリを作る。
# 呼び出し元の setup() で使えるよう TMP/PLUGIN/BIN をグローバル変数として設定する。
setup_plugin_scaffold() {
  # macOS では mktemp が /var/folders（/private/var へのシンボリックリンク）を返し、
  # git が物理パスに解決してパス比較が破綻するため物理パスに正規化する
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  PLUGIN="$TMP/plugin"
  BIN="$PLUGIN/bin"
  mkdir -p "$BIN" "$PLUGIN/.learning"
  cp "$BATS_TEST_DIRNAME/../bin/lib.sh" "$BIN/lib.sh"
  # エンジン設定（メモリー）: model 行なしの claude は haiku 既定
  printf 'engine=claude\n' >"$PLUGIN/.learning/config"
}
