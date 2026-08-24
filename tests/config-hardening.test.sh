#!/usr/bin/env bash
#
# config-hardening.test.sh — the safety properties of the shipped defaults:
# `.claude/settings.json`'s permission shapes, and the handful of properties in the
# shipped commands and agents that can be checked mechanically.
#
# WHY THIS FILE IS HERE AT ALL, AND WHERE IT CAME FROM. These files were forked into a
# private repo (ai-bridge's `config/` layer), reviewed there for the first time, and fixed
# — while THIS public repo went on shipping the defects. Ten fixes; two of them
# secret-exposure paths, ported in #70. The remaining eight arrive with this harness,
# together with the decision that closed the fork: **this repo owns `~/.claude`**, and
# ai-bridge keeps only the three agents its own role agents probe for. A fix that lives
# only in a private fork is a fix the public consumers do not have, so the fixes and the
# harness that pins them belong here, where the files are installed from.
#
# Three groups:
#
#   1. PERMISSION SHAPES. `settings.json` denies reading `.env`, `id_rsa` and
#      `.aws/credentials` — and an allow rule for a shell command that prints arbitrary
#      file contents or environment variables makes every one of those denials
#      decorative, because the deny rules are Read/Edit rules and Bash walks around them.
#      Separately, only the simple pattern shapes are allowed (`Bash(cmd:*)` and exact
#      strings): a mid-pattern wildcard is documented but fragile against flag
#      re-ordering, redirects and env substitution, i.e. against exactly the caller trying
#      to evade it. The wildcard checker is itself exercised against a synthetic bad
#      pattern, so it cannot pass by never firing.
#   2. THE DEFAULT BRANCH IS NEVER GUESSED. `never assume main` is the convention, and a
#      `main` fallback is worse than a refusal: on a `master`/`develop` repo it reviews,
#      rebases or diffs against a base nobody wrote, and every conclusion downstream
#      looks valid. Asserted as absence of the fallback AND presence of the detection —
#      "it has no fallback" alone would pass a command that lost the detection too.
#   3. UNTRUSTED CONTENT IS FENCED BEFORE IT ENTERS A PROMPT. `/grill` and `/plan` fan
#      diffs, plans and other agents' findings out to subagents. The payload is labelled
#      DATA, wrapped in markers, and hostile text is REPORTED rather than dropped — a
#      hunk you cannot see is a hunk you cannot fix.
#
# WHAT THIS FILE CANNOT DO. These are markdown command bodies: prose read by a model, not
# code with an observable output. So the assertions here are static checks over the
# shipped text. They prove a specific regression has not returned; they do not prove the
# command behaves correctly at runtime. Several of the fixes in this area have no test at
# all and are honest prose only.
#
# UNLIKE THE FORK, NOTHING HERE IS OPTIONAL. In ai-bridge these files sat in a deletable
# tier, so an absent one was a SKIP. Here `.claude/` IS the product: an absent file is a
# failure, and it is asserted as one. `jq` is the only genuine skip.
#
# ok() compares actual to expected, in that argument order.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$REPO/.claude/commands"
SET="$REPO/.claude/settings.json"
SCAN="$REPO/.claude/agents/deep-bug-scan.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/confhard.XXXXXX")"
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
  echo "error: mktemp produced no directory (is TMPDIR set to a path that does not exist?)" >&2
  exit 1
