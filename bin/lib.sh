#!/usr/bin/env bash
# Shared library for bin/ scripts

# List of analysis engines available for observation (single source for validation and guidance messages)
readonly VALID_ENGINES="claude codex copilot"

# Resolve the plugin root (one level up) from the calling script's directory
resolve_plugin_root() {
  (cd "$1/.." && pwd)
}

# Sessions from a git worktree are aggregated into the main worktree (if .learning
# were scattered per worktree, confidence would never grow, and learning data
# would be lost when the worktree is removed)
resolve_project_root() {
  local cwd="$1" common_dir
  common_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [ -n "$common_dir" ] && [ -d "$(dirname "$common_dir")" ]; then
    dirname "$common_dir"
  else
    printf '%s\n' "$cwd"
  fi
}

# Read a value from a key=value config file (empty if the file or the line is missing).
# If the same key appears multiple times, the last value wins
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

# Check whether a required external command is available; warn on stderr if not
# (automatically captured if the caller redirects stdout/stderr to a log file)
check_required_command() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] required command not found: $1" >&2
  return 1
}

# Print a timestamped guidance line for an engine misconfiguration to stdout.
# Empty $1 is treated as "not configured", non-empty as "invalid value"
log_engine_guidance() {
  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  if [ -z "$1" ]; then
    echo "[$ts] engine not configured; run /learning:setup to set up"
  else
    echo "[$ts] unknown engine: $1 (valid: ${VALID_ENGINES// /, }); run /learning:setup to fix the config"
  fi
}
