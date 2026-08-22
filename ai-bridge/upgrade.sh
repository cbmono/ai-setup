#!/usr/bin/env bash
#
# upgrade.sh — bring ONE already-stamped ai-bridge instance up to date with this
# template, after a `git pull` here.
#
#   Usage: ai-bridge/upgrade.sh <instance-dir>            # report what a pull means (default)
#          ai-bridge/upgrade.sh <instance-dir> --apply    # write the safe changes
#
# WHY THIS EXISTS.
# README.md's "After pulling `ai-setup`" table says a pull reaches an instance in four
# different ways, and two of them need a human to do something. In practice nobody
# remembers which two, in what order, per instance — so the machinery ships instantly
# through its symlinks while the *data* it validates, and the seed content it assumes,
# quietly stay on the old rules. This is the one command that walks all four cases for
# one instance, in the order that works:
#
#   1. `install.sh <instance>`  — links machinery files the pull ADDED (edited ones
#      already arrived through the existing symlinks; that is the case needing nothing).
#   2. `scripts/validate-bundle.sh` — what the (possibly new) schema says is wrong.
#   3. `scripts/migrate-bundle.sh` — the mechanical repairs, report first.
#   4. SEED DRIFT — the case the table calls "port the change by hand", below.
#
# Install BEFORE migrate, because step 3 runs the instance's *symlink*: on an instance
# that predates those scripts, step 1 is what makes them exist at all.
#
# REPORT-ONLY BY DEFAULT, like `migrate-bundle.sh` and `prune-worktrees.sh`. A default
# run mutates nothing in the instance except the symlinks `install.sh` creates — and
# those are `install.sh`'s documented, blind-re-run-safe behaviour, not this script's.
# Read the report, then re-run with --apply.
#
# SEED DRIFT, AND WHY IT NEEDS A MERGE RATHER THAN A COPY.
# `install.sh` copies `seed/` into an instance **only if absent**, and that asymmetry is
# deliberate: seed files are the ones an instance then OWNS and edits (`instance.config.json`
# gets the group's org and reposRoot, `CLAUDE.md` gets house rules, `log.md` and `index.md`
# grow content). The cost is that a later seed edit never reaches an instance already
# stamped. Copying the new seed over the instance's copy would deliver it — and destroy
# whatever the instance wrote. So neither "copy" nor "leave it" is right, and the answer
# has to be per-file evidence:
#
#   · The seed file has only ever held its CURRENT content ⇒ there is no seed change to
#     deliver, so whatever the instance holds is entirely its own. Quiet. This is the normal
#     state of `log.md`, `index.md` and a `.gitignore` carrying the machinery block, and
#     naming them every run is how a report teaches people to stop reading it.
#   · The instance's copy is byte-identical to a PRIOR version of that seed file in this
#     repo's git history ⇒ nothing was ever hand-edited. That old seed IS the merge base,
#     provably, and the merge result is exactly the new seed. Measured: on 2026-08-22,
#     `_ai-bridge-private/CLAUDE.md` was the pre-v2 seed verbatim, and all three instances'
#     `README.md` were.
#   · It matches no prior version ⇒ it was hand-edited. The closest prior version by diff
#     size is used as a best-effort merge base and the seed's own change is applied ON TOP
#     of the instance's edits (`git merge-file`, i.e. a real 3-way merge, never a copy).
#     Clean ⇒ portable, and the hand edits survive by construction. Conflicting ⇒ reported
#     with the diff, and the file is not touched. Measured: `_ai-bridge-alteos` and
#     `_ai-bridge-proceso` have hand-diverged `CLAUDE.md`.
#   · No git history at all for the seed file (no repo, shallow clone, an uncommitted seed
#     file, a rename this script does not follow) ⇒ no merge base, no evidence, no action.
#     Reported for a human.
#
# "PRIOR" is doing real work in those rules. The current content's own blob is in the history
# too, and for a file the instance grew past it is often the blob CLOSEST to what the instance
# holds — pick it as the base and the base→seed diff is empty, the merge is a no-op, and real
# drift reports as "nothing to port". The fixture caught exactly that: a hand-diverged
# `CLAUDE.md` read as in sync.
#
# A CONFLICT IS NEVER RESOLVED BY FORCE. That is the whole point of the report: an instance's
# hand edits are the only copy of a decision somebody made, and this script cannot know
# whether the seed's new wording supersedes it.
#
# EVERY CLAIMED MUTATION IS READ BACK. `migrate-bundle.sh` once printed FIXED for a write
# that never landed, which is worse than the error it claimed to fix. So the PORTED label
# is printed only after the file on disk has been compared against the merge result and
# checked for conflict markers; otherwise it says FAILED, on stderr, and the run exits 1.
#
# NOT FOLDED INTO install.sh, on purpose. `install.sh` is safe to run blindly precisely
# because it only links and never overwrites; giving it a mutating mode would spend that
# property. `install.sh` only gained ONE non-fatal line pointing here when the instance's
# validator reports errors.
#
# Idempotent: a second run finds nothing to do. Refuses a directory that is not already an
# instance root — stamping a NEW instance is `install.sh`'s job, not an upgrade.
#
# Bash + awk + git only — no jq, no python.
# Verified by ai-bridge/tests/upgrade.test.sh.
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$TEMPLATE_DIR/$(basename "$0")"
SEED_SRC="$TEMPLATE_DIR/seed"
INSTALL_SH="$TEMPLATE_DIR/install.sh"
DIFF_CAP="${UPGRADE_DIFF_LINES:-40}"   # lines of a conflicting diff to print inline

