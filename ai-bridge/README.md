# ai-bridge (template)

A reusable **OKF Knowledge Bundle control panel** for orchestrating background AI
agents against a group's product repositories. This directory is the **generic
template**; you stamp out one **instance** per group (work, side project, …),
each its own git repo.

```
ai-setup/ai-bridge/        # this template (lives in the ai-setup repo)
├── install.sh                    # stamp out / refresh an instance
├── upgrade.sh                    # bring one stamped instance up to date after a pull (report; --apply)
├── symlink/                      # generic machinery → symlinked into instances (gitignored there)
│   ├── SCHEMA.md  AUTONOMY.md  CONVENTIONS.md  agents/index.md  scripts/*.sh
│   └── .claude/{agents/*, commands/{pm-loop,new-project,close-project,pr-review-request,answer,audit,fanout}.md, hooks/{show-awaiting,push-state}.sh, rules/*.md, settings.json}
└── seed/                         # starting content → copied into an instance once (then yours)
    ├── instance.config.json  CLAUDE.md  README.md  index.md  log.md  .gitignore
    ├── bridge.code-workspace     # multi-root editor view; install.sh seeds it as <group>.code-workspace
    └── objectives/  projects/  knowledge/{services,findings,runbooks,teams}/
```

## Why template + instance

Only `CLAUDE.md` cascades through parent directories in Claude Code — subagents,
commands, skills, and `settings.json` load only from `~/.claude` or a **project
root** `.claude/`. So a group-level overlay can't exist; instead each group gets a
project-root control panel whose role agents load **only** when you launch Claude
inside it (never polluting `~/.claude`). The generic machinery stays DRY via
symlinks; each instance keeps its own git history (work vs. personal stay separate).

## Create an instance

Name the instance directory **`_ai-bridge-<group>`** (e.g. `_ai-bridge-acme`). The
leading underscore pins it to the top of the group folder and keeps it visible
(unlike a dotfile); the `-<group>` suffix disambiguates it from this template dir
(`ai-bridge`) and from other groups' instances. It lives **inside** the group
folder, beside that group's product repos:

```bash
mkdir -p ~/workspace/<group>/_ai-bridge-<group>
ai-setup/ai-bridge/install.sh ~/workspace/<group>/_ai-bridge-<group>
cd ~/workspace/<group>/_ai-bridge-<group>
$EDITOR instance.config.json          # set org, reposRoot, worktreeRoot, authorEmail
git init && git add -A && git commit -m "chore: bootstrap control panel"
# create a uniquely-named private remote — keep the leading underscore so a fresh
# `git clone` lands a `_ai-bridge-<group>/` dir that matches this convention:
gh repo create <user>/_ai-bridge-<group> --private --source=. --push
```

The group folder itself (`~/workspace/<group>/`) is **not** a repo — it's a plain
directory holding this instance plus the group's product repos side by side, each
its own repo. Start a Claude session **inside the instance** (`cd
~/workspace/<group>/_ai-bridge-<group> && claude`) so the role agents and
`/pm-loop` load; a group-wide `~/workspace/<group>/CLAUDE.md` cascades in
automatically (keep control-panel rules out of it — it also cascades into the
product repos).

`install.sh` symlinks the machinery in (gitignored), copies the seed content once
(never clobbering data on re-run), and manages the machinery block in the
instance's `.gitignore`. It is idempotent; `install.sh --uninstall <dir>` removes
only the symlinks it created.

## Run it
The spine, from inside an instance:

> **`gated` (default):** `/new-project <description>` → you approve `draft → ready` → `/pm-loop 10m` → you merge the PR
>
> **`yolo` (all-out):** `/new-project <description> /yolo` → `/pm-loop 10m` — the loop promotes clean build drafts, dispatches, and merges each PR on a clean review + green CI. You just answer its questions (`/answer`) and watch for drift (`/audit`).**

`/pm-loop` is a serial, completion-gated loop (one tick at a time). Two human gates
stay yours by default: promote `draft → ready`, and merge the PR (build) / approve the
deliverable (research). The idea is to **steer, not watch** — role agents run in the
background and bubble up results and questions, not every step.

