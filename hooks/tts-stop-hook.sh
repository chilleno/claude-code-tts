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
# Both can also be overridden per-session via environment variables.
# ---------------------------------------------------------------------------
TTS_VOICE="${TTS_VOICE:-}"
TTS_RATE="${TTS_RATE:-200}"

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

# --- pick a speaker per platform -------------------------------------------
# speak() reads the text on stdin. Add a platform: add a case branch.
speaker=()
if [ -n "$TTS_SAY_CMD" ]; then
  speaker=("$TTS_SAY_CMD")
  [ -n "$TTS_VOICE" ] && speaker+=(-v "$TTS_VOICE")
  speaker+=(-r "$TTS_RATE")
else
  case "$(uname -s)" in
    Darwin)
      command -v say >/dev/null 2>&1 || exit 0
      speaker=(say)
      [ -n "$TTS_VOICE" ] && speaker+=(-v "$TTS_VOICE")
      speaker+=(-r "$TTS_RATE")
      ;;
    Linux)
      if command -v spd-say >/dev/null 2>&1; then
        speaker=(spd-say -w -e)   # -e reads stdin, -w waits (we background anyway)
      elif command -v espeak >/dev/null 2>&1; then
        speaker=(espeak --stdin)
      else
        exit 0
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      command -v powershell.exe >/dev/null 2>&1 || exit 0
      speaker=(powershell.exe -NoProfile -Command
        'Add-Type -AssemblyName System.Speech; $s=New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Speak([Console]::In.ReadToEnd())')
      ;;
    *) exit 0 ;;
  esac
fi

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