APPLY=0
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    -h|--help)
      # Range covers the whole header block above. Extend it when you add lines
      # there, or --help truncates silently (same trap as install.sh's --help).
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'
      exit 0 ;;
    -*) echo "error: unknown flag '$arg'" >&2; exit 2 ;;
    *)
      [ -z "$TARGET" ] || { echo "error: multiple target directories given" >&2; exit 2; }
      TARGET="$arg" ;;
  esac
done
TARGET="$(cd "${TARGET:-$PWD}" 2>/dev/null && pwd || true)"
[ -n "$TARGET" ] || { echo "upgrade: target directory does not exist" >&2; exit 2; }
[ -d "$SEED_SRC" ] && [ -f "$INSTALL_SH" ] || {
  echo "upgrade: template is incomplete (expected $SEED_SRC and $INSTALL_SH)" >&2; exit 2; }

# An instance root, or refuse. SCHEMA.md is a symlink into the template, so test -L too:
# a *broken* SCHEMA.md link is exactly an instance that needs upgrading, not a stranger.
if [ ! -e "$TARGET/instance.config.json" ] || { [ ! -e "$TARGET/SCHEMA.md" ] && [ ! -L "$TARGET/SCHEMA.md" ]; }; then
  cat >&2 <<EOF
upgrade: $TARGET is not an ai-bridge instance root (expected SCHEMA.md + instance.config.json).
         To stamp a NEW instance, run: $INSTALL_SH $TARGET
EOF
  exit 2
fi

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/ai-bridge-upgrade.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

failed=0

# Echo up to <cap> findings from a sub-script's report, each as its LABEL line plus the
# indented message line under it, then say how many were left out. `grep -A1` would do
# it on GNU grep but interleaves `--` separators and is not portable, so: awk.
pairs_head() { # <file> <label-regex> <cap>
  awk -v re="$2" -v cap="$3" '
    $0 ~ re {
      total++
      if (total <= cap) { print "  " $0; if ((getline nx) > 0) print "  " nx }
      next
    }
    END { if (total > cap) printf "  … %d more finding(s) not shown\n", total - cap }
  ' "$1"
}

LEFT_N=0
left() { LEFT_N=$((LEFT_N+1)); printf '%2d. %s\n' "$LEFT_N" "$1" >> "$TMPD/left"; }
left_more() { printf '    %s\n' "$1" >> "$TMPD/left"; }
: > "$TMPD/left"
: > "$TMPD/conflicts"

echo "ai-bridge upgrade — $TARGET"
echo "template: $TEMPLATE_DIR"
if [ "$APPLY" -eq 1 ]; then
  echo "mode:     APPLY — the safe changes below WILL be written."
