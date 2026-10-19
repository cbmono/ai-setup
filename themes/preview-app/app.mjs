import {
  TOKENS, PRESETS, BASES, DEFAULT_BASE, FALLBACK_TERMINAL,
  isValidColor, toHex, resolveTheme, fullTheme, themeFromTerminal,
} from './tokens.mjs';

const $ = (s) => document.querySelector(s);
const el = {
  select: $('#theme-select'), termSelect: $('#term-select'), termStrip: $('#term-strip'),
  preview: $('#preview'), src: $('#src'), hl: $('#hl'), gutter: $('#gutter'), problems: $('#problems'),
  fileLabel: $('#file-label'), dirty: $('#dirty'), parse: $('#parse-status'),
  tip: $('#tip'), toast: $('#toast'), picker: $('#picker'), split: $('#split'), splitter: $('#splitter'),
  dlgNew: $('#dlg-new'), dlgExport: $('#dlg-export'), exOut: $('#ex-out'),
};

const state = {
  slug: null, saved: '', parsed: null, resolved: null, parseError: null,
  lines: [], terms: {}, term: FALLBACK_TERMINAL, mode: 'default', menu: false, inspect: true,
  curToken: null,
};

const store = {
  get(k) { try { return localStorage.getItem(`ctp:${k}`); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(`ctp:${k}`, v); } catch { /* per-viewer nicety only */ } },
};

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function toast(msg, err = false) {
  el.toast.textContent = msg;
  el.toast.className = `toast${err ? ' err' : ''}`;
  el.toast.hidden = false;
  clearTimeout(toast.t);
  toast.t = setTimeout(() => { el.toast.hidden = true; }, err ? 5000 : 2200);
}

// ---- preview markup -----------------------------------------------------------------
// Every coloured element names the token that paints it in data-t (and data-t2 for the
// shimmer half), which is what hover/click inspection reads. Colours come from CSS vars.
const V = (t) => `var(--t-${t})`;
const fg = (t, html, bold = false) => `<span data-t="${t}" style="color:${V(t)}">${bold ? `<b>${html}</b>` : html}</span>`;
const bg = (t, html, cls = '') => `<span data-t="${t}" class="${cls}" style="background:${V(t)}">${html}</span>`;
const shim = (t, t2, html, cls = 'shimmer') => `<span data-t="${t}" data-t2="${t2}" class="${cls}" style="--a:${V(t)};--b:${V(t2)}">${html}</span>`;
const row = (...p) => `<div class="row">${p.join('')}</div>`;
const rowBg = (t, ...p) => `<div class="row" data-t="${t}" style="background:${V(t)}">${p.join('')}</div>`;
const flex = (l, r) => `<div class="row flex"><span>${l}</span><span>${r}</span></div>`;
const gap = '<div class="gap"></div>';
const box = (t, rows, tag = '') => `<div class="box" data-t="${t}" style="border-color:${V(t)}">${tag}${rows.join('')}</div>`;
const I = (s) => fg('inactive', esc(s));
const Tx = (s, b) => fg('text', esc(s), b);
const dot = (t = 'text') => fg(t, '⏺');
const out = (...p) => row(`  ${I('⎿')}  `, ...p);

function diffLine(n, sign, t, word, pre, hit, post) {
  const lineNo = I(String(n).padStart(4));
  const body = `${Tx(` ${sign}  ${pre}`)}${hit ? bg(word, Tx(hit)) : ''}${Tx(post)}`;
  return row(`  ${lineNo} `, t ? bg(t, body, 'fill') : `<span class="fill">${body}</span>`);
}

function rainbow(word) {
  const c = ['red', 'orange', 'yellow', 'green', 'blue', 'indigo', 'violet'];
  return [...word].map((ch, i) => {
    const k = c[i % c.length];
    return `<span data-t="rainbow_${k}" data-t2="rainbow_${k}_shimmer" class="glint" style="--a:${V(`rainbow_${k}`)};--b:${V(`rainbow_${k}_shimmer`)};animation-delay:${i * 0.12}s">${ch}</span>`;
  }).join('');
}

