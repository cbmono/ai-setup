Manage a stacked-PR workflow using GitHub's `gh stack` extension.

## Usage

- `/stack` — no args → dispatch the `stack-navigator` agent for a summary + recommended next action
- `/stack <action> [args]` — run the specific action below

## Actions

- **`status`** — `gh stack view`, then summarize: current branch, position in stack, PR numbers and CI state. If not in a stack, say so and suggest `init`.
- **`init <branch>`** — `gh stack init <branch>`. Confirm the stack root was created.
- **`add <branch>`** — `gh stack add <branch>`. Remind the user to commit before the next `submit`.
- **`submit`** — `gh stack view` first (show what will be pushed), then `gh stack submit`. Report PR URLs.
- **`sync`** — `gh stack sync` (fetch + rebase + push + sync PR state). On rebase conflict, stop and hand back to the user with a clear summary. Do not resolve conflicts silently.
- **`rebase`** — `gh stack rebase`. Same conflict rule as sync.
- **`up [n]` / `down [n]` / `top` / `bottom`** — navigate via `gh stack up/down/top/bottom`. Confirm the new branch.
- **`unstack`** — confirm with the user before running `gh stack unstack` — it removes the stack locally and on GitHub.

## Guardrails

- Never pass `--force`-style flags that aren't already the default. `gh stack push` already uses `--force-with-lease --atomic`.
- If `gh` isn't authenticated (`gh auth status` non-zero), tell the user to run `gh auth login` and stop.
- If the extension isn't installed (`gh extension list` doesn't include `github/gh-stack`), tell the user to run `gh extension install github/gh-stack` and stop.
- For `submit` / `sync`, always show the stack view first so the user sees what's about to happen.
