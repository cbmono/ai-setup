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

4. **Resolve kind-specific fields.** For `build`: resolve `target_repo` per the
   Inputs rules. For `research`: resolve the `deliverables` list (from
   `deliverables=`, the description, or ask) — no repo. Get an ISO timestamp once:
   `date -u +%Y-%m-%dT%H:%M:%SZ` — reuse it for every file's `timestamp`.

5. **Scaffold `projects/<slug>/`**, matching the schema/example exactly:
   - `project.md` — `type: Project` frontmatter (`title`, `description`, `kind`,
     `objective: /objectives/<slug>.md`, `status: active`, `timestamp`) — plus
     `target_repo` for **build**, or `deliverables: [...]` for **research** — and a
     `# Context` body that states what the project does and why, ending by linking
     its `index.md` and `log.md`.
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
   seed task titles. Then (unless `--no-commit`) stage and commit to this repo via
   the per-agent helper:
   `scripts/commit-as.sh human "feat: add <slug> project"`.
   Remind the user of the next step: the PM refines the drafts, then **you** promote
   `draft → ready`. For **build**, the PM then dispatches to a role agent → PR →
   you merge. For **research**, *you* work each task in-session (Claude + any
   available authoring/brand/slides skills) and write the deliverable; the PM only
   tracks status — `done` when you approve the deliverable.

## Notes
- This repo commits straight to `main` — that's intended (see `CLAUDE.md`); the
  human gates are promote-to-`ready` and (build) merge / (research) approve the
  deliverable, **not** file creation.
- For a big project, slice it into `phases/` (see `SCHEMA.md` `Phase`) — optional;
  skip unless the description clearly spans sequential stages.
- No customer PII in any task/project/log/deliverable text.
