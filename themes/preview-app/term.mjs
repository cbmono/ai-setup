// The live preview pane: xterm.js (drawn like Orca draws it) fed by the real Claude Code
// running on the server, plus a cell inspector that maps a cell's exact colour back to the
// theme tokens that can produce it.
import { TOKENS, PRESETS, ANSI_NAMES, toHex, luminance } from './tokens.mjs';

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const hex6 = (n) => `#${n.toString(16).padStart(6, '0')}`;
const ID_KEY = 'ctp:live-id';
const liveId = () => {
  try { return sessionStorage.getItem(ID_KEY) || (sessionStorage.setItem(ID_KEY, crypto.randomUUID()), sessionStorage.getItem(ID_KEY)); }
  catch { return (liveId.v ??= crypto.randomUUID()); }
};

// Which tokens, in the resolved theme, paint this colour? A colour may come from the file,
// from the base preset, or (measured: inline code uses `permission`) from the base preset even
// when the file overrides the token. Several matches are listed, never guessed between.
export function tokensFor(color, resolved, parsed, term) {
  const own = parsed?.overrides ?? {};
  const out = [];
  if (color.kind === 'rgb') {
    for (const [k, h] of Object.entries(resolved.hex)) if (h === color.hex) out.push({ token: k, src: Object.hasOwn(own, k) ? 'your file' : `base ${resolved.base}` });
    for (const [k, v] of Object.entries(PRESETS[resolved.base])) {
      if (resolved.hex[k] !== color.hex && toHex(v, term) === color.hex) out.push({ token: k, src: `base ${resolved.base} value (drawn without your override)` });
    }
  } else if (color.kind === 'palette') {
    const name = color.index < 16 ? ANSI_NAMES[color.index] : null;
    for (const [k, v] of Object.entries(resolved.raw)) if (v === `ansi256(${color.index})` || (name && v === `ansi:${name}`)) out.push({ token: k, src: Object.hasOwn(own, k) ? 'your file' : `base ${resolved.base}` });
  }
  return out.sort((a, b) => (a.src === 'your file' ? 0 : 1) - (b.src === 'your file' ? 0 : 1));
}

function cellColor(cell, which, term) {
  const fg = which === 'fg';
  if (fg ? cell.isFgRGB() : cell.isBgRGB()) return { kind: 'rgb', hex: hex6(fg ? cell.getFgColor() : cell.getBgColor()) };
  if (fg ? cell.isFgPalette() : cell.isBgPalette()) {
    const index = fg ? cell.getFgColor() : cell.getBgColor();
    return { kind: 'palette', index, hex: toHex(`ansi256(${index})`, term) };
  }
  return { kind: 'default', hex: fg ? term.foreground : term.background };
}

export class LiveView {
  constructor(host, { orca, onTip, onPick, onState, onDrawn, state }) {
    Object.assign(this, { host, orca: orca ?? {}, onTip, onPick, onState, onDrawn, state, enabled: true });
    this.id = liveId();
  }

  options(term) {
    const n = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white'];
    const theme = { background: term.background, foreground: term.foreground, cursor: term.foreground, ...this.orca.theme };
    term.palette.forEach((c, i) => { theme[i < 8 ? n[i] : `bright${n[i - 8][0].toUpperCase()}${n[i - 8].slice(1)}`] = c; });
    const { fontFamily = 'ui-monospace, Menlo, monospace', fontSize = 14, fontWeight = 'normal', fontWeightBold = 'bold',
      lineHeight = 1, letterSpacing = 0, cursorStyle = 'block', cursorBlink = false } = this.orca;
    // Orca's "auto" minimum contrast: 3 on a dark background, 4.5 on a light one.
    return { fontFamily, fontSize, fontWeight, fontWeightBold, lineHeight, letterSpacing, cursorStyle, cursorBlink, theme,
      minimumContrastRatio: luminance(term.background) < 0.35 ? 3 : 4.5, allowProposedApi: true, scrollback: 0 };
  }

