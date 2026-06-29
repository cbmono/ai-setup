# ai-bridge (template)

A reusable **OKF Knowledge Bundle control panel** for orchestrating background AI
agents against a group's product repositories. This directory is the **generic
template**; you stamp out one **instance** per group (work, side project, …),
each its own git repo.

```
ai-setup/ai-bridge/        # this template (lives in the ai-setup repo)
├── install.sh                    # stamp out / refresh an instance
├── symlink/                      # generic machinery → symlinked into instances (gitignored there)
│   ├── SCHEMA.md  agents/index.md  scripts/commit-as.sh
│   └── .claude/{agents/*, commands/{pm-loop,pr-review-request,new-project}.md, settings.json}
└── seed/                         # starting content → copied into an instance once (then yours)
    ├── instance.config.json  CLAUDE.md  README.md  index.md  log.md  .gitignore
    ├── bridge.code-workspace     # multi-root editor view: control panel + group repos
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
$EDITOR instance.config.json          # set org, reposRoot, authorEmail
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
From inside an instance: `/pm-loop 10m` (serial, completion-gated; one tick at a
time). Add work with `/new-project <description>`. Two human gates stay yours:
promote `draft → ready`, and merge the PR (build) / approve the deliverable (research).

## Projects: build & research
Projects come in two `kind`s (see `symlink/SCHEMA.md`):
- **`build`** (default) — ships code to a `target_repo` as PRs; role agents execute,
  you merge. The full `draft → ready → dispatch → PR → merge` loop.
- **`research`** — produces **deliverables inside the bundle** (docs, marp/pptx decks,
  assets under `projects/<slug>/deliverables/`); no repo, no PRs, **human-driven**
  (the PM tracks but never dispatches them). These are the strategic entry points
  whose conclusions graduate into `knowledge/` and spawn objectives + build projects.

`/new-project` scaffolds either; pass `kind=research` for the latter.

## Editor view (control panel + repos in one tree)
The product repos stay **physical peers** of the instance, never nested inside it
— nesting would drag the instance's control-panel `CLAUDE.md` into the cascade of
every product-repo session (telling them they're a control panel that commits to
`main`). To still see everything in one tree:
- **VS Code / Cursor / Antigravity** — open the seeded **`bridge.code-workspace`**
  (*Open Workspace from File…*): a multi-root view, control panel pinned on top,
  group repos below. A generic `files.exclude` glob (`_ai-bridge-*`) hides the
  instance from the repos pane so it isn't shown twice.
- **Zed** (no workspace-file support) — open the **group folder**; the instance's
  `_`-prefix already sorts it to the top.

It only changes the editor display; nothing moves on disk. **Regardless of editor,
launch Claude by `cd`-ing into the instance dir and running `claude` there** — the
editor's open folder doesn't affect which `.claude/` loads; the working directory
does.

## Per-instance settings
`.claude/settings.json` is **shared machinery** (symlinked) — editing it changes
every instance. For permissions or env an instance needs on its own (e.g. allow
`Bash` in that group's repos), put them in `.claude/settings.local.json` in the
instance: it's local, gitignored, layered on top, and never touches the template.

## Machinery is machine-local
The symlinks point at absolute paths into this template and are gitignored in the
instance, so a clone on another machine has the committed instance data but
**dangling** machinery until you re-run `install.sh` there. That's intentional —
the machinery is sourced from `ai-setup`, not vendored into each instance.

## Updating the machinery
Edit files under `symlink/` here and commit to `ai-setup`. Because instances
symlink them, every instance picks up the change immediately — re-run `install.sh`
on an instance only when you **add** new machinery files (to refresh its symlink
set and `.gitignore` block). Keep machinery generic: no org, repo, path, team, or
channel literals — those belong in each instance's `instance.config.json` /
`CLAUDE.md`.
