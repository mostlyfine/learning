#!/usr/bin/env bash
# Observer prompt acceptance check (consumes real API calls; manual run only).
# Creates a temporary project, has it actually analyze fixture transcripts, and
# checks whether the expected Instincts are generated.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# macOS's mktemp returns /var/folders (a symlink to /private/var), and cwd-relative
# permission rules stop matching absolute-path writes, so normalize to the physical path
work=$(cd "$(mktemp -d)" && pwd -P)
trap 'echo "Work directory: ${work} (delete it manually after checking)"' EXIT

project="$work/project"
mkdir -p "$project/.claude" "$project/.learning"
# The plugin lives outside the target project (equivalent to a plugin cache).
# Reproduce the real layout of <plugin_root>/bin and <plugin_root>/hooks
cp -R "$repo_root/bin" "$work/bin"
cp -R "$repo_root/hooks" "$work/hooks"
# No config file: the engine is auto-detected on every run. CLAUDECODE=1 selects
# claude with its default model (haiku)
export CLAUDECODE=1

echo "=== Running observer (engine=claude, model=haiku) ==="
date +%s >"$project/.learning/.lock"
"$work/bin/observe.sh" \
  "$repo_root/tests/fixtures/sample-transcript.jsonl" "$project" "verify-sess-1"

echo "=== Generated Instincts ==="
ls -la "$project/.learning/instincts/" || true
shopt -s nullglob
for f in "$project/.learning/instincts/"*.md; do
  echo "--- $f ---"
  cat "$f"
done

echo "=== Re-running with a transcript from a different session (verifying reinforcement) ==="
date +%s >"$project/.learning/.lock"
# Reinforcement (confidence increment) requires re-observation in a different session, so pass a different session id
"$work/bin/observe.sh" \
  "$repo_root/tests/fixtures/sample-transcript-2.jsonl" "$project" "verify-sess-2"

echo "=== Frontmatter after reinforcement ==="
grep -H -E '^(confidence|evidence_count):' "$project/.learning/instincts/"*.md || true

cat <<'CHECKLIST'

=== Acceptance checklist (visual check) ===
[ ] A correction-type Instinct was generated (use uv instead of pip)
[ ] An error-solution-type Instinct was generated (uv sync after uv add)
[ ] Each file's frontmatter has id/type/status/confidence/evidence_count/promote_to/created/updated
[ ] After the 1st run, confidence is 0.3 and status is active
[ ] After the 2nd run (a different session), confidence is reinforced to 0.5, evidence_count to 2, and the file count hasn't grown
[ ] No irrelevant or trivial Instincts were generated
CHECKLIST
