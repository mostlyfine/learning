#!/usr/bin/env bash
# CLI wrapper for skills (status/acquire) to ensure the project's .learning
# directory and .gitignore exist before reading Instincts from it.
set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lib.sh" 2>/dev/null || {
  echo "learning-skills: $script_dir/lib.sh not found; setup disabled" >&2
  exit 1
}

project_root="${1:?project root required}"
ensure_learning_dir "$project_root/.learning"