else
  # Be exact about what a report-only run still writes. install.sh links machinery AND
  # copies any *absent* seed file back (its documented seeds-if-absent contract), so
  # "nothing changes" would be false. Stage 4 below — the part that rewrites content the
  # instance has edited — is the part that truly waits for --apply.
  echo "mode:     REPORT ONLY — no instance content is rewritten."
  echo "          (install.sh below still links machinery and restores any ABSENT seed file.)"
fi

# ---------------------------------------------------------------- 1. machinery
echo
echo "== 1/4  machinery symlinks (install.sh) =============================="
# Sampled BEFORE install.sh runs, because install.sh is about to undo it.
#
# `AUTONOMY.md` is the deletable delegated-autonomy capability: absent, every project is
# `gated`, and `commit-as.sh` gates its promotion guard on the same presence check. But it
# lives under symlink/, so it is MACHINERY — and install.sh re-links every machinery file
# unconditionally, by design, because repairing broken links is the whole point of a
# refresh. The two behaviours collide: `rm AUTONOMY.md` disables autonomy for one
# instance, and the next refresh silently switches it back on. That is fail-OPEN on the
# one capability that lets agents merge without asking, so it cannot pass unremarked.
# Reporting it is this script's job; changing install.sh's machinery contract is not.
autonomy_was_absent=no
[ -e "$TARGET/AUTONOMY.md" ] || [ -L "$TARGET/AUTONOMY.md" ] || autonomy_was_absent=yes
inst_rc=0
bash "$INSTALL_SH" "$TARGET" > "$TMPD/install.out" 2>&1 || inst_rc=$?
# install.sh prints one line per machinery file. Echo only the lines that mean
# something changed or needs attention; count the rest.
awk '
  /^  (ok|keep|skip)  / { quiet++; next }
  /^  (link|moved|seed|warn) / { print "  " $0; next }
  { print "  " $0 }
  END { printf "  (%d entries already in place)\n", quiet }
' "$TMPD/install.out"
if [ "$inst_rc" -ne 0 ]; then
  echo "  install.sh exited $inst_rc — see the output above" >&2
  # Count it, so the run exits non-zero. install.sh is the PREREQUISITE for everything
  # below: the machinery symlinks it places are what the later stages read. Reporting a
  # failed install through a 0 exit would let a caller (a CI step, a wrapper script, JM
  # following the printed instructions) treat "machinery never installed" as success.
  failed=$((failed+1))
  left "install.sh failed (exit $inst_rc) — fix that first, then re-run this script."
fi
NEW_LINKS="$(awk '/^  link  /{n++} END{print n+0}' "$TMPD/install.out")"
echo "  summary: $NEW_LINKS new machinery symlink(s)."
if [ "$autonomy_was_absent" = yes ] && { [ -e "$TARGET/AUTONOMY.md" ] || [ -L "$TARGET/AUTONOMY.md" ]; }; then
  echo "  WARNING  AUTONOMY.md was absent and install.sh re-linked it." >&2
  left "DELEGATED AUTONOMY WAS RE-ENABLED. AUTONOMY.md was absent in this instance"
  left_more "(so every project was 'gated'), and install.sh re-linked it as machinery."
  left_more "If that was deliberate, turn it off again:  rm $TARGET/AUTONOMY.md"
fi

# ---------------------------------------------------------------- 2. validate
echo
echo "== 2/4  bundle validation (scripts/validate-bundle.sh) ==============="
VAL_ERRORS=0
if [ ! -e "$TARGET/scripts/validate-bundle.sh" ]; then
  echo "  not present in this instance — skipped."
else
  val_rc=0
  ( cd "$TARGET" && bash scripts/validate-bundle.sh ) > "$TMPD/val.out" 2>&1 || val_rc=$?
  # Both scripts print a finding as a LABEL line plus an indented message line, so echo
  # the pair — the label alone says nothing about what is wrong.
  pairs_head "$TMPD/val.out" '^  (ERROR|WARN) ' 12
  sed -n 's/^validate-bundle: /  summary: /p' "$TMPD/val.out"
  VAL_ERRORS="$(awk '/^validate-bundle: /{for(i=1;i<=NF;i++) if ($i ~ /^errors,?$/) print $(i-1)+0}' "$TMPD/val.out" | head -1)"
  [ -n "$VAL_ERRORS" ] || VAL_ERRORS=0
  if [ "$val_rc" -ne 0 ] && [ "$VAL_ERRORS" -eq 0 ]; then
    echo "  validator exited $val_rc without reporting errors — see above" >&2
  fi