function previewHTML(mode, menu) {
  const h = [];
  // header
  h.push(
    row(fg('clawd_body', ' ▐▛███▜▌'), '   ', Tx('Claude Code', true), ' ', I('v2.1.303')),
    row(fg('clawd_body', '▝▜█████▛▘'), '  ', I('Opus 5.5 · Claude Max')),
    row(fg('clawd_body', '  ▘▘ ▝▝'), '    ', I('~/workspace/private/ai-setup')),
    gap,
    row(' ', bg('claude', fg('inverseText', ' Tip ')), ' ', I('Run /theme to switch themes, or edit ~/.claude/themes/*.json')),
    gap,
  );
  // conversation
  h.push(
    rowBg('userMessageBackground', Tx('> make the diff colors match my terminal')),
    gap,
    row(dot(), ' ', Tx("I'll check the current theme first.")),
    gap,
    row(dot('success'), ' ', Tx('Read', true), Tx('(themes/midnight.json)')),
    out(I('Read '), fg('inactive', '42', true), I(' lines')),
    gap,
    row(dot('success'), ' ', Tx('Update', true), Tx('(themes/midnight.json)')),
    out(I('Updated themes/midnight.json with '), fg('inactive', '1', true), I(' addition and '), fg('inactive', '1', true), I(' removal')),
    diffLine(12, ' ', null, null, '  "overrides": {', '', ''),
    diffLine(13, '-', 'diffRemoved', 'diffRemovedWord', '    "diffAdded": ', '"#14532d"', ','),
    diffLine(13, '+', 'diffAdded', 'diffAddedWord', '    "diffAdded": ', '"#2f6f4a"', ','),
    diffLine(14, ' ', null, null, '    "diffRemoved": "#7f1d1d",', '', ''),
    gap,
    row(dot('success'), ' ', Tx('Skill', true), Tx('('), fg('skill', 'test-locators'), Tx(')')),
    gap,
    row(dot('error'), ' ', Tx('Bash', true), Tx('(npm test)')),
    out(fg('error', 'Error: 2 tests failed · theme.spec.ts:41')),
    gap,
    row(dot('success'), ' ', bg('purple_FOR_SUBAGENTS_ONLY', fg('inverseText', ' code-architect ')), Tx('(Review the theme loader)')),
    out(I('Done (8 tool uses · 12.4k tokens · 41s)')),
    row('  ', I('agents  '), ...['red', 'blue', 'green', 'yellow', 'purple', 'orange', 'pink', 'cyan']
      .map((c) => bg(`${c}_FOR_SUBAGENTS_ONLY`, fg('inverseText', ` ${c} `), 'chip'))),
    gap,
    row(dot('success'), ' ', Tx('Update', true), Tx('(src/theme.ts)')),
    out(fg('error', 'User rejected update to src/theme.ts')),
    diffLine(7, '-', 'diffRemovedDimmed', 'diffRemovedDimmed', '  const accent = ', 'base.claude', ';'),
    diffLine(7, '+', 'diffAddedDimmed', 'diffAddedDimmed', '  const accent = ', 'term.magenta', ';'),
    gap,
    rowBg('memoryBackgroundColor', fg('remember', '# ', true), Tx('always use pnpm, never npm')),
    out(fg('remember', 'Got it. Saved to project memory (CLAUDE.md)')),
    gap,
    rowBg('bashMessageBackgroundColor', fg('bashBorder', '! ', true), Tx('git status --short')),
    out(Tx(' M themes/midnight.json')),
    gap,
    row(dot(), ' ', Tx('Diff now '), bg('selectionBg', Tx('follows your terminal palette')), Tx('. '), fg('warning', '⚠ 2 tests still fail.'),
      ' ', fg('success', '✓ lint passed'), ' ', fg('merged', '⎇ PR #42 merged')),
    gap,
    rowBg('userMessageBackgroundHover', Tx('> /usage')),
    out(Tx('Current session  '), fg('rate_limit_fill', '██████████████'), fg('rate_limit_empty', '██████'), Tx('  71% used')),
    row('     ', I('Resets 3pm (Europe/Berlin)')),
    gap,
    row(fg('subtle', '─'.repeat(28)), ' ', fg('subtle', 'brief view'), ' ', fg('subtle', '─'.repeat(28))),
    row(fg('briefLabelYou', 'You   ', true), Tx(' switch the accent to pink')),
    row(fg('briefLabelClaude', 'Claude', true), Tx(' Done: claude and permission are now #ff7ac2')),
    gap,
    row(shim('claudeBlue_FOR_SYSTEM_SPINNER', 'claudeBlueShimmer_FOR_SYSTEM_SPINNER', '✻ Compacting conversation…')),
  );
  // dock: pinned to the bottom like the real prompt area
  const transcript = h.splice(0);
  if (mode === 'plan') {
    h.push(box('planMode', [
      row(fg('planMode', 'Ready to code?', true)),
      row(Tx("Here is Claude's plan:")),
      row(I('  1. Resolve ansi:* tokens through the terminal palette')),
      row(I('  2. Blend diff backgrounds into the terminal background')),
      row(fg('suggestion', '❯ 1. Yes, and auto-accept edits')),
      row(Tx('  2. Yes, and manually approve edits')),
      row(Tx('  3. No, keep planning')),
    ]));
  } else {
    h.push(box('permission', [
      row(shim('permission', 'permissionShimmer', 'Edit file', 'shimmer')),
      row(Tx('themes/midnight.json')),
      row(Tx('Do you want to make this edit?')),
      row(fg('suggestion', '❯ 1. Yes')),
      row(Tx('  2. Yes, allow all edits during this session')),
      row(Tx('  3. No, and tell Claude what to do differently')),
    ]));
  }
  h.push(row(shim('claude', 'claudeShimmer', '✻ Pondering…'), ' ', I('(12s · ↓ 1.2k tokens · '), shim('inactive', 'inactiveShimmer', 'esc to interrupt'), I(')')));
  // input
  const caret = `<span class="caret" data-t="text" style="background:${V('text')}"> </span>`;
  const bash = mode === 'bash';
  const tag = `<span class="tag">${fg('effortUltra', 'ultracode')}</span>`;
  let input;
  if (bash) input = row(fg('bashBorder', '! ', true), Tx('npm run build'), caret);
  else if (menu) input = row(Tx('> /th'), caret);
  else input = row(Tx('> '), rainbow('ultrathink'), Tx(' about the edge cases'), caret);
  h.push(box(bash ? 'bashBorder' : 'promptBorder', [input], bash ? '' : tag));
  // footer
  if (menu && !bash) {
    h.push(
      row('  ', fg('suggestion', '/theme              Change the theme')),
      row('  ', I('/terminal-setup     Install Shift+Enter key binding')),
      row('  ', I('/todos              List current todo items')),
    );
  } else {
    const left = {
      default: I('? for shortcuts'),
      plan: fg('planMode', '⏸ plan mode on') + I(' (shift+tab to cycle)'),
      accept: fg('autoAccept', '⏵⏵ accept edits on') + I(' (shift+tab to cycle)'),
      auto: shim('warning', 'warningShimmer', '⏵⏵ auto mode on') + I(' (shift+tab to cycle)'),
      bash: fg('bashBorder', '! for bash mode'),
    }[mode];
    const right = [fg('chromeYellow', '◉ Chrome'), fg('ide', '◯ IDE: VS Code'), shim('fastMode', 'fastModeShimmer', '↯ fast')].join('  ');
    h.push(flex(` ${left}`, `${right} `));
  }
  return `<div class="scroll">${transcript.join('')}</div><div class="dock">${h.join('')}</div>`;
}

