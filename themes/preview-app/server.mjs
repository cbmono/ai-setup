#!/usr/bin/env node
// Claude Code theme previewer — zero-dependency local server.
//
//   node themes/preview-app/server.mjs [--port 4477] [--no-detect]
//
// Run it from the terminal whose colours you want to preview against: on start it asks
// the terminal for its foreground, background and 16-colour palette (OSC 10/11/4), then
// serves the page on 127.0.0.1 and reads/writes theme files in the parent `themes/` dir.
import { createServer } from 'node:http';
import { readFile, writeFile, readdir } from 'node:fs/promises';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, extname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const APP_DIR = dirname(fileURLToPath(import.meta.url));
const THEMES_DIR = process.env.THEMES_DIR || dirname(APP_DIR);
const CACHE = process.env.TERMINAL_CACHE || join(APP_DIR, 'terminal-palette.local.json');
const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const opt = (n, d) => (args.includes(n) ? args[args.indexOf(n) + 1] : d);
const PORT = Number(opt('--port', process.env.PORT || 4477));

const SLUG = /^[a-z0-9][a-z0-9_-]{0,63}$/i;
const STATIC = { '/': 'index.html', '/index.html': 'index.html', '/app.mjs': 'app.mjs',
  '/tokens.mjs': 'tokens.mjs', '/presets.mjs': 'presets.mjs', '/style.css': 'style.css' };
const MIME = { '.html': 'text/html; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8' };

// ---- terminal detection -------------------------------------------------------------
// Queries go out in one write followed by a DA1 request (ESC[c). Terminals answer in
// order and every terminal answers DA1, so its reply means "no more colour replies are
// coming" — no fixed sleep, and a terminal that ignores OSC 4 still finishes fast.
export function parseReplies(buf) {
  const scale = (h) => Math.round((parseInt(h, 16) / (16 ** h.length - 1)) * 255);
  const hex = (r, g, b) => '#' + [r, g, b].map((c) => scale(c).toString(16).padStart(2, '0')).join('');
  const out = { palette: [] };
  const re = /\x1b\](10|11|4;(\d{1,3}));rgb:([0-9a-f]{1,4})\/([0-9a-f]{1,4})\/([0-9a-f]{1,4})(?:\x07|\x1b\\)/gi;
  for (const m of buf.matchAll(re)) {
    const c = hex(m[3], m[4], m[5]);
    if (m[1] === '10') out.foreground = c;
    else if (m[1] === '11') out.background = c;
    else if (+m[2] < 16) out.palette[+m[2]] = c;
  }
  return out;
}

function detectTerminal(timeoutMs = 1500) {
  const { stdin, stdout } = process;
  if (!stdin.isTTY || !stdout.isTTY) return Promise.resolve(null);
  // tmux swallows OSC queries unless wrapped in its passthrough envelope.
  const wrap = (s) => (process.env.TMUX ? `\x1bPtmux;${s.replaceAll('\x1b', '\x1b\x1b')}\x1b\\` : s);
  const queries = ['\x1b]10;?\x07', '\x1b]11;?\x07',
    ...Array.from({ length: 16 }, (_, i) => `\x1b]4;${i};?\x07`)].map(wrap).join('');
  return new Promise((resolve) => {
    let buf = '';
    const done = () => {
      clearTimeout(timer);
      stdin.off('data', onData);
      stdin.setRawMode(false);
      stdin.pause();
      const r = parseReplies(buf);
      const complete = r.foreground && r.background && r.palette.filter(Boolean).length === 16;
      resolve(complete ? r : null);
    };
    const onData = (d) => {
      buf += d.toString('latin1');
      if (/\x1b\[\?[\d;]*c/.test(buf)) done();
    };
    const timer = setTimeout(done, timeoutMs);
    stdin.setRawMode(true);
    stdin.resume();
    stdin.on('data', onData);
    stdout.write(queries + '\x1b[c');
  });
}

async function loadTerminal() {
  const name = process.env.TERM_PROGRAM || process.env.TERM || 'terminal';
  if (!flag('--no-detect')) {
    const t = await detectTerminal();
    if (t) {
      const term = { source: `detected from ${name}`, ...t, detectedAt: new Date().toISOString() };
      try { writeFileSync(CACHE, JSON.stringify(term, null, 2) + '\n'); } catch { /* cache is optional */ }
      return term;
    }
  }
  if (existsSync(CACHE)) {
    try {
      const t = JSON.parse(readFileSync(CACHE, 'utf8'));
      return { ...t, source: `cached: ${t.source} (${t.detectedAt?.slice(0, 10) ?? 'unknown date'})` };
    } catch { /* fall through */ }
  }
  return null; // the page falls back to its built-in defaults
}

// ---- http ---------------------------------------------------------------------------
const send = (res, code, body, type = 'application/json; charset=utf-8') => {
  res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body));
};

