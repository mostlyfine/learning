#!/usr/bin/env bash
# bin/ スクリプト共有ライブラリ

# 観察に使える分析エンジンの一覧（検証と案内メッセージの単一ソース）
readonly VALID_ENGINES="claude codex copilot"

# 呼び出し元スクリプトのディレクトリから plugin root（1階層上）を解決する
resolve_plugin_root() {
  (cd "$1/.." && pwd)
}

# git worktree からのセッションはメイン作業ツリーに集約する（worktree ごとに
# .learning が分散すると confidence が育たず、worktree 削除で学習データが消える）
resolve_project_root() {
  local cwd="$1" common_dir
  common_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [ -n "$common_dir" ] && [ -d "$(dirname "$common_dir")" ]; then
    dirname "$common_dir"
  else
    printf '%s\n' "$cwd"
  fi
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

# 必須外部コマンドの有無を確認する。無ければ stderr に警告を出す
# （呼び出し元が stdout/stderr をログファイルへリダイレクトしていれば自動的に記録される）
check_required_command() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] required command not found: $1" >&2
  return 1
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
