# Claude Code theme preview

A local tool for designing [Claude Code custom themes](https://code.claude.com/docs/en/terminal-config#create-a-custom-theme).
A mock Claude Code session renders in your terminal's colors next to the theme JSON. Every
valid edit repaints the preview, and clicking any part of the preview jumps to the JSON value
that colors it.

It is standalone: no dependencies, no build step, and nothing tied to loopd or any other
plugin. The theme files it writes are plain Claude Code theme files, so they work in any setup.

## Run it

```bash
node themes/preview-app/server.mjs        # → http://127.0.0.1:4477
```

Requires Node 18+. **Start it from the terminal you run Claude Code in** (not through `!` inside
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
3. **Inspect.** Hover the preview to see the token that paints an element, its value, and whether
   it comes from your file or the base preset. Click to select that value in the JSON; ⌥-click
   picks the lighter "shimmer" partner some tokens have. If the file doesn't set the token yet, it
   is added with its current value. Moving the cursor onto a token line outlines everything that
   token paints. Some parts have no theme token: dimmed hints, the `❯` in the input, links, table
   borders and your statusLine output. Claude Code draws them in dim text, the terminal
   foreground or your ANSI palette. Hovering one says so, and clicking it does nothing.
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
| `server.mjs` | Local server: terminal detection, static files, `GET/PUT /api/themes/<slug>` |
| `index.html`, `style.css` | The page |
| `app.mjs` | Preview markup, JSON editor, inspect, dialogs |
| `tokens.mjs` | Token descriptions, the color validator, color resolution, theme generators. Shared with the tests |
| `presets.mjs` | The six base presets, extracted from the Claude Code binary |

The server binds to `127.0.0.1` and refuses requests with a foreign `Host` (DNS rebinding) or
`Origin` (another tab). It serves only the files listed above, and writes only
`<THEMES_DIR>/<slug>.json` for slugs matching `[A-Za-z0-9][A-Za-z0-9_-]*`.

## Limitations

- **The preview is an approximation.** It is hand-built HTML laid out like Claude Code, not the
  real renderer. Colors are exact; layout and glyphs are close. Check the final result in a real
  session (see the symlink tip above). The input rules, the mode line, inline code, links,
  tables, the statusLine row, the background-agents panel and the collapsed agent messages were
  re-checked against the 2.1.303 renderer source. Older parts of the mock were not.
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
hold against a live instance.
