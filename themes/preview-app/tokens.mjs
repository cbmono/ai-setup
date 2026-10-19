// Token metadata and colour logic, shared by the page (app.mjs) and the test harness.
// Descriptions follow https://code.claude.com/docs/en/terminal-config ("Create a custom
// theme"). `documented: false` marks tokens the binary accepts as overrides (every key of a
// base preset is overridable) but the docs leave out.
import { PRESETS } from './presets.mjs';

export { PRESETS };
export const BASES = Object.keys(PRESETS);
export const DEFAULT_BASE = 'dark';

const G = {
  text: 'Text and accent',
  status: 'Status',
  input: 'Input box and modes',
  diff: 'Diff rendering',
  bg: 'Message backgrounds',
  meter: 'Usage meter and labels',
  agents: 'Subagent colors',
  rainbow: 'ultrathink rainbow',
  other: 'Undocumented',
};
export const GROUPS = G;

const T = (group, desc, documented = true) => ({ group, desc, documented });
export const TOKENS = {
  claude: T(G.text, 'Primary brand accent: spinner and assistant label'),
  claudeShimmer: T(G.text, 'Lighter half of the spinner shimmer'),
  text: T(G.text, 'Default foreground text'),
  inverseText: T(G.text, 'Text on a colored background, such as status badges'),
  inactive: T(G.text, 'Secondary text: hints, timestamps, disabled items'),
  inactiveShimmer: T(G.text, 'Shimmer pair of inactive'),
  subtle: T(G.text, 'Faint borders and de-emphasized secondary text'),
  suggestion: T(G.text, 'Autocomplete suggestions and picker selection'),
  permission: T(G.text, 'Dialog borders: permission prompts and pickers'),
  permissionShimmer: T(G.text, 'Shimmer pair of permission'),
  remember: T(G.text, 'Memory and CLAUDE.md indicators'),

  success: T(G.status, 'Success messages and passing checks'),
  error: T(G.status, 'Error messages and failures'),
  warning: T(G.status, 'Warnings, caution messages, auto mode indicator'),
  warningShimmer: T(G.status, 'Shimmer pair of warning'),
  merged: T(G.status, 'Merged pull request status'),

  promptBorder: T(G.input, 'Input box border'),
  promptBorderShimmer: T(G.input, 'Shimmer pair of promptBorder'),
  planMode: T(G.input, 'Plan mode accent, plan messages and dialogs'),
  autoAccept: T(G.input, 'Accept-edits mode accent'),
  autoAcceptShimmer: T(G.input, 'Not in the docs; lighter half of the auto-accept mode shimmer', false),
  bashBorder: T(G.input, 'Input box border while entering a ! shell command'),
  ide: T(G.input, 'IDE connection indicator'),
  fastMode: T(G.input, 'Fast mode indicator'),
  fastModeShimmer: T(G.input, 'Shimmer pair of fastMode'),
  effortUltra: T(G.input, 'The ultracode tag on the input box border'),

  diffAdded: T(G.diff, 'Background of added lines'),
  diffRemoved: T(G.diff, 'Background of removed lines'),
  diffAddedDimmed: T(G.diff, 'Added lines in the dimmed diff after a rejected edit'),
  diffRemovedDimmed: T(G.diff, 'Removed lines in the dimmed diff after a rejected edit'),
  diffAddedWord: T(G.diff, 'Word-level highlight within an added line'),
  diffRemovedWord: T(G.diff, 'Word-level highlight within a removed line'),

  userMessageBackground: T(G.bg, 'Background behind your messages'),
  userMessageBackgroundHover: T(G.bg, 'Message background while hovered/expanded (fullscreen only)'),
  bashMessageBackgroundColor: T(G.bg, 'Background behind ! shell command entries'),
  memoryBackgroundColor: T(G.bg, 'Background behind # memory entries'),
  selectionBg: T(G.bg, 'Mouse selection background (fullscreen only)'),

  rate_limit_fill: T(G.meter, 'Filled portion of the /usage meter'),
  rate_limit_empty: T(G.meter, 'Unfilled portion of the /usage meter'),
  briefLabelYou: T(G.meter, 'The "You" label on your messages'),
  briefLabelClaude: T(G.meter, 'The "Claude" label on assistant messages'),

  ...Object.fromEntries(['red', 'blue', 'green', 'yellow', 'purple', 'orange', 'pink', 'cyan']
    .map((c) => [`${c}_FOR_SUBAGENTS_ONLY`, T(G.agents, `Subagents declared with color: ${c}`)])),

  ...Object.fromEntries(['red', 'orange', 'yellow', 'green', 'blue', 'indigo', 'violet']
    .flatMap((c) => [
      [`rainbow_${c}`, T(G.rainbow, `ultrathink gradient: ${c}`)],
      [`rainbow_${c}_shimmer`, T(G.rainbow, `ultrathink gradient: ${c}, shimmer`)],
    ])),

  skill: T(G.other, 'Not in the docs; the name suggests the skill accent', false),
  background: T(G.other, 'Not in the docs; meaning unknown', false),
  claudeBlue_FOR_SYSTEM_SPINNER: T(G.other, 'Not in the docs; the name suggests the system spinner', false),
  claudeBlueShimmer_FOR_SYSTEM_SPINNER: T(G.other, 'Not in the docs; shimmer pair of the system spinner', false),
  professionalBlue: T(G.other, 'Not in the docs; meaning unknown', false),
  chromeYellow: T(G.other, 'Not in the docs; the name suggests the Claude in Chrome accent', false),
  clawd_body: T(G.other, 'Not in the docs; the name suggests the Clawd mascot body', false),
  clawd_background: T(G.other, 'Not in the docs; the name suggests the Clawd mascot background', false),
  composerSidebarBackground: T(G.other, 'Not in the docs; the name suggests the composer sidebar background', false),
};

