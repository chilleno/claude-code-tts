"""tts_kokoro_server.py — long-lived Kokoro speech server for claude-tts.

Loads the Kokoro-82M model once and speaks requests that arrive on a Unix
socket, sentence by sentence (first audio starts after the first sentence is
synthesized, not the whole reply). A new request interrupts the one playing.
Exits on its own after TTS_KOKORO_IDLE seconds without requests, so the
~1 GB of model memory is not held forever.

Protocol: one JSON line per connection —
  {"text": "...", "lang": "es-mx", "voice": "ef_dora", "speed": 1.0}  -> "ok" | "unsupported" | "error"
  {"cmd": "stop"}                                                      -> "ok"   (stop speaking)
  {"cmd": "quit"}                                                      -> "ok"   (stop speaking and exit; `tts off`)

Usage:
  python tts_kokoro_server.py                 # serve (normally started by tts_kokoro_say.py)
  python tts_kokoro_server.py --warmup V...   # download model + voices, synthesize a test line, exit
"""

import atexit, fcntl, json, os, queue, re, shutil, signal, socket, subprocess, sys, tempfile, threading, time

HOME = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HOME)
from tts_kokoro_say import SOCK, PID  # one definition of where the socket and pid file live
LOCK = os.path.join(HOME, "server.lock")
IDLE = float(os.environ.get("TTS_KOKORO_IDLE", "1800"))
WARMUP = len(sys.argv) > 1 and sys.argv[1] == "--warmup"

if __name__ == "__main__" and not WARMUP:
    # Claim the server slot and publish our pid *before* the slow imports below, so `tts off` can stop a server
    # that is still loading. SIGTERM exits through atexit/finally, which remove the pid file and the socket.
    _lockf = open(LOCK, "w")
    try:
        fcntl.flock(_lockf, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(0)  # another server is already starting or running
    with open(PID, "w") as _f:
        _f.write(str(os.getpid()))
    atexit.register(lambda: os.path.exists(PID) and open(PID).read().strip() == str(os.getpid()) and os.unlink(PID))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

os.environ.setdefault("HF_HOME", os.path.join(HOME, "hf"))
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
if not WARMUP:
    os.environ.setdefault("HF_HUB_OFFLINE", "1")  # everything was fetched at install time

# espeak-ng keeps its data path in a 160-byte buffer and silently falls back to
# a baked-in CI path when ours is longer, so install.sh copies the data here.
import espeakng_loader
_espeak_data = os.path.join(HOME, "espeak-ng-data")
if os.path.isdir(_espeak_data):
    espeakng_loader.get_data_path = lambda: _espeak_data
    os.environ["ESPEAK_DATA_PATH"] = _espeak_data

import numpy as np, soundfile as sf, torch
from kokoro import KModel, KPipeline
from misaki import espeak

SR = 24000


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, file=sys.stderr, flush=True)


def pick_device():
    want = os.environ.get("TTS_KOKORO_DEVICE")
    if want:
        return want
    return "mps" if torch.backends.mps.is_available() else "cpu"