fi

# ---------------------------------------------------------------- 3. migrate
echo
echo "== 3/4  schema migration (scripts/migrate-bundle.sh) ================="
MIG_HUMAN=0; MIG_FIX=0
if [ ! -e "$TARGET/scripts/migrate-bundle.sh" ]; then
  echo "  not present in this instance — skipped."
else
  mig_rc=0
  if [ "$APPLY" -eq 1 ]; then
    ( cd "$TARGET" && bash scripts/migrate-bundle.sh --apply ) > "$TMPD/mig.out" 2>&1 || mig_rc=$?
  else
    ( cd "$TARGET" && bash scripts/migrate-bundle.sh ) > "$TMPD/mig.out" 2>&1 || mig_rc=$?
  fi
  pairs_head "$TMPD/mig.out" '^  (WOULD FIX|FIXED|FAILED|HUMAN|SKIPPED) ' 20
  sed -n 's/^migrate-bundle: /  summary: /p' "$TMPD/mig.out"
  # "N would be fixed, M need a human, …" (report) and "N fixed, M left for a human, …"
  # (apply) — parsed field-wise rather than with a sed alternation, which BSD sed's BRE
  # does not support.
  mig_sum="$(awk '/^migrate-bundle: /{
      n=split($0, a, ", "); sub(/^migrate-bundle: /, "", a[1]);
      fix=a[1]+0; hum=0;
      for (i=1;i<=n;i++) if (a[i] ~ /human/) { h=a[i]; sub(/[^0-9]*/, "", h); hum=h+0 }
      printf "%d %d\n", fix, hum; exit
    }' "$TMPD/mig.out")"
  if [ -n "$mig_sum" ]; then MIG_FIX="${mig_sum%% *}"; MIG_HUMAN="${mig_sum##* }"; fi
  if [ "$mig_rc" -ne 0 ]; then
    echo "  migrate-bundle exited $mig_rc — a write did not land; its FAILED lines are above" >&2
    failed=$((failed+1))
  fi
fi

# ---------------------------------------------------------------- 4. seed drift
echo
echo "== 4/4  seed drift (seed/ edits never reach a stamped instance) ======"

# Every git query below runs from the REPO ROOT with root-relative paths. `git -C <dir>`
# makes a pathspec relative to <dir>, so querying from the template dir with the path
# git reports for it ("ai-bridge/seed/…") silently matched nothing — and "no history"
# is indistinguishable from "no evidence", which downgraded every drifted file to
# UNKNOWN. Resolve the root once, and prefix paths with the template's own prefix.
GIT_OK=1
REPO_ROOT=""; PREFIX=""
if git -C "$TEMPLATE_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$TEMPLATE_DIR" rev-parse --show-toplevel)"
  PREFIX="$(git -C "$TEMPLATE_DIR" rev-parse --show-prefix)"
else
  GIT_OK=0
fi
[ "$GIT_OK" -eq 1 ] || echo "  note: the template is not a git checkout, so no merge base can be"
[ "$GIT_OK" -eq 1 ] || echo "        established — differing files can only be reported, never ported."

# Every historical blob of a seed path, newest first, deduplicated. Renames are NOT
# followed: a renamed seed file simply has less history, which degrades to "no base"
# (reported) rather than to a wrong base (ported).
hist_blobs() { # <repo-relative path>
  [ "$GIT_OK" -eq 1 ] || return 0
  git -C "$REPO_ROOT" log --format=%H -- "$1" 2>/dev/null | while IFS= read -r c; do
    git -C "$REPO_ROOT" ls-tree "$c" -- "$1" 2>/dev/null | awk '{print $3}'
  done | awk 'NF && !seen[$0]++'
}

blob_of() { git -C "$TEMPLATE_DIR" hash-object --no-filters -- "$1"; }

# Changed-line count between two files. awk rather than `grep -c`, because grep exits 1
# on zero matches and `set -o pipefail` would turn "identical" into a script failure.
diffcount() { # <a> <b>
  diff "$1" "$2" > "$TMPD/dc" 2>/dev/null || true
  awk '/^[<>]/{n++} END{print n+0}' "$TMPD/dc"
}