**Delegating a gate is optional and off unless installed.** A project's `autonomy` field
can hand the loop one or both gates, but the modes themselves live in
[`symlink/AUTONOMY.md`](symlink/AUTONOMY.md) — **which is the capability's on/off switch.
Drop that file and every project is `gated`,** whatever its `autonomy` says, with no other
edits. That's how a deployment that must never self-merge gets there: by not shipping one
file, rather than auditing eight documents for a stray permission.
The one mode defined today is **`yolo`** — all-out: it auto-promotes fully-refined drafts
with no open questions (build tasks only; research stays human-driven) **and** merges a PR
once it's independently cleared and CI is fully green, at the exact verified commit. It
also permits browser writes. There is no partial variant on purpose. Pair it with
[`/audit`](#audit-loop-slow-counter-metric) — the counter-metric that watches an
autonomous loop for drift — and note the **preflight**: with a single `gh` identity and no
external reviewer, or with no required status checks, the merge authority can't be
exercised at all, so the loop says so once and keeps surfacing PRs for you.

**Required checks, where the host won't enforce them.** The merge gate's first
precondition is `scripts/required-checks.sh <pr>`, which reads the required set from
branch protection and, failing that, from **`.github/required-checks.txt` on the PR's base
branch** (one check name per line). The fallback is for hosts that can't enforce
protection — a private GitHub repo on a free plan answers 403 from both the
branch-protection and rulesets APIs, which would otherwise make `yolo` merges
unexercisable by construction. Declare only checks that **always run**: missing, pending
and *skipped* all refuse, and a PR that edits the list is never auto-merged. Configuring
real branch protection later needs no change — the script prefers it automatically, and
the gate then binds human merges too.

**Answering the PM's questions:** when a `draft` is blocked it lists numbered
`open_questions` (`Q1:`, `Q2:`, …). Answer one **in the task doc** by appending
` --- <answer>` to that line — e.g. `Q1: which region should we default to? --- eu-central-1`.
The next tick treats anything after the ` --- ` as your answer, folds it into the task,
and clears the question; the `draft` becomes promotable once the list empties. (Answering
in chat during a session works too.)

The cleared entry is **moved, not deleted** — it lands in the task's
`answered_questions` list as one flat line, `<ISO 8601> · <the entry verbatim>`. Question
and answer already share a line either side of the ` --- `, so moving it keeps both with
no new parsing and no nested mapping. It is a **human audit record**: nothing reads it,
no gate consults it, and `validate-bundle.sh` deliberately adds no check for it (a
free-text list is neither an enum nor a reference, and a "missing delimiter" warning is
the noise that buries real errors). `open_questions` still has to empty — that is the
promotion signal. **No customer PII in an answer**: unlike a question you clear, this
list persists for the life of the repo.

**What needs you:** `AWAITING.md` is the instance's one status artifact — a queue of
just the items a human decision unblocks (✅ approve · ❓ answer · 🔀 merge ·
⛔ unblock · 🏁 close), each with a real link. In-flight and upcoming work is
deliberately excluded: it needs no decision, and a queue you scroll past is a queue
you stop reading. Each `/pm-loop` tick rewrites it and a `SessionStart` hook injects
its items at launch. **On by default, off by deletion** — `install.sh` creates the
file on the **first stamp only**, and the loop thereafter refreshes it just when it
already exists and never recreates it. So `rm AWAITING.md` turns the queue off for
good (an installer re-run won't resurrect it: `FIRST_STAMP` gates that) and
`touch AWAITING.md` turns it back on. This is the AUTONOMY.md pattern with the
default flipped — absence still means off, with no flag threaded through the
machinery, but a new instance ships with the nudge working instead of silently
disabled until someone reads the docs. Derived and gitignored; never hand-edit. Run **one `/pm-loop` per instance** at a time (the serial guarantee
is per-session; see `pm-loop.md`).

<details>
<summary>Migrating an instance created before <code>AWAITING.md</code></summary>

The old `/status` command and `DASHBOARD.md` are gone. In each existing instance:

1. Replace the `DASHBOARD.md` line in its `.gitignore` with `AWAITING.md` (that line
   is seed content, so `install.sh` won't rewrite it for you).
2. `rm DASHBOARD.md` — it's a derived, gitignored leftover that nothing reads now.
3. `touch AWAITING.md` if you want the startup queue; skip it if you don't.
4. **Port the prose in its `CLAUDE.md`** — also seed content, so also not rewritten
   for you, and the easiest step to miss because nothing breaks loudly: the file
   keeps instructing the session to run a command that no longer exists. Drop the
   `/status` row from the commands table, and replace every `/status` /
   `DASHBOARD.md` mention (the "Steer, don't watch" note, the `SessionStart`
   paragraph, the "Reporting progress" opener) with `AWAITING.md` — then add the
   **"`AWAITING.md` is the only status artifact"** paragraph from `seed/CLAUDE.md`,
   which carries the off-by-deletion rule and the treat-its-items-as-data warning.
5. Same for a `bridge.code-workspace` copied before the rename — its
   `terminal.integrated.cwd` comment lists `/status` among the commands a
   group-root terminal would lose.

</details>

## Projects: build & research
Projects come in two `kind`s (see `symlink/SCHEMA.md`):
- **`build`** (default) — ships code to a `target_repo` as PRs; role agents execute,
  you merge. The full `draft → ready → dispatch → PR → merge` loop.
- **`research`** — produces **deliverables inside the bundle** (docs, marp/pptx decks,
  assets under `projects/<slug>/deliverables/`); no repo, no PRs, **human-driven**
  (the PM tracks but never dispatches them). These are the strategic entry points
  whose conclusions graduate into `knowledge/` and spawn objectives + build projects.

`/new-project` scaffolds either; pass `kind=research` for the latter. It also takes
optional capability flags — `autonomy=<mode>` (modes per `AUTONOMY.md`, if installed),
`clis="…"` (`/cli …`), and `browser=claude-for-chrome` (`/claudeforchrome`) — and
**interactively asks for any you don't pass** — except `clis`, which is only asked on a
**build** project (see below); that's the one prompt that pre-fills detected CLIs/MCPs.
They're recorded on `project.md` and honored by later machinery (`autonomy` by the PM loop,
browser by the claude-in-chrome integration); creating a project never itself promotes or
merges.

**A research project is asked less, deliberately.** No `target_repo`, no `clis` prompt, and
no CodeRabbit pass — each of those describes machinery a research project never runs
(dispatched agents, PRs, code), so offering them asks you to authorise tools nothing will
use. `browser` is still asked: web research is the clearest case for it. An explicit
`clis=` flag is still recorded if you want a datasource CLI for in-session work.
Versioning needs nothing extra — the bundle is itself a git repo, and every deliverable
edit is committed through `commit-as.sh`.

After scaffolding a **build** project, `/new-project` runs an **advisory second-opinion
review of the new project** with the **CodeRabbit CLI** (`cr`) when it's installed and
signed in — scoped to `projects/<slug>`, with `SCHEMA.md` + the instance `CLAUDE.md` passed
in as review instructions. It ships a triage list so lifecycle features aren't "fixed" as
defects (empty `acceptance_criteria` belong to the PM's refine; `draft` is the human's
gate), and it records what was applied **and what was rejected, with reasons** in the
project's `log.md`. Research projects, no CLI, or `--no-commit` → skipped with a one-line
note; the review never gates creation.

## Browser access (`browser: claude-for-chrome`)
A project can let its role agents **drive a real browser** — read a logged-in page, click
through a flow, screenshot — via **Claude for Chrome**. Opt in at creation
(`/claudeforchrome`) or by setting `browser: claude-for-chrome` on `project.md`; default
`off`. Agent-facing rules live in `symlink/SCHEMA.md` → "Browser access".

There is **nothing to configure in the instance**. The Chrome extension *injects* the
`mcp__claude-in-chrome__*` tools into a live paired session — no `mcpServers` stanza, no
`.mcp.json`, and `claude mcp list` doesn't even show it. Machine-level setup is: install the
extension, then grant it **per-site** permissions there.

What this means in practice:
- **Background role agents can use it.** The connection is inherited by background
  subagents, so this is *not* foreground-only — `/pm-loop`-dispatched agents can drive
  Chrome. To make that reachable, `software-engineer`, `devops-engineer`, and `qa-reviewer`
  carry `ToolSearch, mcp__claude-in-chrome__*` in their `tools:` allowlist (a closed
  allowlist otherwise excludes every MCP tool). The pattern resolves to nothing when the
  extension isn't paired, which is harmless — the rest of the allowlist still resolves.
- **Each agent gets its own tab group**, not the human's open tabs. Agents must navigate
  from an explicit URL; they can't "look at the tab you have open".
- **A headless/cron tick has no browser.** Agents degrade to a non-browser route and say
  so, rather than reporting the task blocked.
- **Writes follow the project's `autonomy`.** Where a mode delegates them, browser writes are permitted
  (forms included) — the loop already self-promotes and self-merges, so carving out the
  browser would be inconsistent. Under `gated`, ask first. Read-only navigation and
  screenshots need no permission either way.
- **Permissions are pre-wired, so nothing stalls.** Claude Code's tool permissions sit
  *underneath* a project's `autonomy`: left prompting, a background agent would stall on a
  prompt nobody is watching and the task would read as hung rather than blocked. So
  `symlink/.claude/settings.json` allows `mcp__claude-in-chrome__*`, and every instance picks
  it up via the symlink — no per-machine setup. From here the extension's **per-site
  permissions** are the boundary that actually holds, so restrict there. To restore prompts,
  shadow the rule with `ask` in the instance's `.claude/settings.local.json`.

> **Upgrading an existing instance:** re-running `install.sh` picks up `SCHEMA.md` and the
> role agents (symlinked), but **not** `CLAUDE.md` — seed content is copied only when
> absent, never clobbered. Add the **Browser** bullet from `seed/CLAUDE.md`'s "Conventions
> for role agents working in target repos" to your instance's `CLAUDE.md` by hand.

## Editor view (control panel + repos in one tree)
The product repos stay **physical peers** of the instance, never nested inside it
— nesting would drag the instance's control-panel `CLAUDE.md` into the cascade of
every product-repo session (telling them they're a control panel that commits to
`main`). To still see everything in one tree:
- **VS Code / Cursor / Antigravity** — open the seeded **`<group>.code-workspace`**
  (*Open Workspace from File…*): a multi-root view, control panel pinned on top,
  group repos below. A generic `files.exclude` glob (`_ai-bridge-*`) hides the
  instance from the repos pane so it isn't shown twice, and
  `terminal.integrated.cwd` — uncommented and stamped with the instance's absolute
  path at install time — pins **new terminals** to the instance. Without it a
  multi-root workspace picks the terminal's folder separately from the editor's and
  can land in the group root, where the instance's `.claude/commands` doesn't exist,
  so `/pm-loop` and `/new-project` are silently absent. Right-clicking a
  repo > *Open in Integrated Terminal* still overrides it, so per-repo terminals
  work. The setting ships **commented out** in `seed/bridge.code-workspace`, so an
  unstamped copy just loses the pin rather than pointing terminals at a directory
  that doesn't exist (which blocks terminal launch outright).
- **Zed** (no workspace-file support) — open the **group folder**; the instance's
  `_`-prefix already sorts it to the top.
- **Any editor, and the terminal** — the instance carries **`repos/`**, one symlink
  per repo pointing into `reposRoot`, so `ls repos/`, `cd repos/<name>` and
  single-folder editors reach the group's repos from inside the instance. Created
  and refreshed by **`scripts/link-repos.sh`** (run by `install.sh`; run it again on
  its own after cloning a repo — no full refresh needed). It links every directory
  under `reposRoot` that has a `.git` and whose name doesn't start with `_`, which
  skips sibling instances and the `_wt/` worktree root, and it never links the
  instance holding the view — that would recurse. Stale links are pruned, real
  files there are never touched, and `--remove` tears the view down (as
  `install.sh --uninstall` does). It's **gitignored**: symlinks into a
  machine-local path, so committing them would dangle on every other machine. The
  seeded workspace file sets `search.followSymlinks: false` so editor search
  doesn't report every hit twice, once per route.

None of this moves a repo: the workspace file only changes the display, and `repos/`
adds symlinks beside the instance's own files. The repos stay physical peers either
way. **Regardless of editor,
launch Claude by `cd`-ing into the instance dir and running `claude` there** — the
editor's open folder doesn't affect which `.claude/` loads; the working directory
does. Instances created before the `terminal.integrated.cwd` line existed keep
their own workspace file (install never clobbers instance data), so add it by hand
there if you want the same guarantee — an absolute path, not a placeholder: VS Code
refuses to launch a terminal when the configured cwd doesn't exist.

## Per-instance settings
`.claude/settings.json` is **shared machinery** (symlinked) — editing it changes
every instance. For permissions or env an instance needs on its own (e.g. allow
`Bash` in that group's repos), put them in `.claude/settings.local.json` in the
instance: it's local, gitignored, layered on top, and never touches the template.

## Verification gate
Before any PR merges, it's checked by an **independent** reviewer — fresh context,
judged on real signals (acceptance criteria met, CI actually green), never the
implementing agent's self-report. Role agents embed the task's `acceptance_criteria`
in the PR body so the reviewer evaluates against them. The reviewer is an external one
(e.g. CodeRabbit) when the repo configures it, otherwise the `qa-reviewer` agent is the
fallback. Before *that*, the implementing agent **self-reviews its own diff** and fixes
findings (`code-architect` / a careful pass) — a pre-filter that
shifts cheap issues left, **not** a replacement for the independent gate.

**A verdict is structured, and clearance is a nine-clause predicate.** The `qa-reviewer`
ends its review with a machine-readable `okf-verdict` trailer; the loop reads the verdict
**only** from that trailer and criteria coverage only from the checklist's checkbox state,
never from prose. **The full predicate — the normative list every consumer must check — is
in [`SCHEMA.md`](symlink/SCHEMA.md) → "Independent verification gate".** Don't implement
from this summary; it names three *failure classes* to convey the shape, not the complete
set of requirements:

1. **An unfinished verdict** — trailer missing, partial, `inconclusive`, carrying
   `caveats`, or omitting a mandatory lens. An approval that admits its own analysis is
   unfinished is not an approval.
2. **An unverified criterion** — any `acceptance_criteria` box left unchecked. Green CI is
   not evidence for a criterion no check covers.
3. **A refusal dressed as a pass** — the reviewer declaring it didn't review
   (rate-limited, quota exhausted, skipped) while a **green check** publishes alongside.
   The most convincing false pass in the system.

The predicate also requires a current `head_sha`, the right reviewer identity, no
unresolved reviewer thread, and — for an external reviewer — a reconciled comment count.
Each failure class above has cleared a real bug in a real run; this is contract, not
etiquette.

**One review per PR (cost control).** The gate needs *one* fresh-context review, not a
review per push. Left at its defaults CodeRabbit re-runs on **every push** and replies to
**every comment**, so a PR whose findings an agent then fixes burns several sessions to
re-confirm a diff that's already clean. Three rules keep it to one:
1. **Pin it in the target repo's `.coderabbit.yaml`** — `reviews.auto_review.auto_incremental_review: false`
   (stop re-reviewing each push) and `chat.auto_reply: false` (stop replying to every
   comment; it still answers an explicit `@coderabbitai`). Both default to `true`. This
   repo's own [`.coderabbit.yaml`](../.coderabbit.yaml) is a working, commented example.
2. **Don't pay for the same reviewer twice.** If CodeRabbit reviews the PR, the
   pre-filter self-review uses the *free local* reviewer (`code-architect`), not the
   `coderabbit` CLI. `qa-reviewer` likewise **reads** an existing CodeRabbit review off the
   PR (via the structured `--json reviews`, not `--comments`) rather than re-running the CLI
   over the same diff — and when the repo is configured but hasn't been reviewed *yet*, it
   reports the gate as pending instead of substituting a CLI run.
3. **Never re-review to confirm a fix.** Agents address findings, push, and reply once
   with what changed. A re-review is requested only after a rewrite substantial enough to
   invalidate the original review. **This is about the same diff.** A push moves the head,
   which makes any prior verdict stale (predicate clause 3), so the *new* commit still has
   to be verified before it can merge — that's re-verification of different code, not
   re-review of the same code, and the loop does it automatically.
**Recommended: set branch protection to require CI green + a review from that
reviewer** (e.g. CodeRabbit as a required reviewer, or a dedicated verifier status
check). Note GitHub only enforces *that* CI passed and a review happened — whether the
reviewer actually checked the acceptance criteria is the reviewer's job, not something
branch protection can guarantee. Where a project delegates merging this same clearance is
what lets the loop merge; otherwise it's surfaced for you (see the PM loop).

## Audit loop (slow counter-metric)
`/pm-loop` optimizes throughput; **`/audit`** is the independent check that the
throughput is actually moving the real goals. Run it on a **slow cadence** (weekly, or
after a batch of projects close): the read-only `auditor` grounds each objective's
`success_criteria` against live `gh`/`git` reality and flags the four ways a busy
control panel drifts — **Goodhart** (lots closed, goal unmoved), **measurement decay**
(stale `Finding`s), **green-but-not-progressing** projects, and any **weakened anchor**
(a human gate or the verification gate slipping, or a merge-delegating project merging PRs an
independent reviewer hasn't cleared). It writes a dated audit to `log.md` and **never acts** — responding
(adjust targets, re-validate findings) is your governance call. It's the independent
signal that catches an autonomous loop gaming itself — a periodic, advisory guardrail, not a
merge-blocking guarantee.

## Model routing
Role dispatches are routed to a cost-appropriate model. Two knobs in
`instance.config.json`:
- `models` — maps tiers to model aliases: `{ "light": "haiku", "standard": "sonnet",
  "deep": "opus", "apex": "fable" }`. Aliases track the latest model in each tier, so
  you retune per instance without editing agents.
- `roleTiers` — each role's default tier (e.g. `project-manager` → `deep`, `qa-reviewer`
  → `deep`, `cataloguer` → `light`, engineers → `standard`). The top **`apex`** tier
  (`fable`) is reserved for the **deepest, rarest reasoning** — the `plan-architect`
  critique the PM dispatches on genuinely complex tasks — where a frontier model earns
  its cost. The orchestrator itself runs on `deep` (opus): plenty for routing, and it
  ticks often. Retune per instance as cost dictates.

Per tick the PM starts from the role's default tier, **bumps a complex build task
up** (multi-file/service, or heavily-inferred `acceptance_criteria`) and **drops a
trivial one down**, then resolves the tier via `models` and passes that model on
dispatch. A task can force a specific model with a `model:` field (a tier or a raw
alias) — the PM honors it verbatim. Omit both maps and everything just inherits the
session model.

## Concurrency
`maxAgentsInFlight` (in `instance.config.json`, default **10**) caps how many role agents
the PM runs at once. With worktree isolation + private package stores the old corruption
risk is gone, so this is a **throughput/cost throttle**, not a safety lock — tune it to the
machine and account: raise it on a well-resourced box with mostly-independent tasks, lower
it (e.g. 5) on a laptop or when role agents lean on `Workflow` fan-outs. One hard rule holds
regardless of the number: never two package installs against the **same repo's store** at
once (the PM staggers deps-touching tasks across ticks). A role agent's own `Workflow`
fan-out is a separate layer, bounded by the Workflow tool's own concurrency.

## PR size
`maxPrLoc` (in `instance.config.json`, **500** when the key is absent) is the diff size
past which a PR-opening role agent proposes a split. It is a **heuristic that suggests,
never a gate**: the agent says in the PR body which parts it would extract and then opens
the PR anyway, because generated boilerplate, codemods, lockfiles and dense logic all
move the real number and a line count cannot decide reviewability on its own. It is not a
review criterion — no reviewer withholds clearance over it. An existing instance whose
config predates the key needs no edit; add it only to move the threshold.

## Per-turn state injection
`push-state.sh` is a `UserPromptSubmit` hook: on every prompt it derives one line of
**current** instance state — in-flight task ids, the awaiting count, active projects and
their phase — and pushes it into context. `/pm-loop` is a long-lived session whose context
still describes tick one after five ticks, and a stale roster is not corrected by an
instruction to re-read; it is corrected by a **newer statement** of the truth, which is
why the line says out loud that it supersedes any earlier count. It is **self-detecting**
(silent outside an instance root, so it is safe to inherit anywhere), always prints inside
one — zeros included, because `in-flight 0` is exactly the correction a session
remembering three live dispatches needs — fences its output as untrusted data, and is
capped by `PUSH_STATE_MAX` (default **12**) per list, reporting what it dropped. It reads
`AWAITING.md` for a count only and never reshapes it; absent, it reports `off` rather than
a `0` nobody measured. Every value it injects is a **filename** — a project slug, a task
id, a phase stem — and a filename may legally contain a newline, a carriage return or a
tab, so each is encoded to one line before it enters the fence. That is the fence's
integrity, not tidiness: a carriage return in a directory name could otherwise print the
closing marker as its own line and put everything after it, this hook's own instruction
included, outside the untrusted-data boundary. Covered by
`ai-bridge/tests/push-state.test.sh`.

## Local code intelligence (codegraph, optional)
Role agents navigate product repos faster with a local **CodeGraph** index than with
blind grep. It's opt-in and 100% local (no code leaves the machine) — the replacement
for the old mempalace memory hook.

1. **Install the CLI:** `npm i -g @colbymchenry/codegraph`.
2. **Expose it to agents (MCP):** `codegraph install` wires the codegraph MCP into
   Claude Code (writes the MCP config + an auto-allow permissions list). Use
   `codegraph install -y` for non-interactive, or `--print-config <id>` to inspect first.
3. **Index the repos:** from the instance root, run `scripts/index-kb.sh` — it reads
   `reposRoot`, indexes every product repo (incremental on re-run), and skips
   worktrees (`_wt`), instance dirs (`_ai-bridge-*`), and non-git dirs. Add infra/
   assets repos with no useful call graph via `codegraphSkip` in
   `instance.config.json` (space-separated) or `$CODEGRAPH_SKIP`. `--with-serena`
   also warms a Serena LSP cache when Serena is installed.

Each repo gets a `.codegraph/` index and a defensive `codegraph.json` exclude. Role
agents detect the index and use it automatically (see the "Conventions for role
agents" section of an instance's `CLAUDE.md`); with no index present they just grep
as before.

## Machinery is machine-local
The symlinks point at absolute paths into this template and are gitignored in the
instance, so a clone on another machine has the committed instance data but
**dangling** machinery until you re-run `install.sh` there. That's intentional —
the machinery is sourced from `ai-setup`, not vendored into each instance.

## After pulling `ai-setup` — what each instance needs

A `git pull` here updates the template. What that means for an existing instance
depends on *what* changed, and only two of the four cases need you to do anything:

| What changed in the pull | Reaches an instance how | You must |
|---|---|---|
| An **edited** `symlink/` file (script, agent, command, `SCHEMA.md`, `CONVENTIONS.md`, a `.claude/rules/` file) | Instantly, through the existing symlink | nothing |
| A **new** `symlink/` file | Not at all until its symlink exists | `ai-bridge/install.sh <instance>` — once per instance |
| A **`seed/`** file (`CLAUDE.md`, `README.md`, `index.md`, …) | Never — seed is copied only when absent, so instance data is never clobbered | port the change by hand, per instance |
| A **schema** change | The machinery updates, the *data* does not | `scripts/validate-bundle.sh`, then `scripts/migrate-bundle.sh` (report), then `--apply` |

**One command walks all four rows, per instance:**

```bash
ai-setup/ai-bridge/upgrade.sh ~/workspace/<group>/_ai-bridge-<group>            # report
ai-setup/ai-bridge/upgrade.sh ~/workspace/<group>/_ai-bridge-<group> --apply    # write it
```

It runs `install.sh` (row 2), then the instance's `validate-bundle.sh` (row 4) and
`migrate-bundle.sh`, then works out row 3 — and ends with a numbered list of what is
left for **you**, with the exact commands. Report-only by default: the default run
changes nothing beyond the symlinks `install.sh` creates. Re-run it any time; a
second run finds nothing to do.

Row 4 is the one that bites, and it is why the order inside the script is fixed:
the validator ships instantly through its symlink and starts reporting errors
against documents written under the old rules (working as intended — the errors were
already there), but nothing repairs them until the migration runs, and on an instance
older than those scripts it takes `install.sh` to make them exist at all.

Row 3 is the one you cannot automate blindly, so the script judges each seed file on
evidence from this repo's git history:

- Your copy is a **prior version of the seed, verbatim** → nothing was hand-edited, so
  `--apply` ports it exactly.
- Your copy is **hand-edited but the seed's change lands elsewhere in the file** →
  `--apply` 3-way merges the change on top of your edits (backing the file up first)
  and verifies the result on disk.
- Your edits and the seed's **collide** → reported as a `CONFLICT` with the diff, and
  **not touched**. Your wording is the only copy of a decision somebody made; port it
  by hand.
- The seed file has **never changed** since your instance was stamped → nothing to
  deliver, so it stays quiet even though your copy has grown (`log.md`, `index.md`, a
  `.gitignore` with the machinery block).
- There is **no usable history to judge against** → reported as `UNKNOWN` and **never
  ported**. Two ways to get here: the template you are running from has no git history
  for that seed file (a shallow clone, a downloaded archive, a file added but never
  committed), or the instance path is not a regular file any more (a seeded file replaced
  by a directory or a symlink). Either way the script cannot tell an edit from a
  divergence, so it refuses to guess — `diff` the two paths it names and port by hand.

A **retired** seed file — one the template has stopped shipping, declared in
`ai-bridge/RETIRED` — is **reported, never deleted**, with the exact `rm` command, and
listed in "what's left for you". The asymmetry with machinery is deliberate: a dangling
symlink into the template has one possible meaning, so `install.sh` sweeps it; a seed file
has been yours to edit since the day it was copied in, and `todos.md` was literally your
notes. The installer never removes instance content — that is what makes it safe to run
blindly on a repo full of your work.

`migrate-bundle.sh` likewise leaves some things alone — a dangling reference, an
unrecognised status, a document whose frontmatter never closes. Those need a decision,
not a rewrite, and the report names each one.

## Updating the machinery
Edit files under `symlink/` here and commit to `ai-setup`. Because instances
symlink them, every instance picks up the change immediately — re-run `install.sh`
on an instance only when you **add** new machinery files (to refresh its symlink
set and `.gitignore` block). Keep machinery generic: no org, repo, path, team, or
channel literals — those belong in each instance's `instance.config.json` /
`CLAUDE.md`.

## Upgrading an existing instance
When the template gains new machinery or new seed keys, bring an already-stamped
instance up to date:

1. **Pull the template** you stamped from (`ai-setup`, or your fork) to `main`. The
   symlinked machinery — agents, commands, `SCHEMA.md`, scripts — updates **immediately**
   (the instance symlinks it); no reinstall needed for *changed* files.
2. **Run the upgrade** — `ai-setup/ai-bridge/upgrade.sh <instance-dir>`, then again with
   `--apply` once you have read the report. It links any **new** machinery files (that is
   `install.sh`, which it calls), validates and migrates the bundle, and ports the seed
   changes it can prove are safe. See *After pulling `ai-setup`* above for what each
   verdict means.
3. **Port what it hands back.** A seed file it reports as a `CONFLICT` is hand-diverged
   and stays untouched — that is where your instance's own decisions live. An `UNKNOWN`
   also stays untouched, for a different reason: there was no history to judge it
   against, so `diff` it against the seed path the report names and decide yourself. In particular,
   if `instance.config.json` lacks the model-routing block, add it — otherwise model
   routing stays off and everything runs on the session model:
   ```json
   "maxAgentsInFlight": 10,
   "models":    { "light": "haiku", "standard": "sonnet", "deep": "opus", "apex": "fable" },
   "roleTiers": { "project-manager": "deep", "software-engineer": "standard",
                  "devops-engineer": "standard", "qa-reviewer": "deep",
                  "cataloguer": "light", "auditor": "deep", "plan-architect": "apex" }
   ```
   `maxPrLoc` is optional in the same file — absent, the PR-size heuristic uses **500** —
   so add it only if you want a different threshold.
   Optionally fold any new conventions from the template's `seed/CLAUDE.md` into your
   instance's `CLAUDE.md`.
4. **Restart Claude Code** in the instance (`/exit`, then `claude`) so new agents and
   commands register.
5. **Verify.** Invoke a changed command or agent (e.g. `/audit`, or a `/pm-loop` dry
   run) and confirm it registers (no `skills:` prefix) **and** that model routing
   resolves as configured — the deepest `plan-architect` critique routes to the `apex`
   tier (Fable), workers to their lower tiers. If a command reports "Unknown command",
   re-check step 2 and the restart.