class Speaker:
    """Owns the model, one pipeline per language, and the current playback job."""

    def __init__(self):
        dev = pick_device()
        t0 = time.time()
        self.model = KModel(repo_id="hexgrad/Kokoro-82M").to(dev).eval()
        self.pipes = {}
        self.player = next((p for p in (["afplay"], ["paplay"], ["aplay", "-q"], ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet"])
                            if shutil.which(p[0])), None)
        self.job = 0
        self.proc = None
        self.lock = threading.Lock()
        # One synthesis at a time: an interrupted reply may still be mid-sentence
        # when the next starts, and concurrent MPS encoding aborts the process.
        self.synth = threading.Lock()
        log(f"model loaded on {dev} in {time.time() - t0:.1f}s; player={self.player and self.player[0]}")

    def pipeline(self, lang):
        """Kokoro pipeline for a tts lang code, or None when Kokoro can't speak it."""
        base = lang.split("-")[0] if lang else "en"
        if base == "en":
            key = "a"
        elif base == "es":
            # Castilian only when asked for (es-es); otherwise neutral Latin American (seseo).
            key = "e-es" if lang == "es-es" else "e-419"
        else:
            return None
        if key not in self.pipes:
            p = KPipeline(lang_code=key[0], repo_id="hexgrad/Kokoro-82M", model=self.model)
            if key == "e-419":
                p.g2p = espeak.EspeakG2P(language="es-419")
            self.pipes[key] = p
        return self.pipes[key]

    def stop(self):
        with self.lock:
            self.job += 1
            if self.proc and self.proc.poll() is None:
                self.proc.kill()

    def speak(self, text, lang, voice, speed):
        pipe = self.pipeline(lang)
        if pipe is None or not self.player:
            return "unsupported"
        self.stop()
        with self.lock:
            job = self.job
        threading.Thread(target=self._run, args=(job, pipe, text, voice, speed), daemon=True).start()
        return "ok"

    def _run(self, job, pipe, text, voice, speed):
        clips = queue.Queue()
        threading.Thread(target=self._play, args=(job, clips), daemon=True).start()
        try:
            for sentence in split_sentences(text):
                with self.synth:
                    if job != self.job:
                        break
                    audio = [r.audio.numpy() for r in pipe(sentence, voice=voice, speed=speed) if r.audio is not None]
                if not audio:
                    continue
                fd, path = tempfile.mkstemp(suffix=".wav", dir=HOME)
                os.close(fd)
                sf.write(path, np.concatenate(audio), SR)
                clips.put(path)
        except Exception as e:  # never take the server down for one bad reply
            log("synthesis failed:", repr(e))
        clips.put(None)

    def _play(self, job, clips):
        while (path := clips.get()) is not None:
            try:
                if job == self.job:
                    with self.lock:
                        self.proc = subprocess.Popen(self.player + [path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    self.proc.wait()
            finally:
                os.unlink(path)


def split_sentences(text, limit=300):
    """Sentence chunks for incremental playback; long run-ons split at commas.
    Kokoro's espeak languages (Spanish) don't chunk on their own and truncate
    long inputs, so this also keeps every chunk within the model's window."""
    out = []
    for s in re.split(r"(?<=[.!?…;:])\s+", text.strip()):
        while len(s) > limit:
            cut = s.rfind(",", 0, limit)
            cut = cut + 1 if cut > 0 else s.rfind(" ", 0, limit)
            if cut <= 0:
                cut = limit
            out.append(s[:cut].strip())
            s = s[cut:].strip()
        if s:
            out.append(s)
    return out


def warmup(voices):
    """Fetch the model, the voices and the English G2P data, then synthesize once per voice."""
    sp = Speaker()
    for v in voices:
        lang = "es" if v[0] == "e" else "en"
        t0 = time.time()
        pipe = sp.pipeline(lang)
        n = sum(len(r.audio) for r in pipe("Hola, todo listo." if lang == "es" else "Hello, all set.", voice=v) if r.audio is not None)
        print(f"  {v:12s} ok ({n / SR:.1f}s of audio in {time.time() - t0:.1f}s)", flush=True)


def serve():
    sp = Speaker()  # the server slot (lock + pid file) was claimed at import time
    if os.path.exists(SOCK):
        os.unlink(SOCK)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCK)  # bound only after the model is loaded: a connect means "ready"
    os.chmod(SOCK, 0o600)
    srv.listen(8)
    srv.settimeout(30)
    last = time.time()
    log("listening on", SOCK)
    try:
        while True:
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                playing = sp.proc is not None and sp.proc.poll() is None
                if not playing and time.time() - last > IDLE:
                    log("idle, exiting")
                    return
                continue
            last = time.time()
            quit_now = False
            with conn:
                conn.settimeout(5)
                try:
                    req = json.loads(conn.makefile("r", encoding="utf-8").readline())
                    if req.get("cmd") in ("stop", "quit"):
                        sp.stop()
                        quit_now = req["cmd"] == "quit"
                        reply = "ok"
                    else:
                        reply = sp.speak(req.get("text", ""), (req.get("lang") or "en").lower(),
                                         req.get("voice") or "af_heart", float(req.get("speed") or 1.0))
                except Exception as e:
                    log("bad request:", repr(e))
                    reply = "error"
                try:
                    conn.sendall((reply + "\n").encode())
                except OSError:
                    pass
            if quit_now:
                log("quit requested (tts off), exiting")
                return
    finally:
        sp.stop()
        srv.close()
        if os.path.exists(SOCK):
            os.unlink(SOCK)


if __name__ == "__main__":
    if WARMUP:
        warmup(sys.argv[2:])
    else:
        serve()