export const ANSI_NAMES = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white',
  'blackBright', 'redBright', 'greenBright', 'yellowBright', 'blueBright', 'magentaBright',
  'cyanBright', 'whiteBright'];

// Mirrors Claude Code's own validator (`Z4()` in 2.1.303). An override that fails it is
// ignored by Claude Code and the token falls back to the base preset — the preview does
// the same, so what you see is what the CLI would draw.
export function isValidColor(v) {
  if (typeof v !== 'string') return false;
  if (/^rgb\(\s?\d{1,3},\s?\d{1,3},\s?\d{1,3}\s?\)$/.test(v)) return true;
  if (/^#[0-9a-fA-F]{6}$/.test(v) || /^#[0-9a-fA-F]{3}$/.test(v)) return true;
  if (/^ansi256\(\d{1,3}\)$/.test(v)) return true;
  if (v.startsWith('ansi:')) return ANSI_NAMES.includes(v.slice(5));
  return false;
}

// Used when the server could not ask the terminal (no TTY, or no reply).
export const FALLBACK_TERMINAL = {
  source: 'fallback (xterm defaults)',
  foreground: '#e5e5e5',
  background: '#1e1e1e',
  palette: ['#000000', '#cd0000', '#00cd00', '#cdcd00', '#0000ee', '#cd00cd', '#00cdcd', '#e5e5e5',
    '#7f7f7f', '#ff0000', '#00ff00', '#ffff00', '#5c5cff', '#ff00ff', '#00ffff', '#ffffff'],
};

const hex2 = (n) => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, '0');
export const rgbToHex = (r, g, b) => `#${hex2(r)}${hex2(g)}${hex2(b)}`;

export function hexToRgb(h) {
  const m = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(h);
  if (!m) return null;
  const s = m[1].length === 3 ? [...m[1]].map((c) => c + c).join('') : m[1];
  return [0, 2, 4].map((i) => parseInt(s.slice(i, i + 2), 16));
}

function ansi256(n, term) {
  if (n < 16) return term.palette[n];
  if (n < 232) {
    const i = n - 16;
    const lv = (x) => (x === 0 ? 0 : 55 + x * 40);
    return rgbToHex(lv(Math.floor(i / 36)), lv(Math.floor(i / 6) % 6), lv(i % 6));
  }
  const g = 8 + (n - 232) * 10;
  return rgbToHex(g, g, g);
}

