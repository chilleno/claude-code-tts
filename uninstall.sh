#!/usr/bin/env bash
# uninstall.sh — remove claude-tts cleanly.
#
# Removes the two hook entries from ~/.claude/settings.json (backup first),
# deletes the installed hook scripts, the flag file, and the speech pid file.
# Leaves every other setting and every foreign hook untouched. Idempotent.
#
# --kokoro also deletes the shared Kokoro voices folder (used by every
# instance, so it is kept unless asked).

set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
KOKORO=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) [ $# -ge 2 ] || { echo "error: --dir needs a path" >&2; exit 1; }
           CLAUDE_DIR="$2"; shift 2 ;;
    --kokoro) KOKORO=1; shift ;;
    *) echo "error: unknown option $1 (try --dir PATH or --kokoro)" >&2; exit 1 ;;
  esac
done
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"

PROMPT_CMD="$HOOKS_DIR/tts-prompt-hook.sh"
STOP_CMD="$HOOKS_DIR/tts-stop-hook.sh"

if command -v python3 >/dev/null 2>&1; then
  JSON_RUNNER=python3
elif command -v node >/dev/null 2>&1; then
  JSON_RUNNER=node
else
  echo "error: need python3 or node to edit settings.json" >&2
  exit 1
fi

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
  if [ "$JSON_RUNNER" = python3 ]; then
    python3 - "$SETTINGS" "$PROMPT_CMD" "$STOP_CMD" <<'PYEOF'
import json, sys

settings_path, prompt_cmd, stop_cmd = sys.argv[1], sys.argv[2], sys.argv[3]
ours = {prompt_cmd, stop_cmd}

with open(settings_path) as f:
    raw = f.read()
try:
    settings = json.loads(raw) if raw.strip() else {}
except json.JSONDecodeError as e:
    sys.exit(f"error: {settings_path} is not valid JSON ({e}); fix it first")

hooks = settings.get("hooks", {})
for event in ("UserPromptSubmit", "Stop"):
    groups = hooks.get(event)
    if not groups:
        continue
    for g in groups:
        g["hooks"] = [h for h in g.get("hooks", []) if h.get("command") not in ours]
    hooks[event] = [g for g in groups if g.get("hooks")]
    if not hooks[event]:
        del hooks[event]
if "hooks" in settings and not settings["hooks"]:
    del settings["hooks"]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print("hook entries removed from settings.json")
PYEOF
  else
    node - "$SETTINGS" "$PROMPT_CMD" "$STOP_CMD" <<'JSEOF'
const fs = require("fs");
const [settingsPath, promptCmd, stopCmd] = process.argv.slice(2);
const ours = new Set([promptCmd, stopCmd]);

let settings = {};
const raw = fs.readFileSync(settingsPath, "utf8");
if (raw.trim()) {
  try { settings = JSON.parse(raw); }
  catch (e) { console.error(`error: ${settingsPath} is not valid JSON (${e.message}); fix it first`); process.exit(1); }
}

const hooks = settings.hooks ?? {};
for (const event of ["UserPromptSubmit", "Stop"]) {
  if (!hooks[event]) continue;
  for (const g of hooks[event]) g.hooks = (g.hooks ?? []).filter(h => !ours.has(h.command));
  hooks[event] = hooks[event].filter(g => g.hooks.length > 0);
  if (hooks[event].length === 0) delete hooks[event];
}
if (settings.hooks && Object.keys(settings.hooks).length === 0) delete settings.hooks;

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
console.log("hook entries removed from settings.json");
JSEOF
  fi
fi

rm -f "$HOOKS_DIR/tts-common.sh" "$HOOKS_DIR/tts-toggle.sh" \
      "$HOOKS_DIR/tts-prompt-hook.sh" "$HOOKS_DIR/tts-stop-hook.sh"
rm -f "$CLAUDE_DIR/commands/tts.md" "$CLAUDE_DIR/tts-enabled" "$CLAUDE_DIR/tts-speech.pid" "$CLAUDE_DIR/tts-lang" "$CLAUDE_DIR/tts-voice" "$CLAUDE_DIR/tts-gender"

echo "claude-tts uninstalled."

KOKORO_HOME="${CLAUDE_TTS_KOKORO_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-tts/kokoro}"
if [ "$KOKORO" = 1 ]; then
  pkill -f "$KOKORO_HOME/tts_kokoro_server.py" 2>/dev/null || true
  if [ -f "$KOKORO_HOME/tts_kokoro_server.py" ] || [ -d "$KOKORO_HOME/venv" ]; then
    rm -rf "$KOKORO_HOME"   # only a folder that is recognisably ours
    rmdir "$(dirname "$KOKORO_HOME")" 2>/dev/null || true
    echo "Kokoro voices removed ($KOKORO_HOME)."
  elif [ -e "$KOKORO_HOME" ]; then
    echo "warning: $KOKORO_HOME doesn't look like a claude-tts Kokoro install — left untouched" >&2
  fi
elif [ -d "$KOKORO_HOME" ]; then
  echo "Kokoro voices kept at $KOKORO_HOME (shared by all instances) — remove with: ./uninstall.sh --kokoro"
fi
