# Claude Code defaults for this project

Session-level rules. Keep this file under ~20 lines — it's re-sent every turn.

## Planning & thinking (Opus 4.7)

- **Front-load the spec.** Intent, constraints, acceptance criteria, and file paths belong in the first user turn — extra turns add reasoning overhead.
- **Adaptive thinking.** 4.7 decides per-step whether to think. Steer via prompt: `think carefully and step-by-step` for hard problems, `respond directly` for lookups.
- **Plan before editing non-trivial work.** Multi-file, cross-layer, or fuzzy-criteria tasks — confirm the approach with the user first.

## Parallelism & delegation (4.7 delegates less by default)

- **Spawn subagents explicitly** for genuinely independent work — don't serialize it. The `superpowers:dispatching-parallel-agents` skill owns the mechanics.
- **Use tools proactively.** Grep/Glob the repo thoroughly before answering — don't rely on memory.
- **Read before you write.** Before adding to a file, scan its exports, immediate callers, and shared utilities — duplicate helpers and silent breakage live there.

## Compounding engineering

- **Learn from corrections.** When the user points out a mistake or preference, add a specific rule to this project's `CLAUDE.md` so it doesn't recur. `Don't import from lodash — we use remeda` beats `be careful with imports`.

## PR sizing

- **Keep PRs under ~500 LoC for reviewability.** If a change is heading past that, propose a `gh stack` split before committing. Line count is a heuristic — generated boilerplate, codemods, and dense logic are context-dependent — so suggest, don't block.
