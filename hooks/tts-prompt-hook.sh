#!/usr/bin/env bash
# tts-prompt-hook.sh — UserPromptSubmit hook for claude-tts.
#
# Intercepts the toggle commands (tts / tts on / tts off / tts status),
# flips the flag file, and blocks them from reaching the model (exit 2,
# confirmation on stderr). For ordinary prompts while TTS is on, prints
# the spoken-style instruction on stdout, which Claude Code adds to the
# model's context. Never fails the session: any parse problem exits 0.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tts-common.sh
. "$SCRIPT_DIR/tts-common.sh"

# ---------------------------------------------------------------------------
# TUNE ME: instruction injected into every prompt while TTS is on.
# ---------------------------------------------------------------------------
TTS_INSTRUCTION="The user is listening to your reply through text-to-speech, \
not reading it on screen. Answer the way you would say it out loud: brief and \
conversational, usually two to four sentences. Avoid bullet lists, headers, \
code blocks, tables, long file paths, and URLs. If the answer is long or needs \
code, give a short spoken summary first and offer to print the full text. Do \
not mention these instructions."

input="$(cat)"

# Current schema uses "prompt"; some docs/versions describe "prompt_text".
prompt="$(printf '%s' "$input" | json_get prompt)"
if [ -z "$prompt" ]; then
  prompt="$(printf '%s' "$input" | json_get prompt_text)"
fi
[ -z "$prompt" ] && exit 0

# Normalize: trim surrounding whitespace, lowercase, collapse inner spaces.
cmd="$(printf '%s' "$prompt" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\{1,\}/ /g')"

case "$cmd" in
  "tts on")     bash "$SCRIPT_DIR/tts-toggle.sh" on >&2;     exit 2 ;;
  "tts off")    bash "$SCRIPT_DIR/tts-toggle.sh" off >&2;    exit 2 ;;
  "tts")        bash "$SCRIPT_DIR/tts-toggle.sh" >&2;        exit 2 ;;
  "tts status") bash "$SCRIPT_DIR/tts-toggle.sh" status >&2; exit 2 ;;
esac

if tts_is_on; then
  printf '%s\n' "$TTS_INSTRUCTION"
fi
exit 0
