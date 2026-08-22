# Conventions for role agents working in target repos

**This is the single source of truth for shared role-agent behaviour.** The
symlinked role agents (`software-engineer`, `devops-engineer`, `qa-reviewer`,
`oncall-guide`) reference this file instead of restating it — **keep them in
sync**: change a rule here, not in each agent.

**Read this before your first write in a target repo.** It lives here rather
than in the instance `CLAUDE.md` because it governs work in the **target
repos**, which are outside this bundle — so it cannot be a `paths:`-scoped
rule (globs are matched relative to this directory and never match a file under
`reposRoot`), and as always-loaded text it sat in every session's context
including the majority that dispatch no role agent. The `CLAUDE.md` section of
the same name keeps the handful of invariants that must hold whether or not you
got here.

- Read `instance.config.json` for `reposRoot` (where target repos are cloned).
  Honor this `CLAUDE.md` for data-handling, units, and commit-attribution.
- **Detect the default branch** (`git symbolic-ref --short refs/remotes/origin/HEAD`
  / `git remote show origin`) — never assume `main`. Never work on it.
- Create a feature branch (or a git worktree under the instance's `worktreeRoot` —
  absent that key, `<reposRoot>/_wt`) per task.
- Conventional commits; **no AI attribution / `Co-Authored-By` lines.** Push to
  `origin` early (don't wait until the end) so an interrupted worktree loses nothing.
- PR title format: `<type>: <subject> [<task-id>]` (OKF task id, e.g.
  `[ci-hardening/task-001]`). Target the default branch. **Never merge.**
- **Embed the task's `acceptance_criteria` in the PR body** as a checklist (plus any
  hints a reviewer needs), and note how you verified each. This is what the
  independent reviewer — an external one (e.g. CodeRabbit) or the `qa-reviewer`
  fallback — evaluates the change against, so it must travel with the PR, not just
  your own "it's done."
  **Tick a box only for a criterion you actually verified; leave the rest unchecked** and
  say what verifying it would take. An unchecked box **blocks the PR from being
  merge-eligible** (`SCHEMA.md` → "An unverified acceptance criterion blocks clearance"),
  which is the point: a criterion no test covers — a price that must match an upstream
  rule, a flow only a human or a browser can walk — is exactly where green CI means
  nothing. Leaving it honestly unchecked routes the PR to a human instead of letting it
  ride the deterministic checks. Never tick a box because everything else passed.
- Run the repo's build, lint, and tests green before opening a PR. If you can't
  get them green, report rather than open the PR.
- **Self-review before you open the PR (a pre-filter, not the gate).** On your own diff,
  run a review and fix what it flags *first*: dispatch `code-architect` if it's installed
  in `~/.claude/agents/`, else do a careful pass yourself (correctness, edge cases,
  security, tests). **Don't spend a CodeRabbit session here if CodeRabbit reviews the PR
  anyway** — running the same paid reviewer twice per PR is the single easiest cost to
  delete, and the pre-filter's job (catch the cheap stuff) is served just as well by a
  local agent. Reach for `coderabbit review` locally **only** when the repo has *no*
  CodeRabbit integration, i.e. when the `qa-reviewer` fallback would be the gate. This
  pre-filter does **not** replace the independent verifier: you review your own work
  leniently, so the fresh-context reviewer still runs after (see `SCHEMA.md`
  "Independent verification gate").
- **One review per PR — fix findings, don't re-trigger.** Address every review comment,
  push the fix, and reply once stating what changed (or why you disagree). Do **not** ask
  for a re-review to confirm your fixes: a re-review of addressed findings reliably finds
  nothing and costs a full session. Request one (`@coderabbitai review`) only after a
  *substantial rewrite* that invalidates the original review. Repos should pin this with
  `.coderabbit.yaml` (`auto_incremental_review: false`, `chat.auto_reply: false`) so it
  holds by default rather than by everyone's discipline.
- **Wide work via workflows (optional).** For genuinely wide, *independent* work, author a
  `Workflow` fan-out instead of grinding serially (find the real edges → fan out → verify →
  synthesize). **Read-only** fan-out (review, audit, research, code-navigation) needs **no
  worktree isolation** (nothing writes) but still obeys the instance's concurrency/resource
  limits (the `maxAgentsInFlight` cap) — it does **not** license unlimited dispatches;
  **write** fan-out must *also* give each subagent its own worktree (`isolation:
  'worktree'`) — never parallel writes to a shared clone/worktree (the same collision the
  per-task isolation rule prevents). Skip it for small/sequential work (pure
  overhead). Under **ultracode**, authoring a workflow for substantial wide work is the
  default. `/pm-loop` stays serial — workflows live *inside* a task, never at the loop level.
- Write the PR URL and a `# Result` summary back into the task document, and set
  the task `status: in-review` (or `blocked`, with why, if you can't proceed).
- **No customer PII** in code, commits, or PR text; **never echo, print, or log
  secrets or environment variables** (rely on existing env / `.npmrc` for auth).
- **Capture knowledge:** if you discover something durable and reusable, write or
  update a `Finding` in `knowledge/findings/` (per `SCHEMA.md`) and link it from
  the task, so the next agent doesn't re-derive it.
- **Parallel-safety:** if the product repos share one clone / one package store,
  each agent uses its own worktree under `worktreeRoot` (from `instance.config.json`
  — outside any synced folder; **never** inside `reposRoot`. Absent that key, fall
  back to `<reposRoot>/_wt`) and a **private package
  store** (e.g. `pnpm install --store-dir <worktree>/.pnpm-store`), and pushes
  early. Create the worktree explicitly with `git worktree add <path> -b <branch>
  origin/<default-branch>` — don't rely on the `EnterWorktree` tool, which may be
  unavailable to you as a subagent. (`settings.json` sets `worktree.bgIsolation:
  none` so the control panel manages worktrees itself; harness isolation would
  only isolate this repo, not the product repos.)
- **Browser (only if the project opts in):** when the task's project sets `browser:
  claude-for-chrome` **and** the `mcp__claude-in-chrome__*` tools are actually present, be
  **browser-first**: verify the change in the real page, read the logged-in view, take the
  screenshot — don't hand a browser step back to the human just because it's a browser
  step. You get your **own tab group**, not the human's tabs, so always navigate from an
  explicit URL. Tools absent (e.g. a headless tick) → take a non-browser route and say so;
  never report blocked *only* for a missing browser. **Browser writes follow the project's
  `autonomy`:** **ask first** — that's the default and the only behaviour unless the project
  delegates writes (`AUTONOMY.md` at the bundle root defines the modes; no such file means
  always ask). Read-only navigation and screenshots never need asking. Scope discipline
  still applies — a write nobody asked for isn't licensed by autonomy. And
  no customer PII from a logged-in page
  ever reaches a task doc, PR text, `log.md`, any log or console output, or the KB.
  Describe the *shape* of what you saw, not the records. Full rules: `SCHEMA.md` →
  "Browser access".
- **Code intelligence (if present):** if a repo has a CodeGraph index (a
  `.codegraph/` dir) or the `codegraph` MCP is available, use it to navigate the
  codebase before bulk-grepping — `codegraph explore "<q>" -p <repo>` for an area,
  `codegraph node <sym>` for one symbol's callers/callees, `codegraph impact <sym>` /
  `codegraph affected <files>` before a change. Skip silently if absent; it's an optional
  local index (see the ai-bridge README).
