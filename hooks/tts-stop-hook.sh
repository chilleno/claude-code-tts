#!/usr/bin/env bash
# tts-stop-hook.sh — Stop hook for claude-tts.
#
# When the flag file is on, takes the finished reply (last_assistant_message
# from the hook's JSON input), strips markdown/code/URLs so they aren't read
# symbol-by-symbol, interrupts any speech still playing, and speaks the text
# in the background. Always exits 0 quickly — never blocks the session.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tts-common.sh
. "$SCRIPT_DIR/tts-common.sh"

# ---------------------------------------------------------------------------
# TUNE ME: voice + speed.
#   TTS_VOICE  — macOS voice name, e.g. "Samantha", "Daniel" (`say -v ?` lists
#                them). Empty = system default voice.
#   TTS_RATE   — words per minute on macOS (`say -r`). Typical: 150–250.
#   TTS_KOKORO_SPEED — Kokoro speaking speed (./install.sh --kokoro); 1.0 = natural.
# All can also be overridden per-session via environment variables.
# ---------------------------------------------------------------------------
TTS_VOICE="${TTS_VOICE:-}"
TTS_RATE="${TTS_RATE:-200}"
TTS_KOKORO_SPEED="${TTS_KOKORO_SPEED:-1.0}"

# Test hook: override the speech binary (e.g. a stub `say`).
TTS_SAY_CMD="${TTS_SAY_CMD:-}"

tts_is_on || exit 0

text="$(json_get last_assistant_message)"
[ -z "$text" ] && exit 0

# --- sanitize for speech ----------------------------------------------------
# 1. fenced code blocks -> "Code omitted."   2. inline backticks stripped
# 3. headers/bold/italic/list/table markup stripped
# 4. [text](url) -> text; bare URLs and long paths dropped
# 5. whitespace collapsed
speech="$(printf '%s\n' "$text" | awk '
  /^[[:space:]]*```/ { in_code = !in_code; if (in_code) print "Code omitted."; next }
  in_code { next }
  { print }
' | sed -E \
    -e 's/`([^`]*)`/\1/g' \
    -e 's/^[[:space:]]*#{1,6}[[:space:]]*//' \
    -e 's/\*\*//g' -e 's/__//g' \
    -e 's/(^|[[:space:]])[*_]([^*_]+)[*_]/\1\2/g' \
    -e 's/^[[:space:]]*[-*+][[:space:]]+//' \
    -e 's/^[[:space:]]*[0-9]+\.[[:space:]]+//' \
    -e '/^[[:space:]]*\|.*\|[[:space:]]*$/d' \
    -e 's/\[([^]]*)\]\([^)]*\)/\1/g' \
    -e 's~https?://[^[:space:]]+~~g' \
    -e 's~(^|[[:space:]])[~/.][^[:space:]]*/[^[:space:]]+~\1~g' \
  | tr '\n' ' ' | tr -s '[:space:]' ' ' \
  | sed -e 's/^ //' -e 's/ $//')"
[ -z "$speech" ] && exit 0

# --- language-aware voice ---------------------------------------------------
# Precedence: TTS_VOICE env > `tts voice NAME` file > auto-pick from `tts lang`.
TTS_LANG_CODE="$(tts_lang)"

resolve_say_voice() { # sets say_voice for say-compatible engines
  say_voice="$TTS_VOICE"
  [ -z "$say_voice" ] && say_voice="$(tts_voice)"
  if [ -z "$say_voice" ] && [ -n "$TTS_LANG_CODE" ]; then
    say_voice="$(pick_voice "$TTS_LANG_CODE")"
  fi
}

# --- pick a speaker per platform -------------------------------------------
# speak() reads the text on stdin. Add a platform: add a case branch.
speaker=()
if [ -n "$TTS_SAY_CMD" ]; then
  speaker=("$TTS_SAY_CMD")
  resolve_say_voice
  [ -n "$say_voice" ] && speaker+=(-v "$say_voice")
  speaker+=(-r "$TTS_RATE")
else
  case "$(uname -s)" in
    Darwin)
      if command -v say >/dev/null 2>&1; then
        speaker=(say)
        resolve_say_voice
        [ -n "$say_voice" ] && speaker+=(-v "$say_voice")
        speaker+=(-r "$TTS_RATE")
      fi
      ;;
    Linux)
      if command -v spd-say >/dev/null 2>&1; then
        speaker=(spd-say -w -e)   # -e reads stdin, -w waits (we background anyway)
        [ -n "$TTS_LANG_CODE" ] && speaker+=(-l "${TTS_LANG_CODE%%-*}")
      elif command -v espeak >/dev/null 2>&1; then
        speaker=(espeak --stdin)
        [ -n "$TTS_LANG_CODE" ] && speaker+=(-v "${TTS_LANG_CODE%%-*}")
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      command -v powershell.exe >/dev/null 2>&1 && speaker=(powershell.exe -NoProfile -Command
        'Add-Type -AssemblyName System.Speech; $s=New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Speak([Console]::In.ReadToEnd())')
      ;;
  esac
fi

# Kokoro (optional neural voices) speaks first; the platform speaker above
# becomes its fallback for when the Kokoro server can't start or answer.
if use_kokoro; then
  speaker=("$TTS_KOKORO_HOME/venv/bin/python" "$TTS_KOKORO_HOME/tts_kokoro_say.py"
           --lang "${TTS_LANG_CODE:-en}" --voice "$(kokoro_voice "$TTS_LANG_CODE" "$(tts_gender)")"
           --speed "$TTS_KOKORO_SPEED" -- ${speaker[@]+"${speaker[@]}"})
fi
[ ${#speaker[@]} -eq 0 ] && exit 0

# --- interrupt previous speech ---------------------------------------------
if [ -f "$TTS_PID_FILE" ]; then
  old_pid="$(cat "$TTS_PID_FILE" 2>/dev/null)"
  [ -n "$old_pid" ] && kill "$old_pid" >/dev/null 2>&1
  rm -f "$TTS_PID_FILE"
fi

# --- speak in the background ------------------------------------------------
mkdir -p "$(dirname "$TTS_PID_FILE")"
printf '%s' "$speech" | "${speaker[@]}" >/dev/null 2>&1 &
echo $! > "$TTS_PID_FILE"
disown 2>/dev/null || true

exit 0
