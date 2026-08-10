---
description: Scaffold a new project under projects/<slug>/ — schema-valid files, registered in the bundle index/log and linked to its objective, with seed draft tasks. Supports build (code/PRs) and research (in-bundle deliverables) projects.
argument-hint: <one-line project description>  [kind=build|research] [objective=<slug>] [repo=<name|owner/name>] [deliverables="a; b"] [--no-commit]
allowed-tools: Bash(date:*), Bash(scripts/commit-as.sh:*), Bash(git add:*), Bash(ls:*), Read, Write, Edit, Glob
---

Scaffold a new **Project** in this bundle: the `projects/<slug>/` folder and its
files, registered in the bundle index and log and linked to an Objective, with
one or more seed `draft` tasks. Everything lands `draft`/`active` — nothing
becomes dispatchable until the human promotes a task `draft → ready`.

**Two kinds** (see `SCHEMA.md`): `kind=build` (default) ships code to a product
repo via PRs (role agents execute); `kind=research` produces **deliverables inside
this bundle** (docs, marp/pptx decks, assets) under `projects/<slug>/deliverables/`
— no repo, no PRs, human-driven (you work the tasks in-session; the PM tracks but
never dispatches them). Research projects are typically the strategic **entry
point** whose conclusions later graduate into `knowledge/` and spawn objectives +
build projects.

> **Generic template file** (symlinked from the `ai-bridge` template). It reads
> the bundle's own `SCHEMA.md` and `instance.config.json` for shapes and values —
> never hardcode org/repo/path literals here.

## Inputs
`$ARGUMENTS` = a one-line description of the project, plus optional tokens:
- `kind=build|research` — project kind (default `build`).
- `objective=<slug>` — link to `objectives/<slug>.md` instead of inferring one.
- `repo=<name|owner/name>` — **build only.** `target_repo` (bare name is qualified
  with `org` from `instance.config.json`). Omitted → `<org>/<defaultRepo>` from
  config; if there's no `defaultRepo`, ask. Ignored for research.
- `deliverables="a; b; …"` — **research only.** What the project produces. If
  omitted, infer from the description or ask.
- `autonomy=<mode>` — how much the loop may do without you (default `gated`). The
  available modes, and any shorthand flag for one, are defined in `AUTONOMY.md` at the
  bundle root; **if that file doesn't exist, `gated` is the only mode** — don't offer or
  accept another. Captured now; enforced by later machinery.
- `clis="a; b"` (shorthand `/cli a, b`) — external CLIs/integrations this project's
  agents may use (e.g. `render`, `supabase`).
- `browser=off|claude-for-chrome` (shorthand `/claudeforchrome`) — let agents drive the
  browser via the claude-in-chrome MCP when present (default `off`).
- `--no-commit` — scaffold only; don't commit (default is to commit).

If `$ARGUMENTS` has no description, **ask** for a one-line goal before doing anything.

## Steps

1. **Ground the shapes (don't guess).** Read `SCHEMA.md` (the `Objective`,
   `Project`, `Phase`, `Task` sections + the lifecycle) and **one existing
   project** as a copy-reference: its `project.md`, `index.md`, `log.md`, and a
   `tasks/*.md`. Read `instance.config.json` for `org` and `defaultRepo`.

2. **Derive the slug.** Kebab-case from the description (or an explicit slug if the
   user gave one). Confirm `projects/<slug>/` does **not** already exist — if it
   does, stop and report.

