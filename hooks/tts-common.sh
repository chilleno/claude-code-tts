#!/usr/bin/env bash
# tts-common.sh — shared helpers for the claude-tts hooks.
# Sourced by tts-prompt-hook.sh and tts-stop-hook.sh; not executed directly.

# The Claude config dir is wherever these scripts are installed
# (<config>/hooks/tts-common.sh), so multiple instances via CLAUDE_CONFIG_DIR
# (e.g. ~/.claude-personal, ~/.claude-even) each get their own state.
_TTS_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TTS_CONFIG_DIR="$(dirname "$_TTS_COMMON_DIR")"

# State flag: file present = TTS on. Overridable for tests.
TTS_FLAG="${CLAUDE_TTS_FLAG:-$_TTS_CONFIG_DIR/tts-enabled}"
# PID of the currently-speaking process (so a new reply can interrupt it).
TTS_PID_FILE="${CLAUDE_TTS_PID_FILE:-$_TTS_CONFIG_DIR/tts-speech.pid}"

# json_get FIELD < json-on-stdin
# Prints the top-level string FIELD, or nothing if absent/unparsable.
# Prefers jq, falls back to python3, then node (always present with Claude Code).
json_get() {
  local field="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
try:
    v = json.load(sys.stdin).get(sys.argv[1])
    if isinstance(v, str):
        sys.stdout.write(v)
except Exception:
    pass
' "$field" 2>/dev/null
  elif command -v node >/dev/null 2>&1; then
    node -e '
let d = "";
process.stdin.on("data", c => d += c);
process.stdin.on("end", () => {
  try {
    const v = JSON.parse(d)[process.argv[1]];
    if (typeof v === "string") process.stdout.write(v);
  } catch (e) {}
});
' "$field" 2>/dev/null
  fi
}

tts_is_on() { [ -f "$TTS_FLAG" ]; }
