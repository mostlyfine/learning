#!/usr/bin/env bash
# SessionStart hook: 昇格資格のある Instinct 件数をセッション開始時に案内する。
# LLM を使わない軽量スキャンのみ（frontmatter を読むだけ）。学習系の失敗は
# セッション開始を妨げてはならないため、常に exit 0 する。
set -u

# $1: instinct ファイル, $2: frontmatter のキー名
frontmatter_value() {
  awk -v key="^$2:" '
    /^---$/ { c++; next }
    c==1 && $0 ~ key { sub(key" *", ""); print; exit }
    c>=2 { exit }
  ' "$1"
}

main() {
  local input cwd
  input=$(cat) || return 0
  cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null) || return 0
  { [ -n "$cwd" ] && [ -d "$cwd" ]; } || return 0

  local script_dir project_root data_dir instincts_dir
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  source "$script_dir/lib.sh" 2>/dev/null || return 0
  project_root=$(resolve_project_root "$cwd")
  data_dir="$project_root/.learning"
  instincts_dir="$data_dir/instincts"

  # 未設定・未蓄積のプロジェクトでは毎セッション nag しない
  [ -f "$data_dir/config" ] || return 0
  [ -d "$instincts_dir" ] || return 0

  local f status confidence ready=0 approaching=0
  for f in "$instincts_dir"/*.md; do
    [ -f "$f" ] || continue
    status=$(frontmatter_value "$f" status)
    [ "$status" = "active" ] || continue
    confidence=$(frontmatter_value "$f" confidence)
    [[ "$confidence" =~ ^[0-9]+(\.[0-9]+)?$ ]] || continue
    if awk -v c="$confidence" 'BEGIN{exit !(c >= 0.7)}'; then
      ready=$((ready + 1))
    elif awk -v c="$confidence" 'BEGIN{exit !(c >= 0.5)}'; then
      approaching=$((approaching + 1))
    fi
  done

  [ "$ready" -gt 0 ] || return 0

  {
    echo "<learning-preflight>"
    echo "昇格資格のある Instinct: ${ready} 件（/learning:acquire で確認できます）"
    [ "$approaching" -gt 0 ] && echo "あと一歩（confidence 0.5〜0.69）: ${approaching} 件"
    echo "</learning-preflight>"
  }
  return 0
}

main || true
exit 0