# Write the merged content, keeping the target's mode, via a rename inside the target's
# own directory: `mktemp` in $TMPDIR is mode 0600 and possibly on another filesystem, so
# moving from there would silently re-permission the file and make the write non-atomic.
# (Same reasoning as migrate-bundle.sh's temp_beside.)
write_beside() { # <merged> <target-file>
  local src="$1" f="$2" d t m
  d="$(dirname "$f")"
  t="$(mktemp "$d/.upgrade.XXXXXX" 2>/dev/null)" || return 1
  m="$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null || echo 644)"
  chmod "$m" "$t" 2>/dev/null || true
  cat "$src" > "$t" && mv "$t" "$f"
}

report() { printf '  %-9s %s\n' "$1" "$2"; }
detail() { printf '            %s\n' "$1"; }

# `bridge.code-workspace` is seeded under a group-specific NAME with this instance's
# absolute path stamped into it (see install.sh), so its instance copy can never match a
# seed blob and a "port" would rewrite a machine-local path. `.gitkeep` files are empty
# placeholders install.sh already skips once a directory has real content. Neither is
# seed drift; both are excluded rather than reported as permanent conflicts.
seed_paths() {
  ( cd "$SEED_SRC" && find . -type f | sed 's#^\./##' | sort ) \
    | grep -v '^bridge\.code-workspace$' | grep -v '\.gitkeep$'
}

insync=0; portable=0; ported=0; conflict=0; unknown=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  seed_f="$SEED_SRC/$rel"; inst_f="$TARGET/$rel"

  if [ ! -e "$inst_f" ]; then
    report "absent" "$rel"
    detail "install.sh did not place it (a populated directory needs no placeholder)."
    continue
  fi
  # `-e` is true for a directory, a symlink to one, a fifo. Everything below assumes a
  # regular file: `git hash-object` and `cp` both fail on a directory, and since the hash
  # is taken in an assignment's command substitution, `set -e` would abort the WHOLE
  # upgrade there — losing the report for every remaining file instead of flagging this
  # one. A seeded path replaced by a directory is a real instance shape (someone made
  # `log.md/` a folder), so classify it and keep going.
  if [ ! -f "$inst_f" ] || [ -L "$inst_f" ]; then
    unknown=$((unknown+1))
    report "UNKNOWN" "$rel"
    detail "instance path is not a regular file — left untouched; compare it with $seed_f by hand."
    continue
  fi
  if cmp -s "$seed_f" "$inst_f"; then
    insync=$((insync+1)); continue   # identical to the current seed: quiet by design
  fi

  # Candidate merge bases: the seed file's PRIOR versions — every historical blob except
  # the content the seed has right now.
  #
  # Excluding the current content is load-bearing, not tidiness. The latest commit's blob
  # is in the history too, and for a file the instance has grown past (`log.md`, a
  # `.gitignore` with the machinery block appended) it is often the *closest* blob to what
  # the instance holds. Chosen as the base, the base→seed diff is empty, the merge is a
  # no-op, and real drift is silently reported as "nothing to port". The fixture caught
  # exactly that: a hand-diverged CLAUDE.md read as in sync.
  inst_hash="$(blob_of "$inst_f")"
  seed_hash="$(blob_of "$seed_f")"
  # The heredoc feeds this loop in the CURRENT shell (no pipe), so `any_history` survives
  # it — the difference between "the seed never changed" and "there is no history at all".
  : > "$TMPD/prior"
  any_history=0
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    any_history=1
    [ "$b" = "$seed_hash" ] || printf '%s\n' "$b" >> "$TMPD/prior"
  done <<EOF
