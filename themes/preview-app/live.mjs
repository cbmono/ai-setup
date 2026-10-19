// Live preview: the real Claude Code, resumed on a synthetic session inside a PTY, themed by a
// file in a throwaway CLAUDE_CONFIG_DIR. Nothing under ~/.claude is written, no prompt is ever
// submitted (see SAFE below), and every process and temp dir dies with the server.
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import { delimiter, dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { fixtureJsonl } from './fixture.mjs';

const APP_DIR = dirname(new URL(import.meta.url).pathname);
const which = (bin) => (process.env.PATH || '').split(delimiter).map((d) => join(d, bin)).find((p) => existsSync(p));

// ---- SAFE: the only bytes that ever reach the PTY -----------------------------------
// Keystrokes the page may send, by name. Nothing here submits the prompt.
export const KEYS = { shiftTab: '\x1b[Z', esc: '\x1b', slash: '/', bang: '!', backspace: '\x7f' };
// Replies xterm.js produces for Claude Code's terminal queries, plus mouse-wheel reports.
// Anything else the page forwards (typed keys, clicks, paste) is dropped.
const REPLIES = [
  /\x1b\[\?[\d;]*c/y, /\x1b\[>[\d;]*c/y, // DA1, DA2
  /\x1bP>\|[ -~]{0,64}\x1b\\/y, // XTVERSION
  /\x1b\[\?\d*u/y, // kitty keyboard flags
  /\x1b\]1[0-2];rgb:[0-9a-f/]{5,20}(?:\x07|\x1b\\)/iy, /\x1b\]4;\d{1,3};rgb:[0-9a-f/]{5,20}(?:\x07|\x1b\\)/iy, // colours
  /\x1b\[\d{1,4};\d{1,4}R/y, /\x1b\[\??\d{1,5};\d\$y/y, // CPR, DECRPM
  /\x1b\[[48];\d{1,5};\d{1,5}t/y, /\x1b\[[IO]/y, // size reports, focus
  /\x1b\[<6[4-7];\d{1,4};\d{1,4}M/y, // wheel up/down
];
export const ENTER = /[\r\n]|\x1b\[13(?:;[\d:]*)?u|\x1bOM/;
export function filterReplies(s) {
  let out = '';
  for (let i = 0; i < s.length;) {
    const hit = REPLIES.map((re) => { re.lastIndex = i; return re.exec(s); }).find(Boolean);
    if (hit) { out += hit[0]; i += hit[0].length; continue; }
    const next = s.indexOf('\x1b', i + 1);
    i = next < 0 ? s.length : next;
  }
  return ENTER.test(out) ? '' : out;
}

// ---- environment ---------------------------------------------------------------------
const PYTHON = existsSync('/usr/bin/python3') ? '/usr/bin/python3' : which('python3');
const CLAUDE = process.env.CLAUDE_BIN ? (existsSync(process.env.CLAUDE_BIN) ? process.env.CLAUDE_BIN : null) : which('claude');
const USER_CFG = process.env.CLAUDE_CONFIG_DIR || join(homedir(), '.claude');
export const unavailable = () => (!PYTHON ? 'python3 not found' : !CLAUDE ? 'claude not found on PATH' : null);

// The owner's statusLine, read (never written) and re-pointed at the real config dir, because
// the temp CLAUDE_CONFIG_DIR would otherwise redirect "${CLAUDE_CONFIG_DIR:-$HOME/.claude}".
export function userStatusLine(file = join(USER_CFG, 'settings.json')) {
  try {
    const sl = JSON.parse(readFileSync(file, 'utf8')).statusLine;
    if (!sl || typeof sl.command !== 'string') return null;
    return { ...sl, command: sl.command.replace(/\$\{CLAUDE_CONFIG_DIR(?::-[^}]*)?\}|\$CLAUDE_CONFIG_DIR\b/g, USER_CFG) };
  } catch { return null; }
}

// Orca's terminal settings, so xterm.js draws like the owner's terminal: read live from its
// profile database, opened read-only. Missing keys take Orca's defaults; no Orca ⇒ null.
const ORCA_DB = join(homedir(), 'Library/Application Support/orca/profiles/local-default/profile-state.db');
const ORCA_THEMES = { 'Horizon Dark': { cursor: '#e95678', selectionBackground: '#2e303e' } };
export function orcaTerminal(db = ORCA_DB) {
  if (!PYTHON || !existsSync(db)) return null;
  const py = 'import sqlite3,sys;c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True);'
    + 'print(c.execute("select payload from profile_state_documents where domain=\'settings\'").fetchone()[0])';
  const r = spawnSync(PYTHON, ['-I', '-c', py, db], { encoding: 'utf8', timeout: 3000 });
  let o; try { o = JSON.parse(r.stdout); } catch { return null; }
  const v = (k, d) => o[`terminal${k}`] ?? d;
  const theme = v('ThemeDark', null);
  return { source: `Orca (${theme ?? 'default theme'})`, fontFamily: `"${v('FontFamily', 'SF Mono')}", ui-monospace, Menlo, monospace`,
    fontSize: v('FontSize', 14), fontWeight: v('FontWeight', 500), fontWeightBold: v('FontWeightBold', 700),
    lineHeight: v('LineHeight', 1), letterSpacing: v('LetterSpacing', 0), cursorStyle: v('CursorStyle', 'block'),
    cursorBlink: v('CursorBlink', true), padding: 4, theme: ORCA_THEMES[theme] ?? {} };
}

let ROOT = null;
const root = () => (ROOT ??= realpathSync(mkdtempSync(join(tmpdir(), 'claude-theme-preview-'))));
const MODES = { default: 'manual', plan: 'plan', accept: 'acceptEdits', auto: 'auto', bash: 'manual' };
const sessions = new Map();
let seq = 0;

class Live {
  constructor(id) { this.id = id; this.dir = join(root(), `s${++seq}`); this.buf = []; this.res = null; this.touch(); }

  touch() {
    clearTimeout(this.idle);
    this.idle = setTimeout(() => { this.emit('idle', ''); this.kill(); }, 30 * 60e3);
  }

  start({ cols, rows, mode, theme }) {
    this.stopHost();
    const cfg = join(this.dir, 'cfg'); const cwd = join(this.dir, 'control-panel');
    mkdirSync(join(cfg, 'themes'), { recursive: true }); mkdirSync(cwd, { recursive: true });
    this.cfg = cfg;
    if (theme) this.setTheme(theme);
    writeFileSync(join(cfg, '.claude.json'), JSON.stringify({ hasCompletedOnboarding: true, projects: { [cwd]: { hasTrustDialogAccepted: true } } }));
    // Resume rewrites the session file, so every spawn gets a fresh copy.
    const sid = randomUUID(); const proj = join(cfg, 'projects', cwd.replace(/[^a-zA-Z0-9]/g, '-'));
    mkdirSync(proj, { recursive: true });
    writeFileSync(join(proj, `${sid}.jsonl`), fixtureJsonl(cwd, sid));
    const settings = { theme: 'custom:preview' };
    const sl = userStatusLine(); if (sl) settings.statusLine = sl;
    const env = { HOME: homedir(), USER: process.env.USER || '', LANG: 'en_US.UTF-8', TERM: 'xterm-256color', COLORTERM: 'truecolor',
      PATH: [dirname(CLAUDE), '/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin'].join(':'),
      TERM_PROGRAM: 'Orca', FORCE_HYPERLINK: '1', CLAUDE_CONFIG_DIR: cfg, CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: '1' };
    const argv = [CLAUDE, '--resume', sid, '--settings', JSON.stringify(settings), '--permission-mode', MODES[mode] ?? 'manual'];
    const host = spawn(PYTHON, ['-I', join(APP_DIR, 'pty-host.py'), String(cols), String(rows), '--', ...argv],
      { cwd, env, stdio: ['pipe', 'pipe', 'ignore'] });
    this.host = host; this.buf = []; this.emit('reset', '');
    let quiet = null; const keys = mode === 'bash' ? ['bang'] : this.menu ? ['slash'] : [];
    host.stdout.on('data', (d) => {
      if (this.host !== host) return;
      const b64 = d.toString('base64');
      this.buf.push(b64); this.emit('out', b64);
      // Keys typed before the prompt is up are lost: send them once the first paint settles.
      if (keys.length) { clearTimeout(quiet); quiet = setTimeout(() => { for (const k of keys.splice(0)) this.key(k); }, 600); }
    });
    host.stdin.on('error', () => {});
    this.exited = new Promise((ok) => host.on('exit', () => { if (this.host === host) { this.host = null; this.emit('exit', ''); } ok(); }));
    this.opts = { cols, rows, mode };
  }

  send(msg) { if (this.host) this.host.stdin.write(`${JSON.stringify(msg)}\n`); }

  write(bytes) { if (bytes && !ENTER.test(bytes)) this.send({ w: Buffer.from(bytes, 'latin1').toString('base64') }); }

  key(name) { if (Object.hasOwn(KEYS, name)) this.write(KEYS[name]); }

  resize(cols, rows) { this.opts = { ...this.opts, cols, rows }; this.send({ r: [cols, rows] }); }

  menuKey(on) { this.menu = on; if (this.opts?.mode !== 'bash') this.key(on ? 'slash' : 'backspace'); }

  setTheme(theme) { if (this.cfg) writeFileSync(join(this.cfg, 'themes', 'preview.json'), `${JSON.stringify(theme, null, 2)}\n`); }

  emit(ev, data) { this.res?.write(`event: ${ev}\ndata: ${data}\n\n`); }

  attach(res) {
    this.res?.end(); this.res = res;
    clearTimeout(this.orphan);
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive' });
    for (const b of this.buf) this.emit('out', b);
    // A closed stream ends the session, after a grace that lets the page re-attach (mode change).
    res.on('close', () => { if (this.res === res) { this.res = null; this.orphan = setTimeout(() => this.kill(), 3000); } });
  }

  stopHost() { if (this.host) { const h = this.host; this.host = null; h.stdin.end(); h.kill('SIGTERM'); } }

  kill() {
    clearTimeout(this.idle); clearTimeout(this.orphan);
    this.stopHost(); this.res?.end(); this.res = null;
    sessions.delete(this.id);
    // The host needs a moment to reap claude; the dir goes after it (and with ROOT at exit).
    setTimeout(() => rmSync(this.dir, { recursive: true, force: true }), 1500).unref();
  }
}

// One live claude per browser session (the page's random id), at most four in all.
export function startLive(id, opts) {
  let s = sessions.get(id);
  if (!s) {
    if (sessions.size >= 4) return null;
    s = new Live(id); sessions.set(id, s);
  }
  s.menu = !!opts.menu;
  s.start(opts);
  s.orphan = setTimeout(() => { if (!s.res) s.kill(); }, 15e3);
  return s;
}
export const getLive = (id) => sessions.get(id);

// Last resort (crash, plain exit): hosts also end claude on their own when stdin closes.
process.on('exit', () => {
  for (const s of sessions.values()) s.host?.kill('SIGTERM');
  if (ROOT) rmSync(ROOT, { recursive: true, force: true });
});

// Server exit: end every claude, wait (bounded) for the hosts to reap them, then drop the temp root.
export async function stopAll() {
  const live = [...sessions.values()];
  for (const s of live) s.kill();
  await Promise.race([Promise.all(live.map((s) => s.exited)), new Promise((ok) => setTimeout(ok, 3000))]);
  if (ROOT) { rmSync(ROOT, { recursive: true, force: true }); ROOT = null; }
}
