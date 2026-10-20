"""tts_kokoro_say.py — hand a reply (stdin) to the Kokoro server, starting it if needed.

Standard library only, so it starts in milliseconds. If the server can't be
reached or can't speak the language, runs the fallback command given after
`--` (e.g. `say -v Paulina -r 200`) with the same text on its stdin.

Usage: tts_kokoro_say.py --lang es-mx --voice ef_dora [--speed 1.0] [--stop | --quit] [-- FALLBACK...]
"""

import argparse, json, os, signal, socket, subprocess, sys, tempfile, time

HOME = os.path.dirname(os.path.abspath(__file__))


def socket_path():
    """Unix socket paths are capped at ~104 bytes (macOS); a long install path
    moves the socket to the per-user runtime/temp dir instead."""
    p = os.path.join(HOME, "kokoro.sock")
    if len(p.encode()) < 100:
        return p
    base = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
    return os.path.join(base, f"claude-tts-kokoro-{os.getuid()}.sock")


SOCK = socket_path()
PID = os.path.join(HOME, "server.pid")  # written by the server as soon as it starts, before the model loads
START_WAIT = float(os.environ.get("TTS_KOKORO_START_WAIT", "60"))  # cold start: import torch + load model


def kill_loading_server():
    """A server still loading its model can't answer on the socket yet; stop it by pid — only if that pid really is
    our server (pids get reused)."""
    try:
        pid = int(open(PID).read().strip())
        cmd = subprocess.run(["ps", "-p", str(pid), "-o", "command="], capture_output=True, text=True).stdout
        if os.path.join(HOME, "tts_kokoro_server.py") in cmd:
            os.kill(pid, signal.SIGTERM)
    except (OSError, ValueError):
        pass


def send(req, timeout=5):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(SOCK)
        s.sendall((json.dumps(req) + "\n").encode())
        return s.makefile("r").readline().strip()
    finally:
        s.close()


def start_server():
    log = open(os.path.join(HOME, "server.log"), "w")
    return subprocess.Popen([sys.executable, os.path.join(HOME, "tts_kokoro_server.py")],
                            stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)


def fallback(cmd, text):
    """exec the fallback speaker with text on stdin, so killing our pid kills it."""
    if not cmd:
        sys.exit(1)
    with tempfile.TemporaryFile() as f:
        f.write(text.encode())
        f.seek(0)
        os.dup2(f.fileno(), 0)
    try:
        os.execvp(cmd[0], cmd)
    except OSError:
        sys.exit(1)


def main():
    argv = sys.argv[1:]
    fb = []
    if "--" in argv:
        i = argv.index("--")
        argv, fb = argv[:i], argv[i + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", default="en")
    ap.add_argument("--voice", default="af_heart")
    ap.add_argument("--speed", type=float, default=1.0)
    ap.add_argument("--stop", action="store_true", help="stop current speech (no-op if the server isn't running)")
    ap.add_argument("--quit", action="store_true", help="stop speech and shut the server down, freeing its memory")
    a = ap.parse_args(argv)

    if a.stop or a.quit:
        try:
            send({"cmd": "quit" if a.quit else "stop"})
        except OSError:
            if a.quit:
                kill_loading_server()  # not answering: either not running, or still loading
        return

    text = sys.stdin.read()
    if not text.strip():
        return
    req = {"text": text, "lang": a.lang, "voice": a.voice, "speed": a.speed}
    try:
        reply = send(req)
    except OSError:
        server = start_server()
        reply, deadline = None, time.time() + START_WAIT
        while time.time() < deadline:
            time.sleep(0.25)
            try:
                reply = send(req)
                break
            except OSError:
                # exit 0 = another server holds the lock and is starting; anything else = crashed
                if server.poll() not in (None, 0):
                    break
    if reply != "ok":
        fallback(fb, text)


if __name__ == "__main__":
    main()
