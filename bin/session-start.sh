#!/usr/bin/env bash
# SessionStart hook: announce the count of promotion-eligible Instincts at session start.
# Lightweight scan only, no LLM involved (just reads frontmatter). Learning-related
# failures must never block session start, so this always exits 0.
set -u

# $1: instinct file, $2: frontmatter key name
frontmatter_value() {
  awk -v key="^$2:" '
    /^---$/ { c++; next }
    c==1 && $0 ~ key { sub(key" *", ""); print; exit }
    c>=2 { exit }
  ' "$1"
}

main() {
  local script_dir input cwd
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  source "$script_dir/lib.sh" 2>/dev/null || return 0
  check_required_command jq || return 0

  input=$(cat) || return 0
  cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null) || return 0
  { [ -n "$cwd" ] && [ -d "$cwd" ]; } || return 0

  local project_root data_dir instincts_dir
  project_root=$(resolve_project_root "$cwd")
  data_dir="$project_root/.learning"
  instincts_dir="$data_dir/instincts"

  # Don't nag every session on projects with no config or no accumulated instincts
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
    echo "Promotion-eligible Instincts: ${ready} (check with /learning:acquire)"
    [ "$approaching" -gt 0 ] && echo "Almost there (confidence 0.5-0.69): ${approaching}"
    echo "</learning-preflight>"
  }
  return 0
}

main || true
exit 0
