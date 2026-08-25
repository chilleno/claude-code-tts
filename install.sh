#!/usr/bin/env bash
# install.sh — install claude-tts hooks into ~/.claude.
#
# Target config dir: $CLAUDE_CONFIG_DIR if set (multi-instance setups),
# else ~/.claude. What it touches inside it (and nothing else):
#   hooks/tts-common.sh, tts-toggle.sh, tts-prompt-hook.sh, tts-stop-hook.sh
#   commands/tts.md           (the /tts slash command)
#   settings.json             (merged, timestamped backup made first)
#
# Idempotent: run it as often as you like — never duplicates hook entries.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"
VERSION="$(cat "$REPO_DIR/VERSION")"

# Pick a JSON-capable interpreter: python3 preferred, node fallback
# (node ships with Claude Code, so one of the two is always there).
if command -v python3 >/dev/null 2>&1; then
  JSON_RUNNER=python3
elif command -v node >/dev/null 2>&1; then
  JSON_RUNNER=node
else
  echo "error: need python3 or node to merge settings.json" >&2
  exit 1
fi

mkdir -p "$HOOKS_DIR" "$CLAUDE_DIR/commands"
for f in tts-common.sh tts-toggle.sh tts-prompt-hook.sh tts-stop-hook.sh; do
  cp "$REPO_DIR/hooks/$f" "$HOOKS_DIR/$f"
  chmod +x "$HOOKS_DIR/$f"
done
cp "$REPO_DIR/commands/tts.md" "$CLAUDE_DIR/commands/tts.md"

# Backup existing settings before touching them.
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
fi

PROMPT_CMD="$HOOKS_DIR/tts-prompt-hook.sh"
STOP_CMD="$HOOKS_DIR/tts-stop-hook.sh"

if [ "$JSON_RUNNER" = python3 ]; then
  python3 - "$SETTINGS" "$PROMPT_CMD" "$STOP_CMD" <<'PYEOF'
import json, os, sys

settings_path, prompt_cmd, stop_cmd = sys.argv[1], sys.argv[2], sys.argv[3]

if os.path.exists(settings_path):
    with open(settings_path) as f:
        raw = f.read()
    try:
        settings = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError as e:
        sys.exit(f"error: {settings_path} is not valid JSON ({e}); fix it first")
    if not isinstance(settings, dict):
        sys.exit(f"error: {settings_path} top level is not an object")
else:
    settings = {}

hooks = settings.setdefault("hooks", {})

def ensure(event, command):
    groups = hooks.setdefault(event, [])
    for g in groups:
        for h in g.get("hooks", []):
            if h.get("command") == command:
                return False  # already installed
    groups.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": command, "timeout": 10}],
    })
    return True

added = ensure("UserPromptSubmit", prompt_cmd) | ensure("Stop", stop_cmd)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("hooks registered" if added else "hooks already registered (no change)")
PYEOF
else
  node - "$SETTINGS" "$PROMPT_CMD" "$STOP_CMD" <<'JSEOF'
const fs = require("fs");
const [settingsPath, promptCmd, stopCmd] = process.argv.slice(2);

let settings = {};
if (fs.existsSync(settingsPath)) {
  const raw = fs.readFileSync(settingsPath, "utf8");
  if (raw.trim()) {
    try { settings = JSON.parse(raw); }
    catch (e) { console.error(`error: ${settingsPath} is not valid JSON (${e.message}); fix it first`); process.exit(1); }
  }
  if (typeof settings !== "object" || Array.isArray(settings) || settings === null) {
    console.error(`error: ${settingsPath} top level is not an object`); process.exit(1);
  }
}

const hooks = settings.hooks ??= {};
function ensure(event, command) {
  const groups = hooks[event] ??= [];
  for (const g of groups)
    for (const h of g.hooks ?? [])
      if (h.command === command) return false;
  groups.push({ matcher: "", hooks: [{ type: "command", command, timeout: 10 }] });
  return true;
}

const added = ensure("UserPromptSubmit", promptCmd) | ensure("Stop", stopCmd);
fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
console.log(added ? "hooks registered" : "hooks already registered (no change)");
JSEOF
fi

echo "claude-tts v$VERSION installed into $CLAUDE_DIR"
echo "Restart your Claude Code session, then type:  tts on   (or /tts on)"