// ---- rendering ------------------------------------------------------------------------
function applyColors() {
  const { hex } = state.resolved;
  const s = el.preview.style;
  s.setProperty('--term-bg', state.term.background);
  s.setProperty('--term-fg', state.term.foreground);
  for (const [k, v] of Object.entries(hex)) s.setProperty(`--t-${k}`, v);
}

function renderPreview() {
  const prev = el.preview.querySelector('.scroll');
  const y = prev ? prev.scrollTop : null;
  el.preview.innerHTML = previewHTML(state.mode, state.menu);
  const sc = el.preview.querySelector('.scroll');
  sc.scrollTop = y ?? sc.scrollHeight; // first paint starts at the bottom, like a live session
  const drawn = new Set();
  el.preview.querySelectorAll('[data-t]').forEach((n) => { drawn.add(n.dataset.t); if (n.dataset.t2) drawn.add(n.dataset.t2); });
  state.drawn = drawn;
  markMatches();
  renderGutter();
}

function renderTermStrip() {
  const t = state.term;
  el.termStrip.innerHTML = [t.background, t.foreground, ...t.palette]
    .map((c, i) => `<i style="background:${c}" title="${['background', 'foreground'][i] ?? `ansi ${i - 2}`}: ${c}"></i>`).join('');
  el.termStrip.title = t.source;
}