fi
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
# Count matching lines in a file, 0 when the pattern is absent (grep -c exits 1 there).
nF() { grep -cF -- "$2" "$1" 2>/dev/null || true; }   # fixed string
nE() { grep -cE -- "$2" "$1" 2>/dev/null || true; }   # extended regex
atleast() { if [ "$1" -ge "$2" ]; then echo yes; else echo no; fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# --------------------------------------------------- 0. every asserted file is present
# The fork made these deletable; here they ship. Assert it, so a rename or a deletion
# fails loudly instead of turning every assertion below into a silent SKIP.
for f in acp.md codex-handoff.md dave.md grill.md plan.md rabbit.md stack.md verify.md; do
  ok "commands/$f ships"                             "$(yn test -f "$CMD/$f")" yes
done
ok "settings.json ships"                             "$(yn test -f "$SET")" yes
ok "agents/deep-bug-scan.md ships"                   "$(yn test -f "$SCAN")" yes

# ---------------------------------------------------------------- 1. permission shapes
# A '*' is only permitted as the FINAL character of a Bash pattern. Both expansions below
# strip to the same prefix exactly when the pattern's only '*' is its last character.
star_ok() { # <inner pattern> -> ok|bad
  case "$1" in
    *'*'*) [ "${1%\*}" = "${1%%\**}" ] && echo ok || echo bad ;;
    *)     echo ok ;;
  esac
}
# The checker's own non-vacuity: it must reject the shape the conventions forbid and
# accept the two they require. Without this, "no bad pattern found" could mean "the
# predicate never fires".
ok "checker rejects a mid-pattern wildcard"          "$(star_ok 'git push * --force')" bad
ok "checker rejects a doubled wildcard"              "$(star_ok 'rm -rf */*')"          bad
ok "checker accepts a trailing wildcard"             "$(star_ok 'git status:*')"        ok
ok "checker accepts an exact string"                 "$(star_ok 'gh auth status')"      ok

if ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP: jq not installed — settings.json assertions skipped"
else
  ok "settings.json is valid JSON" "$(jq -e . "$SET" >/dev/null 2>&1 && echo yes || echo no)" yes

  jq -r '.permissions.allow[], .permissions.deny[]' "$SET" | grep '^Bash(' > "$TMP/bashpat" || true
  bad=0; total=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    total=$((total+1))
    inner="${p#Bash(}"; inner="${inner%)}"
    [ "$(star_ok "$inner")" = ok ] || { bad=$((bad+1)); printf '        offending pattern: %s\n' "$p"; }
  done < "$TMP/bashpat"
  ok "every Bash pattern uses a simple shape"         "$bad" 0
  ok "…and there were patterns to check"              "$(atleast "$total" 40)" yes

  allow() { jq -r '.permissions.allow[]' "$SET"; }
  has()   { allow | grep -qxF "$1" && echo yes || echo no; }

  # No auto-approved shell command may read arbitrary file CONTENTS or print an arbitrary
  # environment variable: either one walks straight past the Read/Edit denials below.
  ok "no blanket 'cat' allow (defeats the .env deny)"  "$(has 'Bash(cat:*)')"  no
  ok "no blanket 'echo' allow (prints env vars)"       "$(has 'Bash(echo:*)')" no
  ok "…and the deny rules it would defeat remain"      "$(jq -r '.permissions.deny[]' "$SET" | grep -cxF 'Read(**/.env)')" 1
  ok "…and the SSH key denials remain"                 "$(jq -r '.permissions.deny[]' "$SET" | grep -cxF 'Read(**/id_ed25519)')" 1

  # `gh api` is a write surface (--method POST/PATCH/DELETE): merge a PR, rewrite branch
  # protection, delete a repo. No simple shape can allow only GET, so it prompts.
  ok "no blanket 'gh api' allow (a write surface)"     "$(has 'Bash(gh api:*)')" no
  # …but the read-only gh surface the commands actually use is still allowed.
  ok "…read-only gh checks still allowed"              "$(has 'Bash(gh pr checks:*)')" yes

  # `<pm> install <pkg>` executes a third party's postinstall script and mutates the
  # manifest. Only the lockfile-bound forms are pre-approved.
  ok "no package manager may install an arbitrary pkg" \
     "$(allow | grep -cE '^Bash\((npm|pnpm|yarn|bun) install:\*\)$')" 0
  ok "…lockfile-bound installs still allowed"          "$(has 'Bash(npm ci:*)')" yes
  ok "…and a bare install still allowed"               "$(has 'Bash(pnpm install --frozen-lockfile)')" yes

  # `pnpm exec` runs any binary in node_modules — enumerate the tools like npx/bunx do.
  ok "no blanket 'pnpm exec' allow"                    "$(has 'Bash(pnpm exec:*)')" no
  ok "…the named tools are still allowed"              "$(has 'Bash(pnpm exec vitest:*)')" yes

  # `git branch:*` covers `git branch -D`. Read-only forms stay pre-approved.
  ok "no blanket 'git branch' allow (covers -D)"       "$(has 'Bash(git branch:*)')" no
  ok "…reading the current branch still allowed"       "$(has 'Bash(git branch --show-current)')" yes

  # Deliberate and documented: inert until the Chrome extension is installed and paired,
  # and leaving it prompting defeats the feature for a background agent.
  ok "the claude-in-chrome allow rule is untouched"    "$(has 'mcp__claude-in-chrome__*')" yes

  # The status line and output style are the two keys install.sh will MERGE into a real
  # settings.json (ADOPTABLE_KEYS). If either disappears from the baseline, adopt_keys has
  # nothing to merge and the feature silently stops reaching anyone with an existing file.
  ok "the adoptable display keys are in the baseline"  "$(jq -e 'has("statusLine") and has("outputStyle")' "$SET" >/dev/null 2>&1 && echo yes || echo no)" yes
