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
ok "a terminal-matched theme sets all 71 tokens as #rrggbb" "$(js '
  const { themeFromTerminal, FALLBACK_TERMINAL } = await import(process.argv[1] + "/tokens.mjs");
  const o = themeFromTerminal("t", FALLBACK_TERMINAL).overrides;
  console.log(Object.keys(o).length + ":" + Object.values(o).every((v) => /^#[0-9a-f]{6}$/.test(v)));')" "71:true"
ok "ansi values resolve through the terminal palette" "$(js '
  const { toHex } = await import(process.argv[1] + "/tokens.mjs");
  const term = { palette: Array.from({ length: 16 }, (_, i) => "#0000" + i.toString(16).padStart(2, "0")) };
  console.log([toHex("ansi:cyanBright", term), toHex("ansi256(3)", term), toHex("ansi256(196)", term), toHex("ansi256(244)", term)].join(" "));')" \
   "#00000e #000003 #ff0000 #808080"

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

echo "== 7. the per-machine palette cache stays out of git =="
ok "terminal-palette.local.json is ignored" \
   "$(git -C "$REPO" check-ignore -q themes/preview-app/terminal-palette.local.json && echo yes || echo no)" yes

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
