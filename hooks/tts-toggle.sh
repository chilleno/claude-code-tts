#!/usr/bin/env bash
# tts-toggle.sh — flip/report the TTS flag. Shared by the prompt hook and the
# /tts slash command.
#
# Usage: tts-toggle.sh [on|off|status]   (no argument = toggle)
# Prints the resulting state to stdout.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tts-common.sh
. "$SCRIPT_DIR/tts-common.sh"

turn_on()  { mkdir -p "$(dirname "$TTS_FLAG")"; touch "$TTS_FLAG"; echo "🔊 TTS on"; }
turn_off() { rm -f "$TTS_FLAG"; echo "🔇 TTS off"; }

case "${1:-}" in
  on)  turn_on ;;
  off) turn_off ;;
  status)
    if tts_is_on; then echo "🔊 TTS is on"; else echo "🔇 TTS is off"; fi
    ;;
  ""|toggle)
    if tts_is_on; then turn_off; else turn_on; fi
    ;;
  *)
    echo "usage: tts-toggle.sh [on|off|status]" >&2
    exit 1
    ;;
esac