// Only this machine, only this origin: the server writes files, so a web page in another
// tab must not reach it (Origin check) and neither may a rebound DNS name (Host check).
function trusted(req) {
  const host = (req.headers.host || '').replace(/:\d+$/, '');
  if (!['127.0.0.1', 'localhost'].includes(host)) return false;
  const origin = req.headers.origin;
  return !origin || origin === `http://${req.headers.host}`;
}

const readBody = (req, limit = 256 * 1024) => new Promise((resolve, reject) => {
  let size = 0; const chunks = [];
  req.on('data', (c) => { size += c.length; if (size > limit) { reject(new Error('too large')); req.destroy(); } else chunks.push(c); });
  req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
  req.on('error', reject);
});

export function makeServer(terminal) {
  return createServer(async (req, res) => {
    try {
      if (!trusted(req)) return send(res, 403, { error: 'forbidden' });
      const url = new URL(req.url, 'http://localhost');
      const p = decodeURIComponent(url.pathname);

      if (req.method === 'GET' && STATIC[p]) {
        const f = STATIC[p];
        return send(res, 200, await readFile(join(APP_DIR, f)), MIME[extname(f)]);
      }
      if (req.method === 'GET' && p === '/api/terminal') return send(res, 200, terminal ?? {});
      if (req.method === 'GET' && p === '/api/themes') {
        const files = (await readdir(THEMES_DIR)).filter((f) => f.endsWith('.json') && SLUG.test(f.slice(0, -5)));
        const list = await Promise.all(files.sort().map(async (f) => {
          let name = f.slice(0, -5);
          try { name = JSON.parse(await readFile(join(THEMES_DIR, f), 'utf8')).name || name; } catch { /* show slug */ }
          return { slug: f.slice(0, -5), name };
        }));
        return send(res, 200, list);
      }
      const m = /^\/api\/themes\/([^/]+)$/.exec(p);
      if (m) {
        if (!SLUG.test(m[1])) return send(res, 400, { error: 'invalid slug' });
        const file = join(THEMES_DIR, `${m[1]}.json`);
        if (req.method === 'GET') {
          if (!existsSync(file)) return send(res, 404, { error: 'not found' });
          return send(res, 200, await readFile(file, 'utf8'), 'text/plain; charset=utf-8');
        }
        if (req.method === 'PUT') {
          const body = await readBody(req);
          let parsed;
          try { parsed = JSON.parse(body); } catch (e) { return send(res, 400, { error: `invalid JSON: ${e.message}` }); }
          if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return send(res, 400, { error: 'theme must be a JSON object' });
          if (req.headers['if-none-match'] === '*' && existsSync(file)) return send(res, 409, { error: 'exists' });
          await writeFile(file, body.endsWith('\n') ? body : body + '\n');
          return send(res, 200, { ok: true, slug: m[1] });
        }
      }
      send(res, 404, { error: 'not found' });
    } catch (e) {
      send(res, 500, { error: String(e.message || e) });
    }
  });
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const terminal = await loadTerminal();
  makeServer(terminal).listen(PORT, '127.0.0.1', () => {
    console.log(`Claude Code theme preview → http://127.0.0.1:${PORT}`);
    console.log(`  themes:   ${THEMES_DIR}`);
    console.log(`  terminal: ${terminal ? terminal.source : 'not detected — using defaults (run from a real terminal to detect)'}`);
  });
}