// ---- JSON editor ----------------------------------------------------------------------
// Per-line index of `"key": "value"` pairs, with the value's offsets in the whole text,
// so a token can be revealed and its value selected without re-parsing.
function indexLines(text) {
  const lines = [];
  let off = 0; let depth = 0; let overridesDepth = -1;
  for (const line of text.split('\n')) {
    const info = { start: off, text: line, key: null, inOverrides: overridesDepth >= 0 && depth > overridesDepth };
    const m = /^(\s*)"((?:[^"\\]|\\.)*)"\s*:\s*/.exec(line);
    if (m) {
      info.key = m[2];
      info.indent = m[1];
      const rest = line.slice(m[0].length);
      const v = /^"((?:[^"\\]|\\.)*)"/.exec(rest);
      if (v) {
        info.value = v[1];
        info.vStart = off + m[0].length + 1;
        info.vEnd = info.vStart + v[1].length;
      }
      if (m[2] === 'overrides' && depth === 1 && rest.startsWith('{')) overridesDepth = depth;
    }
    let inStr = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (inStr) { if (c === '\\') i++; else if (c === '"') inStr = false; } else if (c === '"') inStr = true;
      else if (c === '{' || c === '[') depth++;
      else if (c === '}' || c === ']') { depth--; if (overridesDepth >= 0 && depth <= overridesDepth) overridesDepth = -1; }
    }
    lines.push(info);
    off += line.length + 1;
  }
  return lines;
}

function highlight(line) {
  let html = ''; let last = 0;
  const re = /"(?:[^"\\]|\\.)*"(\s*:)?|[{}[\],:]|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|\btrue\b|\bfalse\b|\bnull\b/g;
  for (const m of line.matchAll(re)) {
    html += esc(line.slice(last, m.index));
    const t = m[0];
    if (t.startsWith('"')) {
      html += m[1] ? `<span class="k">${esc(t.slice(0, t.length - m[1].length))}</span>${esc(m[1])}` : `<span class="s">${esc(t)}</span>`;
    } else if (/^[{}[\],:]$/.test(t)) html += `<span class="p">${t}</span>`;
    else html += `<span class="n">${esc(t)}</span>`;
    last = m.index + t.length;
  }
  return html + esc(line.slice(last));
}

function issueFor(key) { return state.resolved?.issues.find((i) => i.key === key); }

function renderHighlight() {
  const cur = caretLine();
  el.hl.innerHTML = state.lines.map((l, i) => {
    const iss = l.key && (l.inOverrides || l.key === 'base') ? issueFor(l.key) : null;
    const cls = ['l', i === cur ? 'cur' : '', iss?.level === 'warn' ? 'unk' : '', iss?.level === 'error' ? 'bad' : ''].join(' ');
    return `<div class="${cls}">${highlight(l.text) || ' '}</div>`;
  }).join('');
}

function renderGutter() {
  const hex = state.resolved?.hex ?? {};
  el.gutter.innerHTML = state.lines.map((l, i) => {
    const tok = l.inOverrides && Object.hasOwn(PRESETS[DEFAULT_BASE], l.key) ? l.key : null;
    const iss = l.key && (l.inOverrides || l.key === 'base') ? issueFor(l.key) : null;
    const drawn = tok && state.drawn?.has(tok);
    const sw = tok
      ? `<span class="sw${drawn ? '' : ' off'}" data-tok="${tok}" style="background:${hex[tok]}" title="${esc(tok)}: ${hex[tok]}${drawn ? '' : ' (not drawn in this preview)'} — click to pick"></span>`
      : '<span class="sw none"></span>';
    const mk = iss ? `<span class="mk ${iss.level}" title="${esc(iss.msg)}">●</span>` : '<span class="mk"></span>';
    return `<div class="g">${mk}${sw}<span>${i + 1}</span></div>`;
  }).join('');
}

function renderProblems() {
  const items = [];
  if (state.parseError) items.push(`<li class="error" data-line="${state.parseError.line ?? ''}">JSON: ${esc(state.parseError.msg)}</li>`);
  for (const i of state.resolved?.issues ?? []) {
    items.push(`<li class="${i.level}" data-key="${esc(i.key)}"><code>${esc(i.key)}</code>: ${esc(i.msg)}</li>`);
  }
  el.problems.innerHTML = items.join('');
}

function parseErrorLine(text, e) {
  const lc = /line (\d+) column (\d+)/.exec(e.message);
  if (lc) return +lc[1];
  const pos = /position (\d+)/.exec(e.message);
  return pos ? text.slice(0, +pos[1]).split('\n').length : null;
}

