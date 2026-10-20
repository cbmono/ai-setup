---
description: Show how much of your Claude Code work you actually delegated to sub-agents, background and headless sessions
allowed-tools: Bash
---

Show the user their own delegation stats for a month.

Argument (optional): a month as `YYYY-MM`. If `$ARGUMENTS` is empty, use the current month.

Run exactly this, substituting the month, then show the user the output verbatim.
Do not summarise it away — the table *is* the answer. Add at most two sentences of comment.

```bash
python3 - <<'PY' $ARGUMENTS
import pathlib, re, sys, datetime, calendar

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
BG = b'"sessionKind":"bg"'
ENTRY = re.compile(rb'"entrypoint":"([^"]+)"')

side = bg = sdk = live = 0
for f in root.rglob("*.jsonl"):
    try:
        if not (lo <= f.stat().st_mtime < hi):
            continue
    except OSError:
        continue
    is_side = is_bg = False
    entry = None
    with f.open("rb") as fh:
        prev = b""
        while chunk := fh.read(1 << 22):
            buf = prev + chunk
            if SIDE in buf:
                is_side = True
                break
            is_bg = is_bg or BG in buf
            if entry is None and (mt := ENTRY.search(buf)):
                entry = mt.group(1)
            prev = buf[-32:]
    if is_side:
        side += 1
    elif is_bg:
        bg += 1
    elif entry and entry.startswith(b"sdk-"):
        sdk += 1
    else:
        live += 1

runs = side + bg + sdk + live
delegated = side + bg + sdk
print(f"\n  Your Claude Code delegation — {calendar.month_name[m]} {y}   (this machine)")
print(f"  {'-'*58}")
print(f"  {'in-process sub-agents (Agent/Task tool)':<45}{side:>6}")
print(f"  {'background sessions (claude --bg)':<45}{bg:>6}")
print(f"  {'headless / SDK sessions (-p, Agent SDK)':<45}{sdk:>6}")
print(f"  {'interactive sessions — you steering':<45}{live:>6}")
print(f"  {'-'*58}")
share = f"{100*delegated/runs:.1f}%" if runs else "--"
print(f"  {'DELEGATED SHARE':<45}{share:>6}")
print(f"\n  {runs} runs scanned. Nothing leaves this machine.\n")
PY
```

Notes to pass on if the user asks:

- **`DELEGATED SHARE` is the whole point.** It is the share of your Claude Code runs that
  did work on your behalf — sub-agents, background sessions, headless/SDK runs — rather
  than you steering a thread yourself. Higher is better. If it is near zero, you are
  working at rung ③/④, not ⑤.
- Read from `~/.claude/projects` on **this machine only**. Nothing is uploaded; no other
  person's data is visible or involved. If you use more than one machine, run it on each.
- Files are bucketed by last-modified time, so a session spanning a month boundary lands in
  the month it was last touched. Fine for a monthly trend; not exact.
- **How runs are classified.** Each transcript lands in exactly one bucket, checked in this
  order: `"isSidechain":true` → in-process sub-agent; `"sessionKind":"bg"` → background
  session; first `entrypoint` starting with `sdk-` (`sdk-py`, `sdk-cli`, … — headless
  `claude -p` and Agent SDK runs, e.g. loopd dispatches) → headless; anything else
  (`cli`, desktop, unknown) → interactive. The first three count as delegated. An SDK app
  you drive by hand would be miscounted as delegated; rare in practice.
- **No `Task`-dispatch counting.** Anything derived from counting `Task` dispatches in the
  parent transcript is unreliable — the dispatch is frequently recorded in the child's
  transcript instead, which undercounts the parent badly. The per-transcript markers above
  are what the local data records cleanly.
- This exists because the org dashboard's `delegated` figure does **not** count in-process
  sub-agent runs: one heavy user's machine showed 788 sub-agent runs in August while the
  whole organisation's reported figure for the same window was 287. This command measures
  the behaviour the dashboard cannot see.
