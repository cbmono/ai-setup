---
description: Show how much of your Claude Code work you actually delegated to sub-agents
allowed-tools: Bash
---

Show the user their own delegation stats for a month.

Argument (optional): a month as `YYYY-MM`. If `$ARGUMENTS` is empty, use the current month.

Run exactly this, substituting the month, then show the user the output verbatim.
Do not summarise it away — the table *is* the answer. Add at most two sentences of comment.

```bash
python3 - <<'PY' $ARGUMENTS
import pathlib, sys, datetime, calendar

arg = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
today = datetime.date.today()
if arg:
    y, m = (int(x) for x in arg.split("-")[:2])
else:
    y, m = today.year, today.month
lo = datetime.datetime(y, m, 1).timestamp()
hi = datetime.datetime(y + (m == 12), (m % 12) + 1, 1).timestamp()

root = pathlib.Path.home() / ".claude" / "projects"
SIDE = b'"isSidechain":true'

top = side = 0
for f in root.rglob("*.jsonl"):
    try:
        if not (lo <= f.stat().st_mtime < hi):
            continue
    except OSError:
        continue
    is_side = False
    with f.open("rb") as fh:
        prev = b""
        while chunk := fh.read(1 << 22):
            buf = prev + chunk
            if SIDE in buf:
                is_side = True
                break
            prev = buf[-32:]
    side += is_side
    top += not is_side

runs = top + side
print(f"\n  Your Claude Code delegation — {calendar.month_name[m]} {y}   (this machine)")
print(f"  {'-'*58}")
print(f"  {'sub-agent runs — work you handed over':<45}{side:>6}")
print(f"  {'top-level sessions — you steering a thread':<45}{top:>6}")
print(f"  {'-'*58}")
share = f"{100*side/runs:.1f}%" if runs else "--"
print(f"  {'DELEGATED SHARE':<45}{share:>6}")
print(f"\n  {runs} runs scanned. Nothing leaves this machine.\n")
PY
```

Notes to pass on if the user asks:

- **`DELEGATED SHARE` is the whole point.** It is the share of your Claude Code runs that
  were sub-agents doing work on your behalf, rather than you steering a thread yourself.
  Higher is better. If it is near zero, you are working at rung ③/④, not ⑤.
- Read from `~/.claude/projects` on **this machine only**. Nothing is uploaded; no other
  person's data is visible or involved. If you use more than one machine, run it on each.
- Files are bucketed by last-modified time, so a session spanning a month boundary lands in
  the month it was last touched. Fine for a monthly trend; not exact.
- **Deliberately only two counts.** Anything derived from counting `Task` dispatches in the
  parent transcript is unreliable — the dispatch is frequently recorded in the child's
  transcript instead, which undercounts the parent badly. Sidechain vs top-level is the one
  distinction the local data records cleanly.
- This exists because the org dashboard's `delegated` figure does **not** count in-process
  sub-agent runs: one heavy user's machine showed 788 sub-agent runs in August while the
  whole organisation's reported figure for the same window was 287. This command measures
  the behaviour the dashboard cannot see.