function onSourceChange() {
  const text = el.src.value;
  state.lines = indexLines(text);
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('theme must be a JSON object');
    state.parsed = parsed;
    state.parseError = null;
    state.resolved = resolveTheme(parsed, state.term);
    applyColors();
    el.parse.textContent = `base: ${state.resolved.base} · ${Object.keys(parsed.overrides ?? {}).length} overrides`;
    el.parse.className = 'parse-status';
  } catch (e) {
    // Keep painting the last good theme; a half-typed edit must not blank the preview.
    state.parseError = { msg: e.message, line: parseErrorLine(text, e) };
    el.parse.textContent = 'invalid JSON: preview shows the last valid state';
    el.parse.className = 'parse-status err';
  }
  el.dirty.hidden = text === state.saved;
  renderHighlight();
  renderGutter();
  renderProblems();
  onCaret();
}

function syncScroll() {
  const { scrollTop: y, scrollLeft: x } = el.src;
  el.hl.style.transform = `translate(${-x}px, ${-y}px)`;
  el.gutter.style.transform = `translateY(${-y}px)`;
}

function caretLine() {
  return el.src.value.slice(0, el.src.selectionStart).split('\n').length - 1;
}

function onCaret() {
  const i = caretLine();
  el.hl.querySelectorAll('.l.cur').forEach((n) => n.classList.remove('cur'));
  el.hl.children[i]?.classList.add('cur');
  const l = state.lines[i];
  state.curToken = l?.inOverrides ? l.key : null;
  markMatches();
}

function markMatches() {
  el.preview.querySelectorAll('.match').forEach((n) => n.classList.remove('match'));
  const t = state.curToken;
  if (!t) return;
  el.preview.querySelectorAll(`[data-t="${CSS.escape(t)}"],[data-t2="${CSS.escape(t)}"]`).forEach((n) => n.classList.add('match'));
}

// Edits go through execCommand so the browser's own undo stack (⌘Z) keeps working.
function replaceRange(start, end, text, keepFocus = false) {
  if (keepFocus) { el.src.setRangeText(text, start, end, 'preserve'); onSourceChange(); return; }
  el.src.focus();
  el.src.setSelectionRange(start, end);
  if (!document.execCommand('insertText', false, text)) el.src.setRangeText(text, start, end, 'end');
  onSourceChange();
}

function lineIndexOf(token) {
  return state.lines.findIndex((l) => l.inOverrides && l.key === token);
}

function insertToken(token) {
  const hex = state.resolved.hex[token];
  const ov = state.lines.findIndex((l) => l.key === 'overrides' && /^\s*\{/.test(l.text.slice(l.text.indexOf(':') + 1)));
  if (ov < 0) {
    if (!state.parsed) { toast('Fix the JSON first: cannot add a token to an invalid file', true); return false; }
    const obj = { ...state.parsed, overrides: { [token]: hex } };
    replaceRange(0, el.src.value.length, JSON.stringify(obj, null, 2) + '\n');
    return true;
  }
  const l = state.lines[ov];
  const braceAt = l.start + l.text.indexOf('{', l.text.indexOf(':'));
  const inner = `${l.indent}  `;
  const afterBrace = el.src.value.slice(braceAt + 1);
  const empty = /^\s*\}/.test(afterBrace);
  if (empty) {
    const close = braceAt + 1 + afterBrace.indexOf('}');
    replaceRange(braceAt + 1, close, `\n${inner}"${token}": "${hex}"\n${l.indent}`);
  } else {
    replaceRange(braceAt + 1, braceAt + 1, `\n${inner}"${token}": "${hex}",`);
  }
  return true;
}

function revealToken(token) {
  let i = lineIndexOf(token);
  if (i < 0) {
    if (!insertToken(token)) return;
    i = lineIndexOf(token);
    toast(`Added "${token}" to overrides with its current value`);
  }
  const l = state.lines[i];
  el.src.focus();
  if (l.vStart !== undefined) el.src.setSelectionRange(l.vStart, l.vEnd);
  const lh = parseFloat(getComputedStyle(el.src).lineHeight) || 20;
  el.src.scrollTop = Math.max(0, i * lh - el.src.clientHeight / 3);
  syncScroll();
  onCaret();
  const n = el.hl.children[i];
  if (n) { n.classList.remove('flash'); void n.offsetWidth; n.classList.add('flash'); }
}

function revealKey(key) {
  const i = state.lines.findIndex((l) => l.key === key && (l.inOverrides || key === 'base'));
  if (i >= 0) {
    const l = state.lines[i];
    el.src.focus();
    el.src.setSelectionRange(l.vStart ?? l.start, l.vEnd ?? l.start + l.text.length);
    const lh = parseFloat(getComputedStyle(el.src).lineHeight) || 20;
    el.src.scrollTop = Math.max(0, i * lh - el.src.clientHeight / 3);
    syncScroll();
    onCaret();
  }
}

