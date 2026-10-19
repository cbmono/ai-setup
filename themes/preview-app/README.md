# Claude Code theme preview

A local tool for designing [Claude Code custom themes](https://code.claude.com/docs/en/terminal-config#create-a-custom-theme).
The preview pane is **the real Claude Code**, running on a synthetic session and drawn by
xterm.js with your terminal's palette and font, next to the theme JSON. Every valid edit
repaints it, and clicking a cell jumps to the JSON value that colors it.

It is standalone: no npm dependencies, no build step, and nothing tied to loopd or any other
plugin. The theme files it writes are plain Claude Code theme files, so they work in any setup.

## How the live preview works

1. The server starts `claude --resume <id>` inside a PTY (`pty-host.py`, Python stdlib only), with
   a clean environment and a throwaway `CLAUDE_CONFIG_DIR` in the system temp dir. The session it
   resumes is `fixture.mjs`: a made-up control-panel exchange (table, `Needs you:` list, inline
   code, a link, Read/Update with a diff, a failing command, a subagent, `!` commands).
   Nothing in it comes from a real session.
2. Your theme JSON is written to `<temp>/themes/preview.json` and selected with
   `--settings '{"theme":"custom:preview"}'`. Claude Code watches that file, so each edit repaints
   the running session in well under a second.
3. The bytes stream to the page over Server-Sent Events. xterm.js draws them and answers the
   terminal queries Claude Code sends (device attributes, colors). The page posts those replies back.
4. Your `statusLine` is read from `~/.claude/settings.json` (never written) and passed through
   `--settings`, so the real status line renders.
5. Font, weight, line height, cursor and minimum contrast come from Orca's settings when Orca is
   installed (its profile database, opened read-only). Colors come from the terminal palette below.

The mode buttons restart claude with `--permission-mode` (`default` is `manual`); **bash**
types `!` into the empty prompt, and **slash menu** types `/` (unticking sends a backspace).
Without `python3` or `claude` on `PATH` (or if xterm.js cannot load), a banner says why and the
hand-drawn mock is shown instead.

### Safety

- **The prompt is never submitted.** The page can only send named keys (`!`, `/`, backspace, Esc,
  shift+tab) and xterm.js's replies to terminal queries plus mouse-wheel reports. Everything else
  it forwards (typed keys, clicks, paste) is dropped. Enter in every encoding (CR, LF, kitty
  `CSI 13 u`, keypad `ESC O M`) is refused by the server and again by the PTY host.
- **Nothing under `~/.claude` is written.** claude runs on a temp config dir, so it uses a separate
  keychain entry and never reads your credentials. It makes no API calls: resuming a session
  sends nothing, and nonessential traffic is off.
- **Nothing outlives the server.** There is one claude per browser tab. It is killed when the tab
  disconnects or after 30 minutes idle. On exit the server kills every claude and deletes the temp dirs.

## Run it

```bash
node themes/preview-app/server.mjs        # → http://127.0.0.1:4477
```

Requires Node 18+, `python3` (macOS ships `/usr/bin/python3`) and `claude` on `PATH`; Orca is
optional. **Start it from the terminal you run Claude Code in** (not through `!` inside
Claude Code), because the server asks that terminal for its colors when it starts.

| Option | Default | What it does |
| --- | --- | --- |
| `--port <n>` / `PORT` | `4477` | Port to listen on (always `127.0.0.1`) |
| `--no-detect` | off | Skip asking the terminal; use the cached or fallback palette |
| `THEMES_DIR` | `themes/` (the parent dir) | Where theme files are listed, read and written |
| `TERMINAL_CACHE` | `terminal-palette.local.json` here | Where the detected palette is cached |

## Terminal colors

On start the server sends OSC 10/11/4 queries (text color, background, and the 16 ANSI colors)
followed by a DA1 request. Terminals answer in order, so the DA1 reply means every color reply
has arrived; there is no fixed wait. Inside tmux the queries are wrapped for passthrough, which
needs `set -g allow-passthrough on`.

Where the palette comes from, in order:

1. **Detected** from the terminal on this start, then written to the cache.
2. **Cached** from the last successful detection, when there is no TTY or no answer.
3. **Fallback**: xterm defaults, in dark and light variants.

The **Terminal** dropdown in the toolbar switches between them. The palette matters beyond the
background: `ansi:<name>` and `ansi256(n)` values resolve through it, as they do in the real CLI.
The cache is per machine and gitignored.

## Using it

1. **Pick or create a theme.** The **Theme** dropdown lists `themes/*.json`. **New…** creates a
   file from a base preset, from the current file, or from **Match my terminal**. New files list
   **every** token (72), pre-filled, so the JSON doubles as the full menu of options.
2. **Edit the JSON.** Valid changes repaint the preview immediately. Invalid colors fall back to
   the base preset and get a red mark; unknown tokens get a yellow one. That matches Claude Code,
   which ignores both silently. Broken JSON keeps the last valid preview until you fix it. Click a
   gutter swatch for a color picker. **⌘S / Ctrl+S** saves.
3. **Inspect.** Hover a cell to see its exact text and background color and the token(s) that
   produce it in the resolved theme (base preset plus your overrides). Click to select that value
   in the JSON; if the file doesn't set the token yet, it is added with its current value. When
   several tokens share the color, all are listed and the click picks the first. Some cells are
   not theme-colored, and the inspector says so: body text and code-block syntax use your
   terminal's foreground and ANSI colors, and links use ANSI blue. Measured on 2.1.303: inline code
   uses the **base preset's** `permission` (`#b1b9f9` on dark), not your override, and the mascot
   stays orange whatever `claude` is.
4. **Switch views.** The mode buttons (default, plan, accept edits, auto, bash) and the
   **slash menu** checkbox show the parts of the UI that only appear in those states. A token
   whose gutter swatch is faded isn't drawn in the current view.
5. **Export.** **Export…** produces a portable file: only tokens that differ from the base,
   documented tokens only, values as `#rrggbb`. That is the strictest shape any loader accepts.
   Copy or download it.

**Match my terminal** takes Claude Code's own `dark-ansi` / `light-ansi` preset (picked from your
background's brightness) and resolves it through your palette. Backgrounds such as diff lines and
message blocks are blended into the terminal background, so they stay readable.

## Theme file format

```json
{
  "name": "Midnight",
  "base": "dark",
  "overrides": {
    "claude": "#a78bfa",
    "diffAdded": "#14532d"
  }
}
```

- `base`: `dark`, `light`, `dark-daltonized`, `light-daltonized`, `dark-ansi` or `light-ansi`.
  Defaults to `dark`.
- Values: `#rrggbb`, `#rgb`, `rgb(r,g,b)`, `ansi256(n)` or `ansi:<name>` (one of the 16 ANSI
  names, such as `red` or `cyanBright`).
- Tokens you don't set fall through to the base preset.

To use a theme in Claude Code, copy or symlink it to `~/.claude/themes/<slug>.json`, then pick
`custom:<slug>` in `/theme`. Claude Code watches that folder, so a symlinked file updates a
running session every time you save here. That is the quickest way to check the preview against
the real thing. A plugin can also ship the file in its themes directory.

## Files

| File | What it is |
| --- | --- |
| `server.mjs` | Local server: terminal detection, static files, `GET/PUT /api/themes/<slug>`, `/api/live/*` |
| `live.mjs` | Live sessions: temp config, spawn, key and reply filter, cleanup; Orca settings |
| `pty-host.py` | The PTY: spawns claude, relays bytes, resizes, refuses Enter |
| `fixture.mjs` | The synthetic session claude resumes |
| `term.mjs` | The page side: xterm.js, resize, the cell inspector |
| `index.html`, `style.css` | The page (xterm.js 6.0.0 from jsDelivr) |
| `app.mjs` | JSON editor, dialogs, and the mock preview used as the fallback |
| `tokens.mjs` | Token descriptions, the color validator, color resolution, theme generators. Shared with the tests |
| `presets.mjs` | The six base presets, extracted from the Claude Code binary |

The server binds to `127.0.0.1` and refuses requests with a foreign `Host` (DNS rebinding) or
`Origin` (another tab). It serves only the files listed above, and writes only
`<THEMES_DIR>/<slug>.json` for slugs matching `[A-Za-z0-9][A-Za-z0-9_-]*`. Starting a live session
is a `POST`, so the Origin check also keeps other sites from spawning claude.

## Limitations

- **xterm.js is not Orca's renderer.** The page uses xterm.js 6.0.0 with its DOM renderer; Orca
  ships a 6.1 beta with WebGL. Glyph rasterization and box-drawing joins can differ by a pixel.
- **The header is the temp config's.** It shows a temp path and `API Usage Billing`, because the
  temp config dir is not signed in.
- **One fixed session.** Permission dialogs, spinners and other in-flight UI need a live turn, which
  would mean an API call; they are not shown. The mock (the fallback) still draws them, laid out
  by hand.
- **Undocumented tokens.** Ten tokens (`skill`, `autoAcceptShimmer`, `chromeYellow`, …) are accepted by
  the CLI but not in the docs. Their descriptions and their places in the preview are inferred
  from their names, and Export leaves them out by default.

## Updating the base presets

`presets.mjs` is a verbatim copy of the preset objects inside the Claude Code binary (2.1.303
when last regenerated). When a release adds or recolors tokens, regenerate it rather than editing
it by hand:

1. Dump the binary's strings: `strings -n 6 "$(readlink -f "$(which claude)")" > /tmp/cc.txt`.
2. Find the line holding the preset literals: they start `={autoAccept:"rgb(` or
   `={autoAccept:"ansi:`, next to a function that ends
   `switch(r){case"light":return …;default:return …}`. That switch maps each preset name to its
   (minified) variable.
3. Convert each object to JSON and write the six into `presets.mjs` under their preset names.
4. Add any new token to `TOKENS` in `tokens.mjs`, then run the test below. It fails when the
   presets and `TOKENS` disagree.

## Tests

```bash
bash tests/theme-preview.test.sh
```

The test checks that every `themes/*.json` is a file Claude Code accepts, that the validator and
color resolution match the CLI, that terminal replies parse, and that the server's write guards
hold against a live instance. For the live preview it checks the key and reply filter, that the PTY host refuses
Enter, and runs a session end to end against a private `HOME`: the real claude when it is
installed, otherwise a stand-in that records every byte it receives (`THEME_PREVIEW_STAND_IN=1`
forces the stand-in). It then asserts that server exit leaves no process and no temp dir behind,
and that `$HOME/.claude/settings.json` and `$HOME/.claude.json` are unchanged.
