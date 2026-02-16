# AGENTS.md

Instructions for AI coding agents working in this gem.

## Scope

- This repository is the `solid_events` Rails engine gem.
- Follow conventions and structure consistent with the solid_* family.
- Keep naming consistent with `SolidEvents`.
- `solid_events` owns observability and incident state only:
  - detect incidents from event/trace data
  - store traces/events/summaries/incidents
  - expose state via UI and API
  - manage incident lifecycle state transitions
- Do not add automation/executor logic here (code fixing, PR creation, QA execution, runtime adapters); that belongs in `solid_agents`.

## Development rules

- Keep changes small and composable.
- Update documentation when behavior or setup changes.
- Add or update Minitest tests for all behavior changes.
- Use Ruby `4.0.1`.

## Commit rules

- Never use `git add .`; stage files explicitly by path.
- Use one logical change per commit.
- Commit messages must be one direct sentence.
- Do not use commit prefixes like `feat:`, `fix:`, `chore:`, etc.
