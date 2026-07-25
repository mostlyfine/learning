# learning-skills

A self-contained plugin that automatically observes AI coding agent sessions, accumulates behavioral patterns as Instincts, and promotes them into CLAUDE.md / skill / agent with user approval. Works with Claude Code as well as VS Code / Codex CLI / GitHub Copilot CLI / Cursor.

## How it works

```
end-of-session hook → guard checks → transcript analyzed by the configured engine (claude / codex / copilot)
  → accumulated in .learning/instincts/*.md (starts at confidence 0.3)
  → +0.2 each time it's re-observed in a different session
  → at 0.7+, becomes eligible for a /learning:acquire promotion proposal
```

All promotion requires user approval. Instincts that are still accumulating never affect session behavior.

For per-turn events (the Stop family), two guards prevent duplicate learning:
re-analysis only happens once turns have grown by `LEARNING_SKILLS_MIN_TURNS` or more since the last analysis (`.learning/analyzed.tsv`), and Instinct reinforcement is limited to once per session via the session id recorded in Evidence.

## Installation

Dependencies: bash, jq, and the CLI for whichever analysis engine you choose (claude, codex, or copilot)

### Claude Code

```
/plugin marketplace add mostlyfine/learning
/plugin install learning@learning-skills
```

The skills (`/learning:status`, `/learning:acquire` — also callable in natural language) and the SessionEnd/Stop hook are enabled automatically.

### VS Code (Copilot agent, Preview)

In the command palette, run "Chat: Install Plugin From Source" and point it at `https://github.com/mostlyfine/learning`. `.claude-plugin/plugin.json` and `hooks/hooks.json` are auto-detected, and observation runs on the `Stop` event.

### GitHub Copilot CLI

```
/plugin marketplace add mostlyfine/learning
/plugin install learning
```

Observation runs on the root `hooks.json`'s (Copilot format) `agentStop` event.

### Codex CLI

```
/plugin marketplace add mostlyfine/learning
/plugin install learning
```

Hooks are experimental, so you need to enable them in settings and grant trust approval for the plugin hook. Observation runs on the `Stop` event.

### Cursor (2.5+)

Install via `/plugin install`. If the plugin hook doesn't get registered, merge the contents of `hooks/configs/cursor-hooks.json` into `~/.cursor/hooks.json` (or the project's `.cursor/hooks.json`), rewriting the command paths to the actual path where you cloned the repo.

### Supported event mapping

| Platform | Event | Hook definition |
|---|---|---|
| Claude Code | `SessionStart` / `SessionEnd` / `Stop` | `hooks/hooks.json` |
| VS Code | `SessionStart` / `Stop` | `hooks/hooks.json` (auto-detects the Claude format) |
| Codex CLI | `SessionStart` / `Stop` | `hooks/hooks.json` (requires trust approval) |
| Copilot CLI | `agentStop` | root `hooks.json` (Copilot format; SessionStart equivalent planned) |
| Cursor | `stop` | `hooks/configs/cursor-hooks.json` (manual registration; SessionStart equivalent planned) |

To dogfood this repository itself, load this directory as a plugin for a single session with `claude --plugin-dir .`.

Runtime data (Instincts, logs, locks) lives under the project root in `.learning/` (created automatically on first run; `.learning/.gitignore` excludes all of it from commits). It's not placed under `.claude/` because headless claude is denied write access there by policy. Sessions in a git worktree aren't scattered per-worktree — they're aggregated into the main worktree's `.learning/` (so learning data isn't lost when a worktree is removed).

## Usage

- Accumulation is automatic (analysis runs at the end of any session with 10+ turns)
- If one or more Instincts are promotion-eligible, the count is announced automatically at session start (Claude Code / VS Code / Codex CLI; zero eligible means no output, and no LLM is used)
- `/learning:status` — list Instincts and check promotion eligibility / how close they are (confidence 0.5-0.69)
- `/learning:acquire` — approve / reject / hold each promotion proposal, one at a time
- `/learning:setup` — configure or reconfigure the analysis engine (delegated to automatically from status / acquire on first use)

## Engine configuration

The analysis engine used for observation is asked once per project, the first time, and saved to `.learning/config` under the project root (applied automatically after that; it survives plugin updates). Setup runs the first time `/learning:status` or `/learning:acquire` is run, and session observation doesn't work until then.

| Engine | Default model | Invocation |
|---|---|---|
| `claude` | `haiku` | `claude -p --allowedTools ...` |
| `codex` | CLI default | `codex exec --sandbox workspace-write` |
| `copilot` | `claude-haiku-4.5` | `copilot -p --no-ask-user` |

In environments where the command isn't available (e.g. Cursor's manual hook registration), create `.learning/config` by hand under the project root:

```
engine=claude
model=haiku
```

Any value of `engine` other than the above prevents observation from running, and guidance listing the valid engines is written to `.learning/logs/observer.log` (reconfigure with `/learning:setup`).

## Configuration (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `LEARNING_SKILLS_MIN_TURNS` | `10` | Minimum turn count for a session to be analyzed; also doubles as the turn-increment threshold required for re-analysis |

## Development

```bash
bats tests/                      # unit tests
tests/manual/verify-observer.sh  # observer acceptance check (consumes real API calls)
```
