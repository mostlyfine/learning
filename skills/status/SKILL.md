---
name: status
description: Read-only skill for checking the Instinct list and promotion eligibility. Triggered by "learning status."
allowed-tools: Read, Glob, Grep, Bash(git rev-parse:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/ensure-learning-dir.sh:*)
---

# /learning:status — List Instincts

Collects the frontmatter of accumulated Instincts (`.learning/instincts/*.md`) and lists them. Never edits any file.

## Ensuring the data directory exists

Before listing, run `${CLAUDE_PLUGIN_ROOT}/bin/ensure-learning-dir.sh <project_root>` via the Bash tool (`<project_root>` per "Assumptions" below) to make sure `.learning/` and its `.gitignore` exist, then continue with normal processing. The analysis engine itself is auto-detected by the observer on every run; there's no separate engine setup to check for here.

## Assumptions

- Instinct location: `.learning/instincts/` under the project root. In a git worktree session, however, data is aggregated into the main worktree, so the project root is the parent directory of the path returned by `git rev-parse --path-format=absolute --git-common-dir`
- Frontmatter used in the listing: `id`, `type`, `confidence`, `evidence_count`, `status` (see `${CLAUDE_PLUGIN_ROOT}/skills/acquire/SKILL.md` and the observer prompt `${CLAUDE_PLUGIN_ROOT}/hooks/prompts/observer.md` for the full schema)
- Promotion eligibility: `status: active` and `confidence >= 0.7`
- Approaching: `status: active` and `confidence` between 0.5 (inclusive) and 0.7 (exclusive)
- If the instincts directory doesn't exist or is empty, report "No Instincts have been accumulated yet. They'll build up automatically over more sessions" and stop

## Output format

| id | type | confidence | evidence | status |
|---|---|---|---|---|
| use-uv-not-pip | correction | 0.7 | 3 | active |

After the table, append "Promotion-eligible: N (check proposals with /learning:acquire)" if one or more Instincts qualify, or "No promotion-eligible Instincts" if none do. Then append "Almost there (confidence 0.5-0.69): N" if one or more Instincts are approaching (omit entirely if none are).