$(hist_blobs "${PREFIX}seed/$rel")
EOF

  if [ ! -s "$TMPD/prior" ]; then
    if [ "$any_history" -eq 1 ]; then
      # The seed file has only ever held its current content, so there is no seed change
      # to deliver: the difference is entirely the instance's own. Quiet on purpose — this
      # is the normal state of `log.md`, `index.md` and a managed `.gitignore`, and naming
      # them every run is how a report teaches people to stop reading it.
      insync=$((insync+1)); continue
    fi
    unknown=$((unknown+1))
    report "UNKNOWN" "$rel"
    detail "differs from the seed, and this template has no git history for it — so"
    detail "there is no merge base and no evidence. Compare by hand:"
    detail "  diff '$inst_f' '$seed_f'"
    continue
  fi

  # The prior version the instance copy IS, if any — that is provable provenance, so it
  # wins. Otherwise the closest prior version by diff size, as a best effort.
  base_blob=""; base_kind=""
  while IFS= read -r b; do
    if [ "$b" = "$inst_hash" ]; then base_blob="$b"; base_kind="verbatim"; break; fi
  done < "$TMPD/prior"

  if [ "$base_kind" != "verbatim" ]; then
    best=""; bestn=""
    while IFS= read -r b; do
      git -C "$REPO_ROOT" cat-file blob "$b" > "$TMPD/cand" 2>/dev/null || continue
      n="$(diffcount "$TMPD/cand" "$inst_f")"
      if [ -z "$bestn" ] || [ "$n" -lt "$bestn" ]; then bestn="$n"; best="$b"; fi
    done < "$TMPD/prior"
    [ -z "$best" ] || { base_blob="$best"; base_kind="closest"; }
  fi

  if [ -z "$base_blob" ]; then
    unknown=$((unknown+1))
    report "UNKNOWN" "$rel"
    detail "differs from the seed, and no prior seed version could be read — so there is"
    detail "no merge base and no evidence. Compare by hand:"
    detail "  diff '$inst_f' '$seed_f'"
    continue
  fi

  git -C "$REPO_ROOT" cat-file blob "$base_blob" > "$TMPD/base"
  cp "$inst_f" "$TMPD/ours"
  merge_rc=0
  git merge-file -q -p \
    -L "$rel (this instance)" -L "seed @ ${base_blob}" -L "seed (new)" \
    "$TMPD/ours" "$TMPD/base" "$seed_f" > "$TMPD/merged" 2>/dev/null || merge_rc=$?

  short="$(printf '%s' "$base_blob" | cut -c1-8)"
  if [ "$merge_rc" -ge 255 ]; then
    unknown=$((unknown+1))
    report "UNKNOWN" "$rel"
    detail "git merge-file could not merge it (exit $merge_rc). Compare by hand:"
    detail "  diff '$inst_f' '$seed_f'"
    continue
  fi

  if [ "$merge_rc" -gt 0 ]; then
    conflict=$((conflict+1))
    report "CONFLICT" "$rel"
    detail "hand-diverged from the seed ($merge_rc conflicting hunk(s)) — NOT touched."
    detail "the seed change to port, relative to base $short:"
    # The ---/+++ header names temp paths, which tells the reader nothing; the hunks are
    # the message. Header lines are dropped rather than relabelled.
    diff -u "$TMPD/base" "$seed_f" > "$TMPD/sd" 2>/dev/null || true
    awk -v cap="$DIFF_CAP" '
      NR<=2 && /^(---|\+\+\+) / { next }
      { n++; if (n<=cap) print "              " $0 }
      END { if (n>cap) printf "              … %d more diff line(s)\n", n-cap }
    ' "$TMPD/sd"
    detail "port it by hand, then re-run. Full diff of what you have vs the seed:"
    detail "  diff -u '$inst_f' '$seed_f'"
    printf '%s\n' "$rel" >> "$TMPD/conflicts"
    continue
  fi

  if cmp -s "$TMPD/merged" "$inst_f"; then
    insync=$((insync+1)); continue   # the seed has no change this instance lacks
  fi

  if [ "$APPLY" -eq 0 ]; then
    portable=$((portable+1))
    report "PORTABLE" "$rel"
    if [ "$base_kind" = "verbatim" ]; then
      detail "the instance copy is the seed verbatim as of $short — porting is exact."
    else
      detail "the seed change merges cleanly onto this instance's edits (base $short)."
    fi
    continue
  fi

  # --apply: write the MERGE RESULT, never a copy of the seed, then read it back.
  # A hand-edited file is backed up first; a verbatim old seed is not, because its
  # content is recoverable from this template's git history and the backup would be
  # clutter a later run has to explain.
  bak=""
  if [ "$base_kind" != "verbatim" ]; then
    bak="$inst_f.bak.$(date +%s)"
    cp "$inst_f" "$bak"
  fi
  if write_beside "$TMPD/merged" "$inst_f" \
     && cmp -s "$TMPD/merged" "$inst_f" \
     && ! grep -qE '^(<<<<<<< |>>>>>>> )' "$inst_f"; then
    ported=$((ported+1))
    report "PORTED" "$rel"
    if [ "$base_kind" = "verbatim" ]; then
      detail "was the seed verbatim as of $short; now the current seed (verified)."
    else
      detail "seed change merged onto this instance's edits (base $short, verified)."
      detail "backup: $(basename "$bak")"
    fi
  else
    failed=$((failed+1))
    report "FAILED" "$rel" >&2
    printf '            %s\n' "the port did not land — the file was left as it was." >&2
    [ -z "$bak" ] || printf '            %s\n' "backup: $bak" >&2
  fi
