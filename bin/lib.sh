#!/usr/bin/env bash
# Shared library for bin/ scripts

# Default models per engine, used when LEARNING_SKILLS_MODEL isn't set
readonly DEFAULT_MODEL_CLAUDE="haiku"
readonly DEFAULT_MODEL_COPILOT="claude-haiku-4.5"

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

# Create .learning/.gitignore (excludes the whole directory from the repo) if it
# doesn't already exist.
ensure_learning_gitignore() {
  [ -f "$1/.gitignore" ] || echo '*' >"$1/.gitignore"
}

# Ensure the .learning data directory and its .gitignore exist. Shared by
# observe.sh, session-end.sh, and the status/acquire skills (via
# bin/ensure-learning-dir.sh), any of which may be the first to see a fresh project.
ensure_learning_dir() {
  mkdir -p "$1"
  ensure_learning_gitignore "$1"
}

# Check whether a required external command is available; warn on stderr if not
# (automatically captured if the caller redirects stdout/stderr to a log file)
check_required_command() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] required command not found: $1" >&2
  return 1
}

# Detect which engine to use for observation. Priority: (a) LEARNING_SKILLS_ENGINE
# if set to a supported value, (b) a reliable host-agent signal (CLAUDECODE=1) ->
# claude, (c) the copilot CLI on PATH -> copilot, (d) the codex CLI on PATH ->
# codex. Echoes the engine name, or nothing if none of the above are available.
detect_agent_engine() {
  case "${LEARNING_SKILLS_ENGINE:-}" in
  claude | codex | copilot)
    echo "$LEARNING_SKILLS_ENGINE"
    return 0
    ;;
  esac
  if [ "${CLAUDECODE:-}" = "1" ]; then
    echo "claude"
    return 0
  fi
  if command -v copilot >/dev/null 2>&1; then
    echo "copilot"
    return 0
  fi
  if command -v codex >/dev/null 2>&1; then
    echo "codex"
    return 0
  fi
}

# Echo the default model for an engine (empty if the engine has no default,
# e.g. codex which defers to the CLI's own default)
default_model_for_engine() {
  case "$1" in
  claude) echo "$DEFAULT_MODEL_CLAUDE" ;;
  copilot) echo "$DEFAULT_MODEL_COPILOT" ;;
  esac
}

# Resolve the model to use for an engine: LEARNING_SKILLS_MODEL overrides the
# engine's default when set
resolve_model_for_engine() {
  if [ -n "${LEARNING_SKILLS_MODEL:-}" ]; then
    echo "$LEARNING_SKILLS_MODEL"
  else
    default_model_for_engine "$1"
  fi
}

# Print a timestamped guidance line to stdout when no supported engine was detected
log_engine_guidance() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] no supported engine detected (checked: CLAUDECODE env, copilot/codex on PATH); observation skipped"
}