// ---- inspect ----------------------------------------------------------------------------
function tipFor(target) {
  const t = target.dataset.t;
  const t2 = target.dataset.t2;
  const meta = TOKENS[t];
  const hex = state.resolved.hex[t];
  const own = state.parsed?.overrides && Object.hasOwn(state.parsed.overrides, t) && isValidColor(state.parsed.overrides[t]);
  const line = (k) => `<span class="sw" style="background:${state.resolved.hex[k]}"></span><code>${esc(k)}</code> ${state.resolved.hex[k]}`;
  return [
    line(t),
    ` <span class="d">${own ? `= ${esc(state.parsed.overrides[t])}` : `from base ${state.resolved.base}`}</span>`,
    meta ? `<div class="d">${esc(meta.desc)}${meta.documented ? '' : ' · placement in this preview is a guess'}</div>` : '',
    t2 ? `<div>${line(t2)} <span class="d">⌥-click</span></div>` : '',
  ].join('');
}

function onPreviewMove(e) {
  if (!state.inspect) { el.tip.hidden = true; return; }
  const target = e.target.closest('[data-t]');
  // Outline only the innermost element, the one a click would pick; :hover would light up every ancestor box.
  if (target !== state.hov) { state.hov?.classList.remove('hov'); target?.classList.add('hov'); state.hov = target; }
  if (target) el.tip.innerHTML = tipFor(target);
  else el.tip.innerHTML = `<span class="sw" style="background:${state.term.background}"></span>Terminal background ${state.term.background}<div class="d">Set by your terminal, not by the theme</div>`;
  el.tip.hidden = false;
  const pad = 14;
  const { innerWidth: W, innerHeight: H } = window;
  const r = el.tip.getBoundingClientRect();
  el.tip.style.left = `${Math.min(e.clientX + pad, W - r.width - 8)}px`;
  el.tip.style.top = `${e.clientY + pad + r.height > H ? e.clientY - r.height - pad : e.clientY + pad}px`;
}

function onPreviewClick(e) {
  if (!state.inspect) return;
  const target = e.target.closest('[data-t]');
  if (!target) return;
  e.preventDefault();
  revealToken(e.altKey && target.dataset.t2 ? target.dataset.t2 : target.dataset.t);
}

// ---- files ------------------------------------------------------------------------------
async function api(path, opts) {
  const r = await fetch(path, opts);
  if (!r.ok) {
    let msg = `${r.status}`;
    try { msg = (await r.json()).error || msg; } catch { /* keep status */ }
    throw new Error(msg);
  }
  return r;
}

async function refreshList(select) {
  const list = await (await api('/api/themes')).json();
  el.select.innerHTML = list.map((t) => `<option value="${esc(t.slug)}">${esc(t.name)} (${esc(t.slug)}.json)</option>`).join('');
  if (select) el.select.value = select;
  return list;
}

function confirmDiscard() {
  return el.src.value === state.saved || window.confirm('Discard unsaved changes?');
}

async function loadTheme(slug) {
  const text = await (await api(`/api/themes/${encodeURIComponent(slug)}`)).text();
  state.slug = slug;
  state.saved = text;
  el.src.value = text;
  el.fileLabel.textContent = `themes/${slug}.json`;
  el.select.value = slug;
  store.set('theme', slug);
  el.src.scrollTop = 0;
  el.src.setSelectionRange(0, 0);
  onSourceChange();
  syncScroll();
  renderPreview();
}

async function save() {
  if (!state.slug) return;
  try {
    await api(`/api/themes/${encodeURIComponent(state.slug)}`, { method: 'PUT', body: el.src.value, headers: { 'Content-Type': 'application/json' } });
    state.saved = el.src.value.endsWith('\n') ? el.src.value : `${el.src.value}\n`;
    if (!el.src.value.endsWith('\n')) { el.src.value = state.saved; }
    onSourceChange();
    await refreshList(state.slug);
    toast(`Saved themes/${state.slug}.json`);
  } catch (e) {
    toast(`Save failed: ${e.message}`, true);
  }
}

// ---- dialogs ----------------------------------------------------------------------------
function openNew() {
  const f = el.dlgNew.querySelector('form');
  f.reset();
  el.dlgNew.returnValue = '';
  f.from.innerHTML = [
    '<option value="terminal">Match my terminal (Claude Code ANSI preset, resolved)</option>',
    ...BASES.map((b) => `<option value="base:${b}">Base preset: ${b}</option>`),
    state.parsed ? '<option value="copy">Copy of the current file (all tokens filled in)</option>' : '',
  ].join('');
  el.dlgNew.showModal();
}

