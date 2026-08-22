#!/usr/bin/env bash
#
# build-board.sh — render every instance's SNAPSHOT.json as ONE self-contained
# HTML page: instance → project → phase progress → a column per task status.
#
#   Usage:
#     scripts/build-board.sh [--out FILE] [--standalone] [INSTANCE_DIR ...]
#
#     INSTANCE_DIR ...  the instances to render. With none given, the list comes
#                       from `boardInstances` in ./instance.config.json; if that key
#                       is absent or empty, just this instance.
#     --out FILE        where to write (default: ./board.html)
#     --standalone      wrap the output in <!doctype html>/<head> for opening in a
#                       browser directly. OMIT for publishing (see OUTPUT SHAPE).
#
# DISCOVERY IS EXPLICIT, NEVER A GLOB. This file is symlinked into every instance,
# so it may not know where anybody's workspace lives — no `~/workspace/*`, no
# guessing at sibling directories. Either you name the instances or the instance's
# own config does, and an unnamed instance is simply not on the board.
#
# ABSENCE IS THE OFF SWITCH, ON BOTH SIDES. An instance with no SNAPSHOT.json does
# not appear — no placeholder, no warning card, nothing (the run says so on stderr,
# where it costs a human nothing). See write-snapshot.sh for why that is permanent.
#
# EVERYTHING FROM A SNAPSHOT IS UNTRUSTED TEXT. Titles, descriptions and URLs come
# from task documents: human-written, quoting tool output and PR metadata, and none
# of it authored here. This is the same boundary show-awaiting.sh keeps when it
# fences items before they enter session context (see its closing comment) — the
# difference is only the sink. Here the sink is an HTML page that gets published, so:
#   · every string is HTML-escaped, attribute values included, at the single point
#     where it is written into the page;
#   · a URL is rendered as a link ONLY if its scheme is http/https — a `javascript:`
#     or `data:` PR URL renders as inert text. The writer already restricts what it
#     collects; the board does not trust it to have done so;
#   · nothing from a snapshot ever reaches a <script>, a style, or an event handler.
# A malformed snapshot is a visible card, not a crash: a broken instance must not be
# able to blank the board for the others.
#
# WHY python3 AND NOT awk. Every other script here is bash + awk on purpose, so it
# ships into an instance unchanged. This one needs two things awk does badly and a
# board cannot be wrong about: parsing arbitrary JSON, and HTML-escaping. A
# hand-rolled JSON reader mis-handling a quote inside a title is exactly the bug that
# turns an untrusted title into markup on a published page. `json` and
# `html.escape(..., quote=True)` are the right primitives, they are in the standard
# library, and this is a human-run reporting step — not tick machinery a /pm-loop
# depends on. No npm, no pip, no new runtime.
#
# OUTPUT SHAPE. The default output is an **Artifact page body**: a <title>, an inline
# <style>, then content — no <!doctype>, <html>, <head> or <body> tags, because the
# publish step wraps the file in exactly those. Opening that file in a browser
# directly works but lands in quirks mode with no charset declared; use
# `--standalone` for a local look, and the plain file for publishing.
#
# Deterministic apart from the "rendered" line. No network. Verified by
# ai-bridge/tests/snapshot.test.sh.
set -euo pipefail

OUT="board.html"
STANDALONE=0
DIRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) shift; [[ $# -gt 0 ]] || { echo "build-board: --out needs a path" >&2; exit 2; }; OUT="$1" ;;
    --out=*) OUT="${1#--out=}" ;;
    --standalone) STANDALONE=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*) echo "build-board: unknown flag '$1'" >&2; exit 2 ;;
    *) DIRS+=("$1") ;;
  esac
  shift
done

command -v python3 >/dev/null 2>&1 || {
  echo "build-board: needs python3 (standard library only). See this script's header for why." >&2
  exit 2
}

BOARD_OUT="$OUT" BOARD_STANDALONE="$STANDALONE" python3 - "${DIRS[@]+"${DIRS[@]}"}" <<'PY'
import html, json, os, sys
from pathlib import Path

