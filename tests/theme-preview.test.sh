#!/usr/bin/env bash
#
# theme-preview.test.sh — the theme files under themes/ are ones Claude Code will accept,
# and the preview app's local server only ever touches themes/*.json.
#
# WHY. Claude Code IGNORES an unknown token or an invalid colour instead of erroring, so a
# broken theme file looks fine until you notice the colour never changed. The shape checks
# here reuse the app's own validator (a copy of the CLI's), so the app and this test cannot
# disagree about what "valid" means. The server writes files, so its guards — slug
# allowlist, Host and Origin checks — are asserted against a live instance, not read off
# the source.
#
# ok() compares actual to expected, per this directory's convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO/themes/preview-app"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
command -v curl >/dev/null 2>&1 || { echo "SKIP: curl not installed"; exit 0; }

[ -n "${KEEP_TMP:-}" ] && trap - EXIT
TMP="$(mktemp -d "${TMPDIR:-/tmp}/theme-preview.XXXXXX")" || {
  echo "theme-preview.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
SRV_PID=""
trap '[ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

js() { node --input-type=module -e "$1" "$APP" "${@:2}" 2>&1; }

echo "== 1. token metadata and base presets agree =="
ok "every preset key has metadata, and nothing extra" "$(js '
  const { TOKENS, PRESETS } = await import(process.argv[1] + "/tokens.mjs");
  const p = Object.keys(PRESETS.dark), t = Object.keys(TOKENS);
  console.log([...p.filter((k) => !t.includes(k)), ...t.filter((k) => !p.includes(k))].join(" ") || "none");')" none
ok "all six presets carry the same token set" "$(js '
  const { PRESETS } = await import(process.argv[1] + "/tokens.mjs");
  const ref = Object.keys(PRESETS.dark).sort().join();
  console.log(Object.entries(PRESETS).filter(([, v]) => Object.keys(v).sort().join() !== ref).map(([k]) => k).join(" ") || "none");')" none

echo "== 2. the validator matches Claude Code's accepted notations =="
ok "accepts #rgb #rrggbb rgb() ansi256() ansi:<name>" "$(js '
  const { isValidColor } = await import(process.argv[1] + "/tokens.mjs");
  console.log(["#abc", "#AABBCC", "rgb(1,2,3)", "rgb( 1, 2, 3 )", "ansi256(208)", "ansi:cyanBright"].every(isValidColor));')" true
ok "rejects #rgba, names, unknown ansi, bare numbers" "$(js '
  const { isValidColor } = await import(process.argv[1] + "/tokens.mjs");
  console.log(["#abcd", "blue", "ansi:purple", "208", "", null].filter(isValidColor).length);')" 0

echo "== 3. every theme file under themes/ is one Claude Code accepts =="
n_themes=0
for f in "$REPO"/themes/*.json; do
  [ -f "$f" ] || continue
  n_themes=$((n_themes+1))
  ok "$(basename "$f"): parses, legal base, known tokens, valid values" "$(js '
    const { resolveTheme, FALLBACK_TERMINAL } = await import(process.argv[1] + "/tokens.mjs");
    const t = JSON.parse((await import("node:fs")).readFileSync(process.argv[2], "utf8"));
    const r = resolveTheme(t, FALLBACK_TERMINAL);
    console.log(r.issues.map((i) => i.key + ":" + i.level).join(" ") || "clean");' "$f")" clean
done
ok "at least one theme ships as an example" "$([ "$n_themes" -ge 1 ] && echo yes || echo no)" yes

echo "== 4. generated themes are full and portable =="
ok "a terminal-matched theme sets all 72 tokens as #rrggbb" "$(js '
  const { themeFromTerminal, FALLBACK_TERMINAL } = await import(process.argv[1] + "/tokens.mjs");
  const o = themeFromTerminal("t", FALLBACK_TERMINAL).overrides;
  console.log(Object.keys(o).length + ":" + Object.values(o).every((v) => /^#[0-9a-f]{6}$/.test(v)));')" "72:true"
ok "ansi values resolve through the terminal palette" "$(js '
  const { toHex } = await import(process.argv[1] + "/tokens.mjs");
  const term = { palette: Array.from({ length: 16 }, (_, i) => "#0000" + i.toString(16).padStart(2, "0")) };
  console.log([toHex("ansi:cyanBright", term), toHex("ansi256(3)", term), toHex("ansi256(196)", term), toHex("ansi256(244)", term)].join(" "));')" \
   "#00000e #000003 #ff0000 #808080"

echo "== 4b. the preview names only real tokens and explained non-theme parts =="
ok "every token the preview paints exists in TOKENS" "$(js '
  const fs = await import("node:fs");
  const { TOKENS } = await import(process.argv[1] + "/tokens.mjs");
  const src = fs.readFileSync(process.argv[1] + "/app.mjs", "utf8");
  const used = new Set();
  for (const m of src.matchAll(/\b(?:fg|bg|shim|rowBg|box|rule|dot)\(\x27([A-Za-z_]+)\x27(?:,\s*\x27([A-Za-z_]+)\x27)?/g)) { used.add(m[1]); if (m[2] && TOKENS[m[2]]) used.add(m[2]); }
  console.log([...used].filter((t) => !TOKENS[t]).join(" ") || "none");')" none
ok "every non-theme part (data-nt) has an inspector note" "$(js '
  const fs = await import("node:fs");
  const src = fs.readFileSync(process.argv[1] + "/app.mjs", "utf8");
  const block = /const NON_THEME = \{([\s\S]*?)\n\};/.exec(src)[1];
  const known = new Set([...block.matchAll(/^\s+([a-z]+):/gm)].map((m) => m[1]));
  const used = new Set([...src.matchAll(/\bnt\(\x27([a-z]+)\x27/g)].map((m) => m[1]));
  for (const k of ["dim", "plain", "link"]) used.add(k);
  console.log([...used].filter((k) => !known.has(k)).join(" ") || "none");')" none

echo "== 5. terminal replies (OSC 10/11/4) parse in both terminator styles =="
ok "fg (ST, 4-digit), bg (BEL, 2-digit), palette index" "$(js '
  const { parseReplies } = await import(process.argv[1] + "/server.mjs");
  const r = parseReplies("\x1b]10;rgb:ffff/8080/0000\x1b\\\\" + "\x1b]11;rgb:10/20/30\x07" + "\x1b]4;9;rgb:ff/00/00\x07");
  console.log([r.foreground, r.background, r.palette[9]].join(" "));')" "#ff8000 #102030 #ff0000"

echo "== 6. the server only reads and writes themes/*.json, only for this origin =="
PORT="$(node -e 'const s=require("net").createServer();s.listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})')"
mkdir -p "$TMP/themes"
printf '{"name":"Seed"}\n' > "$TMP/themes/seed.json"
printf 'secret\n' > "$TMP/outside.json"
# TERMINAL_CACHE points away from the real per-machine cache, or a palette detected on
# this machine would leak into the "no terminal" assertion below.
THEMES_DIR="$TMP/themes" TERMINAL_CACHE="$TMP/no-cache.json" node "$APP/server.mjs" --no-detect --port "$PORT" > "$TMP/server.log" 2>&1 &
SRV_PID=$!
disown "$SRV_PID" 2>/dev/null || true   # no "Terminated" notice when the trap kills it
B="http://127.0.0.1:$PORT"
for _ in $(seq 1 50); do curl -s -o /dev/null "$B/api/themes" && break; sleep 0.1; done
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
ok "lists the theme files"              "$(curl -s "$B/api/themes")" '[{"slug":"seed","name":"Seed"}]'
ok "serves the page"                    "$(code "$B/")" 200
ok "does not serve its own source"      "$(code "$B/server.mjs")" 404
ok "…nor the live-preview host"         "$(code "$B/pty-host.py")$(code "$B/live.mjs")" 404404
ok "a slug with a dot is refused"       "$(code -X PUT --data '{}' "$B/api/themes/a.b")" 400
ok "an encoded ../ never reaches the fs" "$(code "$B/api/themes/..%2Foutside")" 404
ok "invalid JSON is refused"            "$(code -X PUT --data '{nope' "$B/api/themes/x")" 400
ok "a JSON array is refused"            "$(code -X PUT --data '[]' "$B/api/themes/x")" 400
ok "a cross-origin write is refused"    "$(code -X PUT -H 'Origin: https://evil.example' --data '{}' "$B/api/themes/x")" 403
ok "a rebound Host is refused"          "$(code -H "Host: evil.example:$PORT" "$B/api/themes")" 403
ok "create-only write succeeds once"    "$(code -X PUT -H 'If-None-Match: *' --data '{"name":"X"}' "$B/api/themes/x")" 200
ok "…and refuses to overwrite"          "$(code -X PUT -H 'If-None-Match: *' --data '{"name":"Y"}' "$B/api/themes/x")" 409
ok "the write landed in themes/"        "$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).name)' "$TMP/themes/x.json")" X
ok "nothing was written outside themes/" "$(cat "$TMP/outside.json")" secret
ok "no terminal → no palette served"    "$(curl -s "$B/api/terminal")" '{}'

echo "== 7. live preview: nothing but terminal replies and named keys reach the PTY =="
ok "Enter in every encoding, typed keys, clicks, ^C are dropped" "$(js '
  const { filterReplies } = await import(process.argv[1] + "/live.mjs");
  const bad = ["\r", "\n", "a\r", "\x1b[13u", "\x1b[13;2u", "\x1bOM", "hello", "\x1b[A", "\x1b[<0;3;4M", "\x03", "\x1b[200~x\r\x1b[201~"];
  console.log(JSON.stringify(bad.map(filterReplies).join("")));')" '""'
ok "query replies and wheel reports pass, Enter around them does not" "$(js '
  const { filterReplies } = await import(process.argv[1] + "/live.mjs");
  console.log(JSON.stringify(filterReplies("\r\x1b[?1;2c\nx\x1b[13;5R\x1b[<64;3;4M\x1b]11;rgb:1c1c/1e1e/2626\x1b\\\\")));')" \
   '"\u001b[?1;2c\u001b[13;5R\u001b[<64;3;4M\u001b]11;rgb:1c1c/1e1e/2626\u001b\\"'
ok "no named key is an Enter" "$(js '
  const { KEYS, ENTER } = await import(process.argv[1] + "/live.mjs");
  console.log(Object.entries(KEYS).filter(([, v]) => ENTER.test(v)).map(([k]) => k).join(" ") || "none");')" none

# A stand-in claude: records the raw bytes its terminal delivers, so the assertions below see
# exactly what reached the PTY. The real claude is used instead when it is installed.
PY="$(command -v /usr/bin/python3 || command -v python3)"
if [ -z "$PY" ]; then echo "  SKIP  live preview: python3 not installed"; else
mkdir -p "$TMP/tmpdir" "$TMP/fake"
FAKE="$TMP/fake/claude"
cat > "$FAKE" <<EOF
#!$PY
import os, sys, termios, tty
tty.setraw(0, termios.TCSANOW)  # NOW, not FLUSH: keep bytes that arrived early
open("$TMP/fake/argv", "w").write("\n".join(sys.argv[1:]))
os.write(1, b"FAKE CLAUDE READY\r\n")
with open("$TMP/fake/input", "ab") as f:
    while True:
        d = os.read(0, 1024)
        if not d: break
        f.write(d); f.flush()
EOF
chmod +x "$FAKE"

ok "the PTY host refuses Enter even when handed one" "$(
  { printf '{"w":"%s"}\n' "$(printf 'a\rb' | base64)" "$(printf '/' | base64)"; sleep 1; } \
    | "$PY" -I "$APP/pty-host.py" 80 24 -- "$FAKE" >/dev/null 2>&1; od -An -c "$TMP/fake/input" | tr -d ' ')" /
rm -f "$TMP/fake/input"

start_live() { # $1 = CLAUDE_BIN for the server (empty = the claude on PATH)
  PORT2="$(node -e 'const s=require("net").createServer();s.listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})')"
  L="http://127.0.0.1:$PORT2"
  env -u CLAUDE_CONFIG_DIR ${1:+CLAUDE_BIN="$1"} HOME="$TMP/home" TMPDIR="$TMP/tmpdir" THEMES_DIR="$TMP/themes" TERMINAL_CACHE="$TMP/no-cache.json" \
    node "$APP/server.mjs" --no-detect --port "$PORT2" > "$TMP/live.log" 2>&1 &
  LIVE_PID=$!
  disown "$LIVE_PID" 2>/dev/null || true
  for _ in $(seq 1 50); do curl -s -o /dev/null "$L/api/themes" && break; sleep 0.1; done
}
ID=0b0e5c1a-7d6e-4c55-9a1f-1234567890ab
post() { curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data "$2" "$L/api/live/$1"; }

start_live "$TMP/fake/none"
ok "no claude: the page is told why (and shows the mock)" "$(curl -s "$L/api/live/config" | node -pe 'JSON.parse(require("fs").readFileSync(0)).unavailable')" "claude not found on PATH"
ok "…and a start is refused"            "$(post "$ID" '{"start":true,"cols":80,"rows":24}')" 503
kill "$LIVE_PID"; wait "$LIVE_PID" 2>/dev/null

# HOME is a stand-in too: other Claude sessions on this machine write the real ~/.claude.json
# all the time, so only a private HOME can show that the preview itself writes nothing there.
mkdir -p "$TMP/home/.claude"
cat > "$TMP/home/.claude/settings.json" <<'EOF'
{"statusLine":{"type":"command","command":"\"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/sl.sh"}}
EOF
printf '{"hasCompletedOnboarding":true}\n' > "$TMP/home/.claude.json"
REAL=""; [ -z "${THEME_PREVIEW_STAND_IN:-}" ] && command -v claude >/dev/null 2>&1 && REAL=yes
snap() { for f in "$TMP/home/.claude/settings.json" "$TMP/home/.claude.json"; do [ -f "$f" ] && { stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f"; cksum < "$f"; }; done; }
BEFORE="$(snap)"
start_live "$([ -n "$REAL" ] || echo "$FAKE")"
ok "a cross-origin page cannot start claude" "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Origin: https://evil.example' --data '{"start":true,"cols":80,"rows":24}' "$L/api/live/$ID")" 403
ok "a malformed session id is refused"  "$(post not-a-uuid '{"start":true,"cols":80,"rows":24}')" 400
ok "an unknown session has no stream"   "$(code "$L/api/live/$ID/stream")" 404
ok "start ($([ -n "$REAL" ] && echo real || echo stand-in) claude)" "$(post "$ID" '{"start":true,"cols":100,"rows":30,"mode":"plan","theme":{"name":"t","base":"dark"}}')" 200
curl -s -N --max-time 8 "$L/api/live/$ID/stream" > "$TMP/stream.txt" &
STREAM_PID=$!
sleep 4
read -ra HOSTS <<< "$(pgrep -P "$LIVE_PID" | tr '\n' ' ')"
read -ra KIDS <<< "$(for h in "${HOSTS[@]}"; do pgrep -P "$h"; done | tr '\n' ' ')"
ok "one PTY host and one claude are running" "${#HOSTS[@]}:${#KIDS[@]}" 1:1
if [ -n "$REAL" ] && command -v lsof >/dev/null 2>&1; then
  ok "claude has no network socket open" "$(for p in "${KIDS[@]}"; do lsof -nP -a -i -p "$p" 2>/dev/null | tail -n +2; done | wc -l | tr -d ' ')" 0
fi
BODY='{"replies":"x\r\n\u001b[13u\u001b[?1;2c","menu":true}'   # JSON escapes: CR, LF, kitty Enter, DA1
ok "Enter and typed text sent as replies never arrive" "$(post "$ID" "$BODY")" 200
ok "the stream carries the terminal output" "$(grep -c '^event: out' "$TMP/stream.txt" | awk '{print ($1>0)?"yes":"no"}')" yes
if [ -z "$REAL" ]; then
  sleep 1
  ok "…the stand-in got only the menu's / and the DA1 reply" "$(od -An -c "$TMP/fake/input" | tr -d ' \n')" '/033[?1;2c'
  ok "…and was started on the temp theme and the plan mode" "$(grep -c -e '"theme":"custom:preview"' -e '^plan$' "$TMP/fake/argv")" 2
  ok "…with your statusLine, pointed at your real config dir" "$(grep -c -F "$(basename "$TMP")/home/.claude\\\"/sl.sh" "$TMP/fake/argv")" 1
fi
roots() { find "$TMP/tmpdir" -mindepth 1 -maxdepth 1 -name 'claude-theme-preview-*' | wc -l | tr -d ' '; }
ok "the session lives in a temp config dir"  "$(roots)" 1
kill "$LIVE_PID"; wait "$LIVE_PID" 2>/dev/null; wait "$STREAM_PID" 2>/dev/null
sleep 1
ok "server exit ends the host and claude (no strays)" "$(for p in "${HOSTS[@]}" "${KIDS[@]}"; do kill -0 "$p" 2>/dev/null && echo "$p"; done | tr '\n' ' ')" ""
ok "server exit removes the temp dirs"   "$(roots)" 0
ok "\$HOME/.claude/settings.json and \$HOME/.claude.json untouched" "$([ "$(snap)" = "$BEFORE" ] && echo same || echo changed)" same
fi

echo "== 8. the per-machine palette cache stays out of git =="
ok "terminal-palette.local.json is ignored" \
   "$(git -C "$REPO" check-ignore -q themes/preview-app/terminal-palette.local.json && echo yes || echo no)" yes

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
