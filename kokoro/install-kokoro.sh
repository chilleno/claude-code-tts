#!/usr/bin/env bash
# install-kokoro.sh — install the optional Kokoro neural voices for claude-tts.
# Run through `./install.sh --kokoro`, or directly. Idempotent.
#
# Everything lands in one folder (default ~/.local/share/claude-tts/kokoro,
# override with CLAUDE_TTS_KOKORO_HOME) shared by every Claude instance:
#   python/   private Python 3.11 (Kokoro needs 3.10–3.12), fetched by uv
#   venv/     PyTorch + kokoro (~1.5 GB)
#   hf/       Kokoro-82M model + the four voices (~350 MB)
#   espeak-ng-data/, tts_kokoro_server.py, tts_kokoro_say.py
# Nothing is installed system-wide; `./uninstall.sh --kokoro` deletes the folder.
# The model, voices and English pronunciation data are downloaded here, once;
# after that speech runs fully offline.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../hooks/tts-common.sh
. "$REPO_DIR/hooks/tts-common.sh"
KH="$TTS_KOKORO_HOME"

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) echo "error: the Kokoro engine supports macOS and Linux only" >&2; exit 1 ;;
esac
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required to install Kokoro" >&2; exit 1; }

echo "Installing Kokoro voices into $KH (≈2 GB download, one time)…"
mkdir -p "$KH"
export UV_PYTHON_INSTALL_DIR="$KH/python" UV_CACHE_DIR="$KH/.uv-cache" HF_HOME="$KH/hf" HF_HUB_DISABLE_TELEMETRY=1

# uv fetches the right Python version without touching the system one.
if command -v uv >/dev/null 2>&1; then
  UV=uv
else
  [ -x "$KH/boot/bin/uv" ] || { python3 -m venv "$KH/boot" && "$KH/boot/bin/pip" install -q uv; }
  UV="$KH/boot/bin/uv"
fi
[ -x "$KH/venv/bin/python" ] || "$UV" venv -q -p 3.11 "$KH/venv"
# pip: misaki downloads its English (spaCy) model with pip on first use.
"$UV" pip install -q -p "$KH/venv/bin/python" "kokoro==0.9.4" "misaki[en]==0.9.4" soundfile pip

# A running server would keep serving the old code.
pkill -f "$KH/tts_kokoro_server.py" 2>/dev/null || true
cp "$REPO_DIR/kokoro/tts_kokoro_server.py" "$REPO_DIR/kokoro/tts_kokoro_say.py" "$KH/"

# espeak-ng ignores data paths longer than its 160-byte buffer, and the one
# inside the venv usually is; keep a copy at a short path next to the server.
espeak_src="$("$KH/venv/bin/python" -c 'import espeakng_loader; print(espeakng_loader.get_data_path())')"
rm -rf "$KH/espeak-ng-data"
cp -R "$espeak_src" "$KH/espeak-ng-data"
if [ "${#KH}" -gt 128 ]; then   # espeak tries "$KH/espeak-ng-data/espeak-ng-data" (+30) in 160 bytes
  echo "warning: $KH is a long path; Spanish pronunciation may fail (espeak-ng path limit)." >&2
  echo "         Set CLAUDE_TTS_KOKORO_HOME to a shorter folder and re-run." >&2
fi

echo "Downloading the model and voices, then a test run:"
voices=()
for lang in en es; do for g in female male; do voices+=("$(kokoro_voice "$lang" "$g")"); done; done
"$KH/venv/bin/python" "$KH/tts_kokoro_server.py" --warmup "${voices[@]}"

rm -rf "$KH/.uv-cache"
echo "Kokoro installed ($(du -sh "$KH" | cut -f1)). Switch voices in a session with: tts voice man / tts voice woman"