OUT = Path(os.environ["BOARD_OUT"])
STANDALONE = os.environ.get("BOARD_STANDALONE") == "1"

# Canonical column order — SCHEMA.md's Task enum. An unknown status still gets a
# column at the end rather than vanishing: a snapshot from a drifted instance should
# look wrong on the board, not be silently dropped from it.
COLUMNS = ["draft", "ready", "in-progress", "in-review", "blocked", "done", "cancelled"]
VERBS = {"approve": "✅", "answer": "❓", "merge": "🔀", "unblock": "⛔", "close": "🏁"}

def e(v):
    """The single escape point. Everything from a snapshot goes through here."""
    return html.escape("" if v is None else str(v), quote=True)

def href(url):
    """A link only for http/https. Anything else is inert text (see header)."""
    u = "" if url is None else str(url)
    return u if u.lower().startswith(("http://", "https://")) else ""

def resolve_dirs(argv):
    if argv:
        return [Path(a).expanduser() for a in argv], None
    cfg = Path("instance.config.json")
    if cfg.is_file():
        try:
            listed = json.loads(cfg.read_text(encoding="utf-8")).get("boardInstances") or []
        except (ValueError, OSError):
            listed = []
            print("build-board: instance.config.json is unreadable; falling back to this instance.", file=sys.stderr)
        if isinstance(listed, list) and listed:
            return [Path(str(p)).expanduser() for p in listed], "boardInstances"
    return [Path(".")], "this instance"

dirs, source = resolve_dirs(sys.argv[1:])

