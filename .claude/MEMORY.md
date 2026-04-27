# Project memory

Durable conventions Claude Code should follow in this project. To make this auto-loaded every turn, add `@.claude/MEMORY.md` to your project's `CLAUDE.md` alongside `@.claude/claude-defaults.md`.

## Slash command triggers

When the user phrases a request that maps to one of this repo's slash commands, invoke the command directly rather than improvising. The command body lives in `.claude/commands/<name>.md` and isn't auto-loaded into context — improvising skips load-bearing setup like slug derivation, agent dispatch, file persistence, and cleanup reminders.

| Natural-language phrasing                                                          | Command          |
| ---------------------------------------------------------------------------------- | ---------------- |
| "make/draft/write a plan", "plan out X", "plan this"                               | `/plan`          |
| "grill this", "grill the diff/changes", "be devil's advocate", "find what's wrong" | `/grill`         |
| "verify", "run the checks", "pre-PR check", "is this green"                        | `/verify`        |
| "stage and commit", "commit and push", "ship it"                                   | `/acp`           |
| "ask Dave", "second opinion from Dave", "what does Dave think"                     | `/dave`          |
| "scan for bugs", "deep bug scan", "scan `<dir>`"                                   | `/scan`          |
| any `gh stack` action ("stack view/add/submit/sync/merge/up/down…")                | `/stack <action>` |
| "find tech debt", "techdebt scan", "find duplicated code"                          | `/techdebt`      |
| "run CodeRabbit", "rabbit review"                                                  | `/rabbit`        |

When the request adds constraints the command flow doesn't cover, invoke the command and adapt inside its steps rather than discarding it.
