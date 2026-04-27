# Claude Code defaults for this project

Session-level rules. Keep this file under ~20 lines — it's re-sent every turn.

## Planning & thinking (Opus 4.7)

- **Front-load the spec.** Intent, constraints, acceptance criteria, and file paths belong in the first user turn — extra turns add reasoning overhead.
- **Adaptive thinking.** 4.7 decides per-step whether to think. Steer via prompt: `think carefully and step-by-step` for hard problems, `respond directly` for lookups.
- **Plan before editing non-trivial work.** Multi-file, cross-layer, or fuzzy-criteria tasks — confirm the approach with the user first.

## Parallelism & delegation (4.7 delegates less by default)

- **Spawn subagents explicitly** when the work is genuinely independent: multi-file reads, parallel searches, batched migrations. Don't serialize independent work.
- **Use tools proactively.** Grep/Glob the repo thoroughly before answering — don't rely on memory.

## Compounding engineering

- **Learn from corrections.** When the user points out a mistake or preference, add a specific rule to this project's `CLAUDE.md` so it doesn't recur. `Don't import from lodash — we use remeda` beats `be careful with imports`.