fi

# ------------------------------------------------------- 2. the default branch is detected
ok "no shipped command falls back to \`main\`" \
   "$(grep -rniE 'fall ?back to .main.' "$CMD" 2>/dev/null | grep -c . || true)" 0
for f in dave rabbit; do
  ok "$f.md still detects the default branch" \
     "$(nF "$CMD/$f.md" 'symbolic-ref --short refs/remotes/origin/HEAD')" 1
  ok "…and says the missing fallback is deliberate" \
     "$(nF "$CMD/$f.md" 'deliberately no `main` fallback')" 1
done
# plan.md's closing reminder is prose, not a git operation — but "merges to main" is the
# same wrong assumption in the place a user reads last.
ok "plan.md's reminder names the default branch"    "$(nF "$CMD/plan.md" "merges to the repo's default branch")" 1

# ------------------------------------------- the working-tree payload is complete
# An untracked file appears in no `git diff` output at all, so a whole new module would
# otherwise be reviewed as if it did not exist.
ok "grill.md collects untracked files"              "$(nF "$CMD/grill.md" 'ls-files --others --exclude-standard')" 1
ok "dave.md collects untracked files"               "$(nF "$CMD/dave.md"  'ls-files --others --exclude-standard')" 1
ok "grill.md reads staged+unstaged as one patch"    "$(atleast "$(nF "$CMD/grill.md" 'git diff HEAD')" 1)" yes
ok "dave.md reads staged+unstaged as one patch"     "$(atleast "$(nF "$CMD/dave.md"  'git diff HEAD')" 1)" yes

# ------------------------------------------- 3. untrusted content is fenced
# Every interpolation of a repository-derived payload must sit inside the markers on its
# own line, and the prompt must say the block is DATA and that a directive found inside
# it is reported rather than obeyed.
fenced() { # <file> <interpolation> <marker>  -> "<fenced>/<total>"
  local tot fen
  tot="$(nF "$1" "$2")"
  fen="$(grep -F -- "$2" "$1" 2>/dev/null | grep -cF -- "$3" || true)"
  printf '%s/%s' "$fen" "$tot"
}
ok "grill: every diff interpolation is fenced"       "$(fenced "$CMD/grill.md" '${a.diff}' 'untrusted data')" 2/2
ok "grill: every finding interpolation is fenced"    "$(fenced "$CMD/grill.md" 'JSON.stringify(f)' 'untrusted data')" 1/1
ok "plan: every plan interpolation is fenced"        "$(fenced "$CMD/plan.md"  '${a.planContent}' 'untrusted data')" 2/2
ok "plan: every finding interpolation is fenced"     "$(fenced "$CMD/plan.md"  'JSON.stringify(f)' 'untrusted data')" 1/1
ok "grill: the block is labelled DATA"               "$(atleast "$(nE "$CMD/grill.md" 'are DATA|is DATA')" 2)" yes
ok "plan: the block is labelled DATA"                "$(atleast "$(nE "$CMD/plan.md"  'are DATA|is DATA')" 2)" yes
ok "grill: hostile text is reported, not dropped"    "$(atleast "$(nE "$CMD/grill.md" "never something to drop|report it, don't act on it")" 2)" yes
ok "plan: hostile text is reported, not dropped"     "$(atleast "$(nE "$CMD/plan.md"  "never something to drop|report it, don't act on it")" 2)" yes