// Any valid Claude Code colour -> #rrggbb, resolving ansi:* and ansi256 against the
// terminal's own palette (that is what the terminal does with them).
export function toHex(v, term) {
  const rgb = /^rgb\(\s?(\d{1,3}),\s?(\d{1,3}),\s?(\d{1,3})\s?\)$/.exec(v);
  if (rgb) return rgbToHex(+rgb[1], +rgb[2], +rgb[3]);
  if (v.startsWith('#')) return rgbToHex(...hexToRgb(v));
  const a256 = /^ansi256\((\d{1,3})\)$/.exec(v);
  if (a256) return ansi256(Math.min(255, +a256[1]), term);
  if (v.startsWith('ansi:')) return term.palette[ANSI_NAMES.indexOf(v.slice(5))];
  return null;
}

export function mix(a, b, t) {
  const [x, y] = [hexToRgb(a), hexToRgb(b)];
  return rgbToHex(...x.map((c, i) => c + (y[i] - c) * t));
}

export function luminance(h) {
  const [r, g, b] = hexToRgb(h).map((c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

// Theme file -> the effective colour of every token, plus what was ignored and why.
export function resolveTheme(theme, term) {
  const issues = [];
  const base = BASES.includes(theme?.base) ? theme.base : DEFAULT_BASE;
  if (theme?.base !== undefined && !BASES.includes(theme.base)) {
    issues.push({ key: 'base', level: 'error', msg: `unknown base "${theme.base}", falling back to "dark"` });
  }
  const raw = { ...PRESETS[base] };
  const overrides = theme?.overrides && typeof theme.overrides === 'object' ? theme.overrides : {};
  for (const [k, v] of Object.entries(overrides)) {
    if (!Object.hasOwn(raw, k)) issues.push({ key: k, level: 'warn', msg: 'unknown token, ignored by Claude Code' });
    else if (!isValidColor(v)) issues.push({ key: k, level: 'error', msg: `invalid color ${JSON.stringify(v)}, base value used` });
    else raw[k] = v;
  }
  const hex = Object.fromEntries(Object.entries(raw).map(([k, v]) => [k, toHex(v, term)]));
  return { base, raw, hex, issues };
}

// A new theme file listing every token, pre-filled with the base preset's values as hex —
// so the file is the full menu of options, and editing one line changes one thing.
export function fullTheme(name, base, term) {
  const overrides = {};
  for (const k of Object.keys(TOKENS)) overrides[k] = toHex(PRESETS[base][k], term);
  return { name, base, overrides };
}

// Claude Code's own *-ansi preset, resolved through this terminal's palette: the theme that
// "matches the terminal" by the CLI's own mapping. Backgrounds are blended rather than raw
// ANSI, because a full-saturation green behind a diff line is unreadable.
export function themeFromTerminal(name, term) {
  const dark = luminance(term.background) < 0.35;
  const base = dark ? 'dark' : 'light';
  const preset = PRESETS[dark ? 'dark-ansi' : 'light-ansi'];
  const t = fullTheme(name, base, term);
  for (const k of Object.keys(TOKENS)) t.overrides[k] = toHex(preset[k], term);
  const bg = term.background;
  const fg = term.foreground;
  const P = (n) => term.palette[ANSI_NAMES.indexOf(n)];
  Object.assign(t.overrides, {
    text: fg,
    inverseText: bg,
    subtle: mix(bg, fg, 0.3),
    inactive: mix(bg, fg, 0.55),
    inactiveShimmer: mix(bg, fg, 0.75),
    diffAdded: mix(bg, P('green'), 0.3),
    diffRemoved: mix(bg, P('red'), 0.3),
    diffAddedWord: mix(bg, P('green'), 0.55),
    diffRemovedWord: mix(bg, P('red'), 0.55),
    diffAddedDimmed: mix(bg, P('green'), 0.12),
    diffRemovedDimmed: mix(bg, P('red'), 0.12),
    userMessageBackground: mix(bg, fg, 0.1),
    userMessageBackgroundHover: mix(bg, fg, 0.15),
    bashMessageBackgroundColor: mix(bg, P('magenta'), 0.12),
    memoryBackgroundColor: mix(bg, P('cyan'), 0.12),
    selectionBg: mix(bg, P('blue'), 0.4),
    composerSidebarBackground: mix(bg, fg, 0.06),
    rate_limit_empty: mix(bg, fg, 0.2),
    clawd_background: bg,
  });
  return t;
}
