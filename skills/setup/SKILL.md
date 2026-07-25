---
name: setup
description: Runs first-time setup and reconfiguration of the analysis engine (claude / codex / copilot) the learning plugin uses for observation. Use for "set up learning," "I want to change the observation engine," fixing an "unknown engine" seen in the observer log, and delegation from status / acquire.
allowed-tools: Read, Glob, Grep, AskUserQuestion, Write(.learning/config), Write(.learning/.gitignore), Edit(.learning/config)
---

# /learning:setup — Configure the analysis engine

Saves the analysis engine used for session observation (the observer) to `.learning/config` under the project (cwd) root. If a config already exists, show its current value before overwriting it (reconfiguration).

## Procedure

1. Present the choices `claude` / `codex` / `copilot` (use the AskUserQuestion tool if available, otherwise confirm conversationally)
2. Write `.learning/config` based on the selection:
   - claude → `engine=claude` and `model=haiku`
   - copilot → `engine=copilot` and `model=claude-haiku-4.5`
   - codex → `engine=codex` only (leave the model to the CLI default)
3. If `.learning/.gitignore` doesn't exist, create it with content `*` (excludes all of `.learning`, including the config, from the repository)
4. Tell the user "Saved. Observation will be active starting from the end of the next session." If this was delegated from status / acquire, continue with the original processing

## Notes

- Configuration is per-project. Since it lives in `.learning` alongside the learning data, it survives plugin updates
- In a git worktree session, observation data is aggregated into the main worktree's `.learning`, so setup should also run from the main worktree
- Any value of `engine` other than the above prevents observation from running, and guidance on valid values is written to the project's `.learning/logs/observer.log`