async function createTheme(form) {
  const slug = form.slug.value.trim();
  const name = form.elements.display.value.trim() || slug;
  const from = form.from.value;
  let theme;
  if (from === 'terminal') theme = themeFromTerminal(name, state.term);
  else if (from === 'copy') {
    theme = fullTheme(name, state.resolved.base, state.term);
    for (const k of Object.keys(theme.overrides)) theme.overrides[k] = state.resolved.hex[k];
  } else theme = fullTheme(name, from.slice(5), state.term);
  try {
    await api(`/api/themes/${encodeURIComponent(slug)}`, {
      method: 'PUT', body: `${JSON.stringify(theme, null, 2)}\n`,
      headers: { 'Content-Type': 'application/json', 'If-None-Match': '*' },
    });
  } catch (e) {
    toast(e.message === 'exists' ? `themes/${slug}.json already exists` : `Create failed: ${e.message}`, true);
    return;
  }
  await refreshList(slug);
  await loadTheme(slug);
  toast(`Created themes/${slug}.json`);
}

function exportJSON() {
  if (!state.parsed) return null;
  const onlyChanged = $('#ex-changed').checked;
  const documented = $('#ex-documented').checked;
  const normalize = $('#ex-hex').checked;
  const base = state.resolved.base;
  const src = state.parsed.overrides ?? {};
  const order = [...Object.keys(TOKENS), ...Object.keys(src).filter((k) => !TOKENS[k])];
  const overrides = {};
  for (const k of order) {
    if (!Object.hasOwn(src, k) || !Object.hasOwn(PRESETS[base], k) || !isValidColor(src[k])) continue;
    if (documented && !TOKENS[k]?.documented) continue;
    const hex = toHex(src[k], state.term);
    if (onlyChanged && hex === toHex(PRESETS[base][k], state.term)) continue;
    overrides[k] = normalize ? hex : src[k];
  }
  const outTheme = { name: typeof state.parsed.name === 'string' && state.parsed.name ? state.parsed.name : state.slug, base, overrides };
  return `${JSON.stringify(outTheme, null, 2)}\n`;
}

function refreshExport() {
  el.exOut.value = exportJSON() ?? '// Fix the JSON errors first: an invalid file cannot be exported.';
}

// ---- boot -------------------------------------------------------------------------------
function setTerminal(key) {
  state.term = state.terms[key] ?? FALLBACK_TERMINAL;
  store.set('term', key);
  renderTermStrip();
  if (state.parsed) state.resolved = resolveTheme(state.parsed, state.term);
  if (state.resolved) { applyColors(); renderGutter(); }
}

async function initTerminals() {
  let detected = null;
  try { detected = await (await api('/api/terminal')).json(); } catch { /* fall back */ }
  const light = { ...FALLBACK_TERMINAL, source: 'fallback light', foreground: '#1f2328', background: '#ffffff' };
  const hexOk = (c) => typeof c === 'string' && /^#[0-9a-f]{6}$/i.test(c);
  if (detected && hexOk(detected.background) && hexOk(detected.foreground)
    && Array.isArray(detected.palette) && detected.palette.length === 16 && detected.palette.every(hexOk)) {
    state.terms.detected = { ...detected, source: String(detected.source ?? 'detected') };
  }
  state.terms.dark = FALLBACK_TERMINAL;
  state.terms.light = light;
  el.termSelect.innerHTML = Object.entries(state.terms)
    .map(([k, t]) => `<option value="${k}">${esc(t.source)}</option>`).join('');
  const want = store.get('term');
  const key = want && state.terms[want] ? want : (state.terms.detected ? 'detected' : 'dark');
  el.termSelect.value = key;
  setTerminal(key);
  if (!state.terms.detected) toast('Terminal colors not detected: start the server from a real terminal to use yours');
}