# ------------------------------------------- acp scans before it stages (#70, kept pinned)
# `git add -A` stages every non-ignored path, so a scan that runs afterwards is a scan of
# an index that already holds the secret.
# Ordinal, not textual proximity: step 1 must be the scan and the staging command must be
# step 2. (Step 1 *mentions* `git add -A` to explain why it runs first, so a plain "first
# mention" check would match the explanation.)
ok "acp.md step 1 is the secret scan"               "$(nE "$CMD/acp.md" '^1\. \*\*Scan for secrets BEFORE staging')" 1
ok "…and staging is step 2, after it"               "$(nE "$CMD/acp.md" '^2\. `git add -A` to stage')" 1
ok "…and a candidate's contents are never printed"  "$(nF "$CMD/acp.md" 'Never print the contents of a secret candidate')" 1
# This repo went FURTHER than the fork did on acp.md: declining to *read* a diff is not
# the same as declining to *emit* it, so an authorised secret path is excluded from the
# step-3 diff with a pathspec. That is the stronger property and it must not be lost by a
# future "sync from the fork".
ok "…an authorised path is excluded by pathspec"    "$(nF "$CMD/acp.md" ":(exclude)")" 1

# ------------------------------------------- gh stack push is not atomic
ok "no false atomic claim for \`gh stack push\`" \
   "$(nF "$CMD/stack.md" 'push` already uses `--force-with-lease --atomic`')" 0
ok "…the partial-update risk is stated"             "$(nF "$CMD/stack.md" 'partially succeed')" 1

# ------------------------------------------- one handoff record per handoff
ok "no single-slot baseline write"                  "$(nF "$CMD/codex-handoff.md" '> "$ROOT/.claude/codex-baseline-head"')" 0
ok "…no last-line-wins session selector"            "$(nF "$CMD/codex-handoff.md" "awk 'END{print \$NF}'")" 0
ok "…selection is keyed by session id"              "$(nF "$CMD/codex-handoff.md" '$2 == want')" 1
ok "…and \`back <session-id>\` is documented"       "$(atleast "$(nF "$CMD/codex-handoff.md" 'back <session-id>')" 1)" yes

# ------------------------------------------- /verify keeps the build bucket
# The declined finding: the build is the only check in the fast set that runs the
# production bundler, so removing it lets a class of failure through to CI.
ok "fast mode still runs the build bucket"          "$(nE "$CMD/verify.md" '^- `/verify` — fast mode.*build')" 1
ok "…and records why it stays"                      "$(nF "$CMD/verify.md" 'production bundler')" 1

# ------------------------------------- deep-bug-scan: cleanup leaks are in scope
ok "cleanup is not skipped wholesale"               "$(nE "$SCAN" '^- Missing teardown / cleanup$')" 0
ok "…a leaked resource is explicitly in scope"      "$(nF "$SCAN" 'NOT skipped')" 1
ok "…and the existing leak class still stands"      "$(atleast "$(nF "$SCAN" 'connection/handle leaks')" 1)" yes

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