done <<EOF
$(seed_paths)
EOF

printf '  summary: %d in sync or with nothing to port, %d portable, %d ported, %d conflicting, %d unknown.\n' \
  "$insync" "$portable" "$ported" "$conflict" "$unknown"
[ "$APPLY" -eq 1 ] || [ "$portable" -eq 0 ] || echo "  (report only — nothing was written)"

# ------------------------------------------------------------ what's left for you
#
# Assembled here rather than as the sections run, so the list reads in the order a
# human would act: re-run with --apply first (it subsumes several items), then the
# decisions only they can make, then the commit.
if [ "$APPLY" -eq 0 ] && { [ "$MIG_FIX" -gt 0 ] || [ "$portable" -gt 0 ]; }; then
  left "re-run with --apply to write the safe changes ($MIG_FIX schema repair(s), $portable seed file(s)):"
  left_more "$SELF '$TARGET' --apply"
fi
# install.sh already printed these in stage 1; repeat them here because the numbered list
# is what a human actually reads and acts on, and this is a decision only they can make.
STALE_N="$(awk '/^  stale /{n++} END{print n+0}' "$TMPD/install.out")"
if [ "$STALE_N" -gt 0 ]; then
  left "$STALE_N retired file(s) are still in this instance — the template stopped"
  left_more "shipping them, but the contents are yours, so nothing was deleted. Each"
  left_more "'stale' line in stage 1 above prints the exact rm command."
fi
if [ "$MIG_HUMAN" -gt 0 ]; then
  left "$MIG_HUMAN document(s) need a decision only you can make (a dangling reference,"
  left_more "an unrecognised status). Read its HUMAN lines:"
  left_more "cd '$TARGET' && scripts/migrate-bundle.sh"
fi
if [ -s "$TMPD/conflicts" ]; then
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    left "port the seed change into $c by hand — it is hand-diverged, so nothing was"
    left_more "written. What you have vs the seed:"
    left_more "diff -u '$TARGET/$c' '$SEED_SRC/$c'"
  done < "$TMPD/conflicts"
fi
if [ "$unknown" -gt 0 ]; then
  left "$unknown seed file(s) differ with no merge base to judge them by — compare by"
  left_more "hand using the commands printed under UNKNOWN above."
fi
if [ "$VAL_ERRORS" -gt 0 ] && [ "$APPLY" -eq 1 ]; then
  left "re-check the bundle: $VAL_ERRORS error(s) were reported before the migration ran,"
  left_more "and anything still listed needs a human:"
  left_more "cd '$TARGET' && scripts/validate-bundle.sh"
fi
if [ "$ported" -gt 0 ] || { [ "$APPLY" -eq 1 ] && [ "$MIG_FIX" -gt 0 ]; }; then
  left "review and commit what changed — the instance is its own git repo:"
  left_more "cd '$TARGET' && git status && git diff"
fi

echo
echo "== what's left for you ==============================================="
if [ "$LEFT_N" -eq 0 ]; then
  echo "  Nothing. This instance is up to date with the template."
else
  cat "$TMPD/left"
fi

[ "$failed" -eq 0 ] || {
  echo
  echo "upgrade: $failed claimed change(s) did not land — see the FAILED lines above." >&2
  exit 1
}
exit 0