function wire() {
  el.src.addEventListener('input', onSourceChange);
  el.src.addEventListener('scroll', syncScroll);
  for (const ev of ['keyup', 'click', 'select']) el.src.addEventListener(ev, onCaret);
  el.src.addEventListener('keydown', (e) => {
    if (e.key === 'Tab' && !e.shiftKey) { e.preventDefault(); replaceRange(el.src.selectionStart, el.src.selectionEnd, '  '); }
  });
  window.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 's') { e.preventDefault(); save(); }
  });
  window.addEventListener('beforeunload', (e) => { if (el.src.value !== state.saved) e.preventDefault(); });

  el.preview.addEventListener('mousemove', onPreviewMove);
  el.preview.addEventListener('mouseleave', () => { el.tip.hidden = true; state.hov?.classList.remove('hov'); state.hov = null; });
  el.preview.addEventListener('click', onPreviewClick);

  el.gutter.addEventListener('click', (e) => {
    const sw = e.target.closest('.sw[data-tok]');
    if (!sw) return;
    const tok = sw.dataset.tok;
    revealToken(tok);
    el.picker.value = state.resolved.hex[tok];
    el.picker.dataset.tok = tok;
    const r = sw.getBoundingClientRect();
    el.picker.style.left = `${r.right}px`;
    el.picker.style.top = `${r.top}px`;
    if (el.picker.showPicker) el.picker.showPicker(); else el.picker.click();
  });
  el.picker.addEventListener('input', () => {
    const l = state.lines[lineIndexOf(el.picker.dataset.tok)];
    if (l?.vStart !== undefined) replaceRange(l.vStart, l.vEnd, el.picker.value, true);
  });

  el.problems.addEventListener('click', (e) => {
    const li = e.target.closest('li');
    if (!li) return;
    if (li.dataset.key) revealKey(li.dataset.key);
    else if (li.dataset.line) {
      const l = state.lines[+li.dataset.line - 1];
      if (l) { el.src.focus(); el.src.setSelectionRange(l.start, l.start + l.text.length); }
    }
  });

  $('#mode-seg').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-mode]');
    if (!b) return;
    state.mode = b.dataset.mode;
    $('#mode-seg').querySelectorAll('button').forEach((x) => x.classList.toggle('on', x === b));
    renderPreview();
  });
  $('#opt-menu').addEventListener('change', (e) => { state.menu = e.target.checked; renderPreview(); });
  $('#opt-inspect').addEventListener('change', (e) => {
    state.inspect = e.target.checked;
    el.preview.classList.toggle('inspect', state.inspect);
    if (!state.inspect) el.tip.hidden = true;
  });
  el.preview.classList.add('inspect');

  el.select.addEventListener('change', async () => {
    const want = el.select.value;
    if (!confirmDiscard()) { el.select.value = state.slug; return; }
    await loadTheme(want);
  });
  el.termSelect.addEventListener('change', () => setTerminal(el.termSelect.value));

  $('#btn-new').addEventListener('click', openNew);
  $('#btn-save').addEventListener('click', save);
  el.dlgNew.addEventListener('close', () => {
    if (el.dlgNew.returnValue === 'ok' && confirmDiscard()) createTheme(el.dlgNew.querySelector('form'));
  });
  $('#btn-export').addEventListener('click', () => { refreshExport(); el.dlgExport.showModal(); });
  el.dlgExport.querySelectorAll('input[type=checkbox]').forEach((c) => c.addEventListener('change', refreshExport));
  $('#ex-copy').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(el.exOut.value); toast('Copied portable theme JSON'); } catch { el.exOut.select(); toast('Select-all done: press ⌘C to copy'); }
  });
  $('#ex-download').addEventListener('click', () => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([el.exOut.value], { type: 'application/json' }));
    a.download = `${state.slug ?? 'theme'}.json`;
    a.click();
    URL.revokeObjectURL(a.href);
  });

  // splitter
  const saved = store.get('split');
  if (saved) el.split.style.setProperty('--left', saved);
  el.splitter.addEventListener('pointerdown', (e) => {
    el.splitter.setPointerCapture(e.pointerId);
    const move = (ev) => {
      const r = el.split.getBoundingClientRect();
      const pct = `${Math.min(80, Math.max(25, ((ev.clientX - r.left) / r.width) * 100)).toFixed(1)}%`;
      el.split.style.setProperty('--left', pct);
      store.set('split', pct);
    };
    const up = () => { el.splitter.removeEventListener('pointermove', move); el.splitter.removeEventListener('pointerup', up); };
    el.splitter.addEventListener('pointermove', move);
    el.splitter.addEventListener('pointerup', up);
  });
}

async function boot() {
  wire();
  await initTerminals();
  // A resolved theme must exist before the first preview paint, even with no files yet.
  state.resolved = resolveTheme({ base: DEFAULT_BASE }, state.term);
  applyColors();
  renderPreview();
  const list = await refreshList();
  if (!list.length) { openNew(); return; }
  const want = store.get('theme');
  await loadTheme(list.some((t) => t.slug === want) ? want : list[0].slug);
}

boot().catch((e) => toast(`Failed to start: ${e.message}`, true));