  async start({ mode, menu, theme, term }) {
    this.termColors = term;
    if (!this.xt) {
      this.xt = new window.Terminal(this.options(term));
      this.xt.open(this.host);
      // Replies to Claude Code's terminal queries go back; the server drops everything else.
      let pend = ''; const flush = () => { const r = pend; pend = ''; if (r) this.post({ replies: r }); };
      this.xt.onData((d) => { pend += d; queueMicrotask(flush); });
      this.xt.onWriteParsed(() => { clearTimeout(this.scan); this.scan = setTimeout(() => this.onDrawn?.(this.colorsOnScreen()), 250); });
      this.host.addEventListener('mousemove', (e) => this.inspect(e, false), true);
      this.host.addEventListener('mousedown', (e) => this.inspect(e, true), true);
      this.host.addEventListener('mouseleave', () => this.onTip(null));
      new ResizeObserver(() => { clearTimeout(this.rz); this.rz = setTimeout(() => this.fit(), 120); }).observe(this.host);
    } else this.setPalette(term);
    this.fit(false);
    const r = await fetch(`/api/live/${this.id}`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ start: true, cols: this.xt.cols, rows: this.xt.rows, mode, menu, theme }) });
    if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error || `HTTP ${r.status}`);
    this.attach();
  }

  attach() {
    this.es?.close();
    const es = new EventSource(`/api/live/${this.id}/stream`);
    this.es = es;
    es.addEventListener('out', (e) => this.xt.write(Uint8Array.from(atob(e.data), (c) => c.charCodeAt(0))));
    es.addEventListener('reset', () => this.xt.reset());
    es.addEventListener('exit', () => this.onState('claude exited'));
    es.addEventListener('idle', () => { es.close(); this.onState('paused after 30 min idle'); });
    es.onerror = () => { if (this.es === es) { es.close(); this.onState('disconnected from the server'); } };
    es.onopen = () => this.onState(null);
  }

  post(body) {
    return fetch(`/api/live/${this.id}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).catch(() => {});
  }

  setTheme(theme) { clearTimeout(this.tt); this.tt = setTimeout(() => this.post({ theme }), 60); }

  setMenu(on) { this.post({ menu: on }); }

  setPalette(term) { this.termColors = term; if (this.xt) this.xt.options.theme = this.options(term).theme; }

  fit(post = true) {
    const scr = this.host.querySelector('.xterm-screen');
    if (!scr || !this.xt) return;
    const r = scr.getBoundingClientRect();
    const cw = r.width / this.xt.cols; const ch = r.height / this.xt.rows;
    const pad = 2 * (this.orca.padding ?? 4);
    const cols = Math.max(20, Math.floor((this.host.clientWidth - pad) / cw));
    const rows = Math.max(8, Math.floor((this.host.clientHeight - pad) / ch));
    if (cols === this.xt.cols && rows === this.xt.rows) return;
    this.xt.resize(cols, rows);
    if (post) this.post({ size: [cols, rows] });
  }

  cellAt(e) {
    const r = this.host.querySelector('.xterm-screen').getBoundingClientRect();
    const x = Math.floor(((e.clientX - r.left) / r.width) * this.xt.cols);
    const y = Math.floor(((e.clientY - r.top) / r.height) * this.xt.rows);
    if (x < 0 || y < 0 || x >= this.xt.cols || y >= this.xt.rows) return null;
    const buf = this.xt.buffer.active;
    return buf.getLine(buf.viewportY + y)?.getCell(x) ?? null;
  }

  colorsOnScreen() {
    const seen = new Set(); const buf = this.xt.buffer.active;
    for (let y = 0; y < this.xt.rows; y++) {
      const line = buf.getLine(buf.viewportY + y);
      for (let x = 0; line && x < this.xt.cols; x++) {
        const c = line.getCell(x);
        if (c.isFgRGB()) seen.add(hex6(c.getFgColor()));
        if (c.isBgRGB()) seen.add(hex6(c.getBgColor()));
      }
    }
    return seen;
  }

  // Hover explains the cell; mousedown jumps to its token. The capture phase keeps the click
  // from reaching xterm.js, so no mouse report is even produced.
  inspect(e, pick) {
    if (!this.enabled || !this.xt) return;
    if (pick) { e.preventDefault(); e.stopPropagation(); }
    const cell = this.cellAt(e);
    if (!cell) { this.onTip(null); return; }
    const { resolved, parsed } = this.state();
    const term = this.termColors;
    let fg = cellColor(cell, 'fg', term); let bg = cellColor(cell, 'bg', term);
    if (cell.isInverse()) [fg, bg] = [bg, fg];
    const ch = cell.getChars().trim();
    const parts = [['text', fg, ch ? `“${esc(ch)}”` : 'blank cell'], ['background', bg, '']].map(([what, c, label]) => {
      const cands = tokensFor(c, resolved, parsed, term);
      const sw = `<span class="sw" style="background:${c.hex}"></span>`;
      let why;
      if (cands.length) why = cands.map((x) => `<code>${esc(x.token)}</code> <span class="d">${esc(x.src)}${TOKENS[x.token]?.documented ? '' : ' · undocumented'}</span>`).join('<br>')
        + (cands.length > 1 ? '<div class="d">Ambiguous: these tokens share this colour; click picks the first.</div>' : '');
      else if (c.kind === 'default') why = `<span class="d">terminal ${what === 'text' ? 'foreground' : 'background'}, not the theme</span>`;
      else if (c.kind === 'palette') why = `<span class="d">terminal ANSI ${c.index < 16 ? ANSI_NAMES[c.index] : c.index}, from your terminal palette, not the theme</span>`;
      else why = '<span class="d">no token resolves to this colour: a literal colour in Claude Code (body text and code-block syntax use the terminal palette)</span>';
      return { html: `<div>${sw}${what} ${c.hex} ${label}<br>${why}</div>`, cands };
    });
    const dim = cell.isDim() ? '<div class="d">dimmed (SGR 2): the terminal fades the colour</div>' : '';
    this.onTip(parts.map((p) => p.html).join('') + dim, e);
    if (pick) { const tok = (parts[0].cands[0] ?? parts[1].cands[0])?.token; if (tok) this.onPick(tok); }
  }

  dispose() { this.es?.close(); this.xt?.dispose(); this.xt = null; }
}
