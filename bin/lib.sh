#!/usr/bin/env bash
# bin/ スクリプト共有ライブラリ

# 観察に使える分析エンジンの一覧（検証と案内メッセージの単一ソース）
readonly VALID_ENGINES="claude codex copilot"

# 呼び出し元スクリプトのディレクトリから plugin root（1階層上）を解決する
resolve_plugin_root() {
  (cd "$1/.." && pwd)
}

# key=value 形式の設定ファイルから値を読む（ファイル欠落・行なしは空）。
# 同一 key が複数あれば最後の値を採る
read_config_value() {
  [ -f "$1" ] || return 0
  sed -n "s/^$2=//p" "$1" | tail -1
}

is_valid_engine() {
  case " $VALID_ENGINES " in
  *" $1 "*) [ -n "$1" ] ;;
  *) return 1 ;;
  esac
}

# エンジン設定不備の案内行（タイムスタンプ付き）を stdout に出す。
# $1 が空なら未設定、非空なら不正値として扱う
log_engine_guidance() {
  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  if [ -z "$1" ]; then
    echo "[$ts] engine not configured; run /learning:setup to set up"
  else
    echo "[$ts] unknown engine: $1 (valid: ${VALID_ENGINES// /, }); run /learning:setup to fix the config"
  fi
}