instances, broken = [], []
for d in dirs:
    snap = d / "SNAPSHOT.json"
    if not d.is_dir():
        print(f"build-board: skipped {d} — no such directory.", file=sys.stderr)
        continue
    if not snap.is_file():
        # The off switch. Absent from the board entirely, by design.
        print(f"build-board: skipped {d} — no SNAPSHOT.json (off the board).", file=sys.stderr)
        continue
    try:
        data = json.loads(snap.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError("top level is not an object")
    except (ValueError, OSError, UnicodeDecodeError) as exc:
        broken.append((str(d), type(exc).__name__ + ": " + str(exc)))
        print(f"build-board: {d}/SNAPSHOT.json is malformed — rendering a note.", file=sys.stderr)
        continue
    data["_dir"] = str(d)
    if not data.get("group"):
        data["group"] = d.name.removeprefix("_ai-bridge-") or str(d)
    instances.append(data)

def tolist(v):
    return v if isinstance(v, list) else []

def todict(v):
    return v if isinstance(v, dict) else {}

# ---------------------------------------------------------------- awaiting queue
awaiting = []
for inst in instances:
    for proj in tolist(inst.get("projects")):
        proj = todict(proj)
        if proj.get("awaiting_close"):
            awaiting.append({
                "verb": "close", "group": inst["group"], "project": proj.get("title") or proj.get("slug"),
                "what": "all tasks terminal", "detail": "/close-project " + str(proj.get("slug") or ""), "prs": [],
            })
        for task in tolist(proj.get("tasks")):
            task = todict(task)
            verb = task.get("awaiting")
            if verb in VERBS:
                awaiting.append({
                    "verb": verb, "group": inst["group"], "project": proj.get("title") or proj.get("slug"),
                    "what": task.get("title") or task.get("id"),
                    "detail": (f"{task.get('open_questions')} open question(s)" if verb == "answer" else ""),
                    "prs": tolist(task.get("prs")),
                })
ORDER = list(VERBS)
awaiting.sort(key=lambda a: (ORDER.index(a["verb"]), a["group"], str(a["project"])))

# ---------------------------------------------------------------- HTML
CSS = """
/* Full light palette on BARE :root, so no colour is ever defined only inside a
   media or [data-theme] block. Dark redefines these same tokens twice: once for
   the system preference (guarded so an explicit light choice wins) and once for an
   explicit dark choice. */
:root{
  --bg:#f6f7f9; --surface:#ffffff; --surface-2:#eef0f4; --border:#d7dbe2;
  --text:#12161c; --text-dim:#5b6472; --accent:#2f5fd0; --accent-soft:#e6edfb;
  --warn-bg:#fdf1e3; --warn-border:#e0a94a; --shadow:0 1px 2px rgba(16,22,32,.07);
  --draft:#8b7bd8; --ready:#2f8f5b; --in-progress:#c98a17; --in-review:#2f5fd0;
  --blocked:#c5443c; --done:#5b6472; --cancelled:#8a9099; --other:#8a9099;
}
:root:not([data-theme="light"]){}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --bg:#0f1216; --surface:#171b21; --surface-2:#1e242c; --border:#2c343e;
    --text:#e7ebf0; --text-dim:#98a2b0; --accent:#7aa2f7; --accent-soft:#1d2637;
    --warn-bg:#2a2115; --warn-border:#6b5220; --shadow:0 1px 2px rgba(0,0,0,.4);
    --draft:#a996f2; --ready:#5cc98c; --in-progress:#e3b04b; --in-review:#7aa2f7;
    --blocked:#f0776e; --done:#98a2b0; --cancelled:#78818d; --other:#78818d;
  }
}
:root[data-theme="dark"]{
  --bg:#0f1216; --surface:#171b21; --surface-2:#1e242c; --border:#2c343e;
  --text:#e7ebf0; --text-dim:#98a2b0; --accent:#7aa2f7; --accent-soft:#1d2637;
  --warn-bg:#2a2115; --warn-border:#6b5220; --shadow:0 1px 2px rgba(0,0,0,.4);
  --draft:#a996f2; --ready:#5cc98c; --in-progress:#e3b04b; --in-review:#7aa2f7;
  --blocked:#f0776e; --done:#98a2b0; --cancelled:#78818d; --other:#78818d;
}
*,*::before,*::after{box-sizing:border-box}
body{
  margin:0; padding:1rem .85rem 3rem;
  background:var(--bg); color:var(--text);
  font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  -webkit-text-size-adjust:100%; overflow-x:hidden;
}
img,svg{max-width:100%}
.wrap{max-width:78rem; margin:0 auto}
h1{font-size:1.35rem; margin:0 0 .2rem; letter-spacing:-.01em}
h2{font-size:1.05rem; margin:1.6rem 0 .6rem}
h3{font-size:.98rem; margin:0}
.sub{color:var(--text-dim); font-size:.82rem; margin:0 0 1.2rem}
a{color:var(--accent)}
.card{background:var(--surface); border:1px solid var(--border); border-radius:.7rem; box-shadow:var(--shadow)}
.pill{display:inline-block; padding:.08rem .45rem; border-radius:1rem; font-size:.7rem;
  font-weight:600; text-transform:uppercase; letter-spacing:.03em;
  background:var(--surface-2); color:var(--text-dim); white-space:nowrap}
.pill[data-s]{color:var(--surface)}
.pill[data-s="draft"]{background:var(--draft)} .pill[data-s="ready"]{background:var(--ready)}
.pill[data-s="in-progress"]{background:var(--in-progress)} .pill[data-s="in-review"]{background:var(--in-review)}
.pill[data-s="blocked"]{background:var(--blocked)} .pill[data-s="done"]{background:var(--done)}
.pill[data-s="cancelled"]{background:var(--cancelled)} .pill[data-s="other"]{background:var(--other)}

/* --- awaiting you: the one thing on this page that needs a decision --- */
.awaiting{border-left:.28rem solid var(--blocked); padding:.85rem .9rem; margin:0 0 1.4rem}
.awaiting h2{margin:0 0 .55rem; font-size:1rem}
.awaiting ul{list-style:none; margin:0; padding:0; display:grid; gap:.5rem}
.awaiting li{display:flex; flex-wrap:wrap; gap:.4rem .55rem; align-items:baseline;
  padding:.45rem .55rem; background:var(--surface-2); border-radius:.45rem; font-size:.9rem}
.awaiting .verb{font-weight:700; white-space:nowrap}
.awaiting .where{color:var(--text-dim); font-size:.78rem; width:100%}
.none{color:var(--text-dim); font-size:.9rem; margin:0}

/* --- instance tabs: CSS-only, so no script and full keyboard support --- */
.tabs>input{position:absolute; opacity:0; pointer-events:none; width:0; height:0}
.tablist{display:flex; flex-wrap:wrap; gap:.4rem; margin:0 0 1rem}
.tablist label{cursor:pointer; padding:.35rem .7rem; border:1px solid var(--border);
  border-radius:.5rem; background:var(--surface); font-size:.85rem; font-weight:600}
.tabs>input:focus-visible+.tablist label[data-first],
.tablist label:hover{border-color:var(--accent)}
.panel{display:none}
.tabs>input:checked{}

/* --- a project --- */
.project{padding:.85rem .9rem; margin:0 0 1rem}
.phead{display:flex; flex-wrap:wrap; gap:.4rem .6rem; align-items:baseline}
.pdesc{color:var(--text-dim); font-size:.85rem; margin:.35rem 0 0}
.progress{margin:.6rem 0 .2rem; font-size:.75rem; color:var(--text-dim)}
.bar{height:.4rem; border-radius:1rem; background:var(--surface-2); overflow:hidden; margin-top:.25rem}
.bar>span{display:block; height:100%; background:var(--accent)}
.phaselist{margin:.45rem 0 0; padding:0; list-style:none; display:flex; flex-wrap:wrap; gap:.3rem}
.phaselist li{font-size:.72rem; color:var(--text-dim); background:var(--surface-2);
  border-radius:.35rem; padding:.1rem .4rem}

/* --- the columns. Wide content scrolls INSIDE this strip; the body never does. --- */
.cols{display:flex; gap:.6rem; overflow-x:auto; padding:.7rem .1rem .3rem;
  scroll-snap-type:x proximity; -webkit-overflow-scrolling:touch}
.col{flex:0 0 15rem; min-width:15rem; scroll-snap-align:start;
  background:var(--surface-2); border-radius:.55rem; padding:.5rem}
@media (min-width:52rem){ .col{flex:1 1 0; min-width:11rem} }
.colhead{display:flex; justify-content:space-between; align-items:baseline;
  font-size:.74rem; font-weight:700; text-transform:uppercase; letter-spacing:.04em;
  color:var(--text-dim); margin:0 0 .45rem}
.task{background:var(--surface); border:1px solid var(--border); border-radius:.45rem;
  padding:.45rem .5rem; margin:0 0 .4rem; font-size:.85rem}
.task .t{overflow-wrap:anywhere}
.task .meta{display:flex; flex-wrap:wrap; gap:.3rem; align-items:center; margin-top:.35rem}
.task .flight{color:var(--in-progress); font-size:.7rem; font-weight:700}
.task .prs{display:flex; flex-wrap:wrap; gap:.25rem; margin-top:.3rem}
.task .prs a{font-size:.72rem; background:var(--accent-soft); color:var(--accent);
  border-radius:.3rem; padding:.05rem .35rem; text-decoration:none; white-space:nowrap}
.task .inert{font-size:.72rem; color:var(--text-dim); overflow-wrap:anywhere}
.empty{color:var(--text-dim); font-size:.78rem; padding:.2rem .1rem}

.note{background:var(--warn-bg); border:1px solid var(--warn-border); border-radius:.55rem;
  padding:.6rem .7rem; margin:0 0 .8rem; font-size:.85rem}
.note code{overflow-wrap:anywhere}
footer{color:var(--text-dim); font-size:.75rem; margin-top:2rem; border-top:1px solid var(--border); padding-top:.7rem}
table{border-collapse:collapse}
.scroll{overflow-x:auto}
"""

parts = []
w = parts.append

w("<title>Bridge Board</title>")
w('<meta name="viewport" content="width=device-width, initial-scale=1">')
w("<style>" + CSS)
# The tab rules are generated: one pair per instance, so the CSS-only tabs need no JS.
for i in range(len(instances)):
    w(f'.tabs>#tab-{i}:checked ~ #panel-{i}{{display:block}}')
    w(f'.tabs>#tab-{i}:checked ~ .tablist label[for="tab-{i}"]'
      '{background:var(--accent-soft); border-color:var(--accent); color:var(--accent)}')
w("</style>")

w('<div class="wrap">')
w("<h1>Bridge Board</h1>")
total_tasks = sum(int(todict(i.get("counts")).get("tasks") or 0) for i in instances)
w('<p class="sub">{} instance(s) · {} project(s) · {} task(s) · {} awaiting you</p>'.format(
    len(instances),
    sum(len(tolist(i.get("projects"))) for i in instances),
    total_tasks, len(awaiting)))

for d, msg in broken:
    w('<div class="note"><strong>Unreadable snapshot.</strong> '
      f'<code>{e(d)}/SNAPSHOT.json</code> could not be parsed, so that instance is not on '
      f'the board. Re-run <code>scripts/write-snapshot.sh</code> there. <br>{e(msg)}</div>')

# ---- awaiting you
w('<section class="card awaiting">')
w(f"<h2>🔴 Awaiting you ({len(awaiting)})</h2>")
if awaiting:
    w("<ul>")
    for a in awaiting:
        w("<li>")
        w(f'<span class="verb">{VERBS[a["verb"]]} {e(a["verb"])}</span>')
        w(f'<span>{e(a["what"])}</span>')
        for pr in tolist(a["prs"]):
            pr = todict(pr)
            u = href(pr.get("url"))
            label = f'{pr.get("repo")}#{pr.get("number")}'
            if u:
                w(f'<a href="{e(u)}" rel="noopener noreferrer" target="_blank">{e(label)}</a>')
            else:
                w(f'<span class="inert">{e(label)}</span>')
        tail = f' · {a["detail"]}' if a["detail"] else ""
        w(f'<span class="where">{e(a["group"])} › {e(a["project"])}{e(tail)}</span>')
        w("</li>")
    w("</ul>")
else:
    w('<p class="none">Nothing needs a decision right now.</p>')
w("</section>")

# ---- instances
if not instances:
    w('<div class="note">No instance on the board. An instance appears here once it has a '
      '<code>SNAPSHOT.json</code> — <code>touch SNAPSHOT.json</code> in it, then run '
      '<code>scripts/write-snapshot.sh</code>.</div>')
else:
    w('<div class="tabs">')
    for i in range(len(instances)):
        checked = " checked" if i == 0 else ""
        w(f'<input type="radio" name="board-instance" id="tab-{i}"{checked}>')
    w('<nav class="tablist">')
    for i, inst in enumerate(instances):
        n = len(tolist(inst.get("projects")))
        w(f'<label for="tab-{i}"{" data-first" if i == 0 else ""}>{e(inst["group"])} '
          f'<span class="pill">{n}</span></label>')
    w("</nav>")

    for i, inst in enumerate(instances):
        w(f'<section class="panel" id="panel-{i}">')
        w(f'<p class="sub">snapshot generated {e(inst.get("generated_at") or "unknown")} · '
          f'<code>{e(inst.get("_dir"))}</code></p>')
        projects = [todict(p) for p in tolist(inst.get("projects"))]
        if not projects:
            w('<p class="none">No projects in this instance yet.</p>')
        for proj in projects:
            w('<article class="card project">')
            w('<div class="phead">')
            w(f'<h3>{e(proj.get("title") or proj.get("slug"))}</h3>')
            st = proj.get("status") or "other"
            w(f'<span class="pill" data-s="{e(st if st in COLUMNS or st in ("active","paused","done") else "other")}">{e(st)}</span>')
            w(f'<span class="pill">{e(proj.get("kind") or "build")}</span>')
            if (proj.get("autonomy") or "gated") != "gated":
                w(f'<span class="pill" data-s="blocked">autonomy: {e(proj.get("autonomy"))}</span>')
            if proj.get("awaiting_close"):
                w('<span class="pill" data-s="ready">🏁 close?</span>')
            w("</div>")
            if proj.get("description"):
                w(f'<p class="pdesc">{e(proj.get("description"))}</p>')

            prog = todict(proj.get("phase_progress"))
            ptot = int(prog.get("total") or 0)
            pdone = int(prog.get("done") or 0)
            if ptot:
                pct = max(0, min(100, round(100 * pdone / ptot)))
                w(f'<div class="progress">Phases {pdone}/{ptot} done'
                  f'<div class="bar"><span style="width:{pct}%"></span></div></div>')
                w('<ul class="phaselist">')
                for ph in sorted((todict(p) for p in tolist(proj.get("phases"))),
                                 key=lambda p: (int(p.get("order") or 0), str(p.get("title") or ""))):
                    w(f'<li>{e(ph.get("order"))}. {e(ph.get("title"))} — {e(ph.get("status"))}</li>')
                w("</ul>")

            tasks = [todict(t) for t in tolist(proj.get("tasks"))]
            if not tasks:
                w('<p class="empty">No tasks yet.</p>')
            else:
                buckets = {c: [] for c in COLUMNS}
                for t in tasks:
                    buckets.setdefault(t.get("status") or "other", []).append(t)
                order = COLUMNS + [k for k in buckets if k not in COLUMNS]
                w('<div class="cols">')
                for col in order:
                    items = buckets.get(col) or []
                    w('<div class="col">')
                    label = col if col in COLUMNS else (col or "unknown")
                    w(f'<div class="colhead"><span>{e(label)}</span><span>{len(items)}</span></div>')
                    if not items:
                        w('<div class="empty">—</div>')
                    for t in items:
                        w('<div class="task">')
                        w(f'<div class="t">{e(t.get("title") or t.get("id"))}</div>')
                        w('<div class="meta">')
                        w(f'<span class="pill">{e(t.get("id"))}</span>')
                        if t.get("assignee"):
                            w(f'<span class="pill">{e(t.get("assignee"))}</span>')
                        if t.get("in_flight"):
                            w('<span class="flight">● in flight</span>')
                        if t.get("awaiting") in VERBS:
                            w(f'<span class="pill" data-s="blocked">{VERBS[t["awaiting"]]} {e(t["awaiting"])}</span>')
                        oq = t.get("open_questions") or 0
                        if isinstance(oq, int) and oq > 0:
                            w(f'<span class="pill">{oq} question(s)</span>')
                        w("</div>")
                        prs = [todict(p) for p in tolist(t.get("prs"))]
                        if prs:
                            w('<div class="prs">')
                            for pr in prs:
                                u = href(pr.get("url"))
                                label = f'{pr.get("repo")}#{pr.get("number")}'
                                if u:
                                    w(f'<a href="{e(u)}" rel="noopener noreferrer" target="_blank">{e(label)}</a>')
                                else:
                                    w(f'<span class="inert">{e(label)} (link withheld: not http/https)</span>')
                            w("</div>")
                        w("</div>")
                    w("</div>")
                w("</div>")
            w("</article>")
        w("</section>")
    w("</div>")

w("<footer>Generated by <code>scripts/build-board.sh</code> from each instance's "
  "<code>SNAPSHOT.json</code>. Derived, read-only, and <strong>as sensitive as the task "
  "documents it comes from</strong> — every title here is human-written free text. "
  f"Instances listed from: {e(source or 'command line')}.</footer>")
w("</div>")

body = "\n".join(parts) + "\n"
if STANDALONE:
    body = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
            + body + "</head>\n<body></body>\n</html>\n")
OUT.write_text(body, encoding="utf-8")
print(f"build-board: wrote {OUT} — {len(instances)} instance(s), {len(awaiting)} awaiting, "
      f"{len(broken)} unreadable snapshot(s).")
PY