3. **Resolve the objective.** List `objectives/*.md`. If `objective=` was given,
   use it. Otherwise propose the best-fitting existing objective; if none fits,
   **propose creating** a new `objectives/<slug>.md` and get the user's OK before
   creating it (an objective is a strategic goal — don't mint one silently).

4. **Resolve capabilities & kind-specific fields (capabilities first).**

   **a. Capabilities (flags-first, else ask).** Settle `kind`, `autonomy`, `clis`, and
   `browser` **before** the kind-specific fields below — otherwise a project could be
   asked build-only questions on a research project, or vice versa. For any supplied as
   a flag (`kind=`, `autonomy=` or a mode's shorthand, `/cli …` / `clis=`,
   `/claudeforchrome` / `browser=`), use it and **don't** ask. For those NOT supplied,
   ask the missing ones in **one batched `AskUserQuestion`**:
   - **kind** — build / research.
   - **autonomy** — read `AUTONOMY.md` at the bundle root first. **Absent ⇒ don't ask at
     all**: `gated` is the only mode, so record it and move on. Present ⇒ offer `gated`
     (default) plus the modes it defines, described in that file's own terms.
   - **clis** (multi-select) — **pre-populate from what's actually available**: run
     `claude mcp list` for connected MCP servers and probe `PATH` for likely CLIs;
     show each with a ✓/✗ on whether it looks authenticated, plus "other" for free
     entry. Declarations — agents still verify a CLI works before relying on it.
   - **browser** — off (default) / claude-for-chrome.
   If **browser = claude-for-chrome** and the chosen mode **delegates browser writes**,
   don't block it — that combination is supported and deliberate. State once what it means
   so the choice is informed: agents may **write** in the human's logged-in browser
   (submit forms, change settings) without asking, including from background `/pm-loop`
   dispatches, and the extension's **per-site permissions** are then the effective
   boundary. Record that in `# Context` and continue. Otherwise browser writes ask first
   (see `SCHEMA.md` → "Browser access").
   If the chosen mode **delegates merging** on a build project, **run that mode's
   preflight now** (`AUTONOMY.md`) rather than letting the loop discover mid-run that the
   authority isn't exercisable: check whether the repo has an external PR reviewer, and
   whether it has any required status checks. Report the result in one line and record it
   in `# Context` — if either is missing, say plainly that every PR will still be surfaced
   for the human, and offer to fix it (configure the reviewer / branch protection) or to
   proceed knowing merges stay manual. Also flag at scaffold time that the project will
   otherwise **self-merge**, so the human knows before work starts.

   **b. Kind-specific fields.** Now that `kind` is settled: for `build`, resolve
   `target_repo` per the Inputs rules; for `research`, resolve the `deliverables` list
   (from `deliverables=`, the description, or ask) — no repo. Get an ISO timestamp once:
   `date -u +%Y-%m-%dT%H:%M:%SZ` — reuse it for every file's `timestamp`.

   These capability fields are **captured now, enforced later** (`autonomy` by the PM
   loop, per `AUTONOMY.md`; `browser` by the claude-in-chrome integration): creating a
   project never itself promotes, merges, or drives a browser.

5. **Scaffold `projects/<slug>/`**, matching the schema/example exactly:
   - `project.md` — `type: Project` frontmatter (`title`, `description`, `kind`,
     `objective: /objectives/<slug>.md`, `status: active`, `timestamp`) — plus
     `target_repo` for **build**, or `deliverables: [...]` for **research**; plus the
     capabilities from step 4: `autonomy:` (always; default `gated`), and `clis:` /
     `browser:` only when non-default (omit them otherwise) — and a `# Context` body
     that states what the project does and why, ending by linking its `index.md` and
     `log.md`.
   - `index.md` — `# <title> — tasks`, one bullet per seed task with its status.
   - `log.md` — `# <title> — log`, a `## <date>` heading and a **Created** bullet.
   - `tasks/` — derive seed tasks from the description. For a **research** project
     split by domain/team, create **one task + one deliverable stub per chunk**
     (`tasks/task-001-<chunk>.md` → `deliverables/<chunk>.md`). Otherwise a single
     `task-001-<slug>.md` capturing the main goal. Each task: `type: Task`, `kind`
     (matching the project), `status: draft`, `assignee:` empty,
     `acceptance_criteria: []`, `open_questions: []`, `timestamp`, body with a
     `# Context`. **Build** tasks carry `target_repo` (omit if same as project
     default) + `pr:`; **research** tasks carry `artifacts: [ <deliverable path> ]`
     instead. **Never invent `acceptance_criteria`** — leave them for the PM's refine.
   - For **research**, also create the `deliverables/` directory with a stub file per
     task (a title + a one-line "TODO: …" so the path exists and is committable).
   - `sources/` — always create it, with a short `sources/README.md` explaining that
     the user can drop any raw context here (images, transcripts, spreadsheets, PDFs,
     etc.) that serves as background or raw data for the project. The README makes the
     otherwise-empty folder committable.

6. **Register the project** (keep the bundle navigable):
   - Add a bullet under `## Projects` in the root `index.md`. For build:
     `[<title>](/projects/<slug>/project.md) - target: \`<target_repo>\` · <n> seed task(s)`.
     For research: `[<title>](/projects/<slug>/project.md) - research · <n> deliverable(s)`.
   - Add the project to the objective's "Projects serving this objective" list. If
     you created a new objective in step 3, also add it under `## Objectives` in the
     root `index.md`.
   - Prepend a dated **Project added** bullet to the root `log.md` (newest-first:
     reuse today's `## <date>` heading if present, else add it at the top of the
     dated entries).

7. **Show & commit.** Print the created tree, the `project.md` frontmatter, and the
   seed task titles. **Record the current `HEAD` sha before committing** — step 8 needs
   it as a review base. Then (unless `--no-commit`) stage and commit to this repo via
   the per-agent helper:
   `scripts/commit-as.sh human "feat: add <slug> project"`.
   Remind the user of the next step: the PM refines the drafts, then **you** promote
   `draft → ready`. For **build**, the PM then dispatches to a role agent → PR →
   you merge. For **research**, *you* work each task in-session (Claude + any
   available authoring/brand/slides skills) and write the deliverable; the PM only
   tracks status — `done` when you approve the deliverable.

8. **Second-opinion review of the scaffold — CodeRabbit CLI, when available.** A fresh
   reviewer catches what a scaffolding pass cannot see in itself: a `depends_on` missing a
   real prerequisite, a cross-reference left stale by a rename, a design rule with a hole
   in it. Run it **after** step 7 so the scaffold is a reviewable diff. **Skipped entirely
   under `--no-commit`** — there's no committed scaffold to diff against, so a committed
   review would see nothing. Skipped with a one-line note when the CLI isn't there —
   **never block project creation on this.**

   **a. Gate on availability.** First, if step 7 ran with `--no-commit`, stop here (nothing
   to review). Otherwise resolve the CodeRabbit CLI — it ships under two names, so try
   `command -v cr` then `command -v coderabbit` and keep whichever resolves as `<cli>` for the
   rest of this step. None found, not signed in, or `<cli> doctor` erroring → say so in one
   line and stop. The project already exists and is committed; this step is additive.

   **b. Run it scoped to the new project and wait for it** (a review takes ~1–2 min; run it
   synchronously and capture stdout — the triage in step c reads that output). Use the `<cli>`
   resolved in step a in place of `cr` below:

   ```bash
   cr review --agent --committed --base-commit <sha-from-step-7> \
             --dir <instance-root>/projects/<slug> -c CLAUDE.md SCHEMA.md
   ```

   `--dir` keeps it on the new project rather than the whole commit; `--base-commit` is the
   pre-commit `HEAD`; `-c` hands it the bundle's own rules so it reviews against `SCHEMA.md`
   and the instance `CLAUDE.md` instead of generic style; `--agent` returns structured
   findings. Confirm the flags with `cr review --help` before running — don't assume this
   surface, the CLI moves.

   **c. Triage before applying. On a fresh scaffold most findings are the reviewer not
   knowing the OKF lifecycle.** These are **by design — do not "fix" them**:
   - `acceptance_criteria: []` and `open_questions: []` — the PM fills these during refine;
     step 5 explicitly forbids inventing them.
   - `deliverables/*.md` TODO stubs — the deliverable **is** the work that hasn't happened
     yet; the stub only makes the path committable.
   - every task sitting at `status: draft` — that's the human's promotion gate.
   - a research project having no `target_repo`, no `pr:`, and no assignee.
   - the control panel committing straight to `main`.
   - a merge-delegating `autonomy` being near-inert on a research project — a documented consequence,
     not a defect.

   **Take these seriously** — each is a real defect worth a follow-up commit:
   - a `depends_on` that omits a genuine prerequisite, or a dependency cycle;
   - stale names, paths, or counts after a rename — typically the one file the restructure
     missed;
   - `project.md`, `index.md`, and the task bodies contradicting each other;
   - a security, privacy, or authorization hole in something the project *describes*
     (identity propagation, tenant boundaries, who may read what);
   - PII, secrets, tokens, or credentials in committed text — including in `sources/`;
   - a durable, verified discovery asserted in the scaffold but captured nowhere in
     `knowledge/findings/` — write the `Finding` and link it from the task.

   **d. Fail closed on an empty result.** Zero findings is a pass only if the command exited
   successfully **and** the output names the files it reviewed — an auth failure, an
   unconnected-organization notice, or a truncated run can exit non-zero or still read as
   "clean" with nothing reviewed. Check the exit status and confirm a files-reviewed line
   before calling it green; if either is missing, treat the run as indeterminate and say so
   rather than reporting a pass.

   **e. Record the verdicts.** Add a dated bullet to the project's `log.md` naming what you
   applied **and what you rejected, with the reason** — and make sure that entry is committed,
   not just the accepted fixes. Stage `log.md` alongside the fixes so they land in one commit,
   or record it in a follow-up commit if the fixes already landed; an uncommitted verdict
   record doesn't survive. Without it, the next reviewer re-raises the same by-design findings
   and someone eventually "fixes" them — deleting the PM's refine step or filling stubs with
   invented content.

## Notes
- This repo commits straight to `main` — that's intended (see `CLAUDE.md`); the
  human gates are promote-to-`ready` and (build) merge / (research) approve the
  deliverable, **not** file creation.
- For a big project, slice it into `phases/` (see `SCHEMA.md` `Phase`) — optional;
  skip unless the description clearly spans sequential stages.
- No customer PII in any task/project/log/deliverable text. `sources/README.md` should warn
  about **secrets as well as PII** — raw exports, HAR files, browser screenshots and support
  transcripts can be PII-free and still carry access tokens, API keys, signed URLs or
  internal hostnames. A committed token is leaked: rotate it, don't just delete the file.
- The step-8 review is **advisory**. It never promotes, never merges, and never gates
  creation — it produces findings you triage. Treat a rejected finding as a decision worth
  recording (in the project's `log.md`), not as something to argue with the tool about.
