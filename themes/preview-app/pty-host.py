# PTY host for the live preview — Python stdlib only, run as `python3 -I pty-host.py COLS ROWS -- cmd...`.
# stdout: the raw bytes the child writes to its terminal. stdin: one JSON message per line,
#   {"w": "<base64>"}  write to the terminal (Enter is refused here too, after the server's filter)
#   {"r": [cols, rows]} resize (TIOCSWINSZ + SIGWINCH)
# stdin EOF, SIGTERM or SIGINT end the child's process group; the master is closed before
# waitpid, because the child blocks on a full terminal otherwise.
import base64, fcntl, json, os, pty, re, select, signal, struct, sys, termios, time

cols, rows = int(sys.argv[1]), int(sys.argv[2])
cmd = sys.argv[sys.argv.index('--') + 1:]
FORBIDDEN = re.compile(rb'[\r\n]|\x1b\[13(;[\d:]*)?u|\x1bOM')  # Enter: plain, kitty, keypad

pid, fd = pty.fork()
if pid == 0:
    os.execv(cmd[0], cmd)


def size(c, r):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', r, c, 0, 0))
    try: os.kill(pid, signal.SIGWINCH)
    except OSError: pass


def finish(*_):
    try: os.close(fd)
    except OSError: pass
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try: os.killpg(pid, sig)
        except OSError: pass
        for _ in range(20):
            if os.waitpid(pid, os.WNOHANG)[0]: os._exit(0)
            time.sleep(0.05)
    os._exit(0)


signal.signal(signal.SIGTERM, finish)
signal.signal(signal.SIGINT, finish)
signal.signal(signal.SIGHUP, finish)
size(cols, rows)
out, inp, line = sys.stdout.buffer, sys.stdin.buffer.fileno(), b''
while True:
    ready, _, _ = select.select([fd, inp], [], [])
    if fd in ready:
        try: data = os.read(fd, 65536)
        except OSError: data = b''
        if not data: finish()
        out.write(data); out.flush()
    if inp in ready:
        chunk = os.read(inp, 65536)
        if not chunk: finish()
        line += chunk
        while b'\n' in line:
            msg, line = line.split(b'\n', 1)
            try: m = json.loads(msg)
            except ValueError: continue
            if 'r' in m: size(int(m['r'][0]), int(m['r'][1]))
            if 'w' in m:
                data = base64.b64decode(m['w'])
                if not FORBIDDEN.search(data): os.write(fd, data)
