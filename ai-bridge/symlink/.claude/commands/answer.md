---
description: Answer the PM's pending open_questions interactively — gather every task's unanswered questions and ask them in one batch, then fold the answers back into the tasks (clearing them). In-session convenience instead of editing each task file by hand.
allowed-tools: Bash(pwd), Bash(ls:*), Read, Edit, Glob, Grep, AskUserQuestion
---

Answer the Project Manager's pending `open_questions` **interactively**, instead of
opening each `taskX.md` and appending ` --- <answer>` by hand.

## Preconditions
Run from a control-panel instance root — confirm `SCHEMA.md`, `instance.config.json`,
and `.claude/agents` exist in the cwd; if not, tell the user to `cd` into the instance
and stop.

## Steps
1. **Gather.** Glob `projects/*/tasks/*.md` and collect every task with a non-empty
   `open_questions` list. For each entry (numbered `Q1:`, `Q2:`, …) record the task path
   + question text.
2. **Ask.** Present them with `AskUserQuestion`, batched (max 4 per call — loop if there
   are more), grouped by task so the context is clear. Where you can propose plausible
   answers, offer them as options; otherwise take free-form.
3. **Fold back.** For each answered question, bake the answer into the task itself
   (`# Context`, a tightened `acceptance_criteria`, or `# Notes` as fits) and **delete
   that entry** from `open_questions` — the same effect as the ` --- <answer>` delimiter,
   applied here. Keep no answered-question history.
4. **Report** which tasks became clean (empty `open_questions`). Under `gated` they're
   now promotable by the human; under `yolo`/`yolo-merge` the next `/pm-loop` tick will
   auto-promote them. This command **only answers questions** — it never promotes,
   dispatches, or merges.

## Notes
- **Foreground/interactive only** — a background `/pm-loop` tick can't prompt you; it
  parks questions on the 🔴 board, and you clear them here (or by editing the task docs).
- Commit is optional: the next `/pm-loop` tick commits the doc changes under the PM
  identity, or commit them yourself using this bundle's usual process.
- No customer PII in answers written to task docs.
