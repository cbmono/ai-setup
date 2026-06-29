---
description: Lightweight todo manager for this control panel — add, list, or complete quick personal reminders kept in todos/todos.md
argument-hint: <todo text>  |  (empty) or "list"  |  done <text-or-#>  |  clear
allowed-tools: Bash(date:*), Read, Edit, Write
---

Manage the control panel's quick todo list — a single GFM checklist at
`todos/todos.md` (relative to this instance root).

> **Generic template file** (symlinked from the `ai-bridge` template). Todos are
> **lightweight personal reminders**, distinct from the formal OKF work tracked
> under `projects/`. When a todo is really a piece of agent-executed work, promote
> it with `/new-project` instead of leaving it here.

## Modes (interpret `$ARGUMENTS`)
- **empty** or **`list`** → list todos: open items first, then a short "done" tail.
- **`done <text-or-#>`** → mark the matching open item complete (`- [ ]` → `- [x]`).
  Match by 1-based position among open items, or by a unique substring; if it's
  ambiguous, show the candidates and ask.
- **`clear`** → remove the completed (`- [x]`) lines (after confirming the count).
- **anything else** → treat `$ARGUMENTS` as the text of a **new** todo.

## Steps
1. Read `todos/todos.md`. If it's missing, create it with a `# Todos` heading and
   the same one-line "lightweight notes vs `/new-project`" note, then continue.
2. **Add:** append `- [ ] <text> (added <YYYY-MM-DD>)` to the checklist — get the
   date once via `date +%F`. Keep new items at the end.
3. **Done:** resolve the target open item and flip `- [ ]` → `- [x]`; leave its text
   intact (optionally append ` (done <YYYY-MM-DD>)`).
4. **List / after any change:** print the **open** items as a numbered list
   (numbers = the positions `done` accepts), then a one-line count of done items.
5. **Do not commit.** `todos.md` is tracked instance content — leave it staged-free;
   it rides along with the next commit. (Don't use `commit-as.sh` here.)

## Notes
- One file only — never split todos across files or add a `todos/` subfolder.
- No customer PII in todo text.
