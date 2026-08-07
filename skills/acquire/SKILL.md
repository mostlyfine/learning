---
name: acquire
description: Promotion review of accumulated Instincts (approve/reject/hold). Triggered by "promote the instincts."
allowed-tools: Read, Glob, Grep, AskUserQuestion, Bash(git rev-parse:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/ensure-learning-dir.sh:*), Edit(.learning/instincts/**), Edit(.claude/rules/**), Edit(.claude/skills/**), Edit(.claude/agents/**), Edit(CLAUDE.md), Write(.claude/rules/**), Write(.claude/skills/**), Write(.claude/agents/**)
---

# /learning:acquire — Instinct promotion proposals

Promotes accumulated Instincts (`.learning/instincts/*.md`) that have reached the confidence threshold, with user approval.

## Ensuring the data directory exists

Before collecting Instincts, run `${CLAUDE_PLUGIN_ROOT}/bin/ensure-learning-dir.sh <project_root>` via the Bash tool (`<project_root>` per "Assumptions" below) to make sure `.learning/` and its `.gitignore` exist, then continue with normal processing. The analysis engine itself is auto-detected by the observer on every run; there's no separate engine setup to check for here.

## Assumptions

- Instinct location: `.learning/instincts/` under the project root. In a git worktree session, however, data is aggregated into the main worktree, so the project root is the parent directory of the path returned by `git rev-parse --path-format=absolute --git-common-dir` (editing files on the main-tree side may trigger a confirmation prompt — that's expected)
- Instinct file frontmatter: `id`, `type`(correction|error-solution|workflow|insight), `status`(active|promoted|rejected), `confidence`, `evidence_count`, `promote_to`(rules|instructions|skill|agent), `created`, `updated`
- Promotion eligibility: `status: active` and `confidence >= 0.7`
- If the instincts directory doesn't exist or is empty, report "No Instincts have been accumulated yet. They'll build up automatically over more sessions" and stop

## Procedure

1. Collect Instincts meeting the promotion eligibility bar (see Assumptions). If there are none, report "No promotion-eligible Instincts" along with the current highest confidence, and stop
2. For each Instinct, decide the promotion destination. Start from the frontmatter's `promote_to` and change it if the content doesn't fit:
   - `instructions` → append as a rule to the project's `CLAUDE.md` (add a new section at the end if none fits)
   - `rules` → create a new path-scoped rule definition at `.claude/rules/<id>.md`
   - `skill` → improve an existing skill's procedure, or create a new `.claude/skills/<id>/SKILL.md`
   - `agent` → create a new subagent definition at `.claude/agents/<id>.md`
3. Read the current state of the destination file and draft a concrete change proposal (a diff, or the full text of a new file)
4. Present each Instinct to the user **one at a time** and confirm approve / reject / hold (use the AskUserQuestion tool if available, otherwise ask conversationally). Include the Instinct's Trigger/Action, evidence_count, and a summary of the proposed change in the question
   - **Approve** → apply the change, update the Instinct's frontmatter to `status: promoted`, and append `promoted_to: <destination path>`
   - **Reject** → update to `status: rejected` (the observer will no longer recreate the same kind of Instinct)
   - **Hold** → change nothing (carries over to the next `/learning:acquire` run)
5. After processing all of them, show a summary of the outcome (counts of approved/rejected/held, and the destination paths)

## Constraints

- Never modify a promotion-destination file without user approval
- Never apply multiple Instincts in a single approval (confirm one at a time)
- Never manually rewrite an instinct file's confidence or evidence (that's the observer's job)
