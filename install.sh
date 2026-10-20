#!/usr/bin/env bash
# install.sh — install claude-tts into one or more Claude Code config dirs.
#
# Target selection, in order:
#   1. --dir PATH (repeatable)          → install into those, no questions
#   2. $CLAUDE_CONFIG_DIR set           → install there, no questions
#   3. interactive terminal             → detect instances (~/.claude,
#      ~/.claude-*, CLAUDE_CONFIG_DIR=… in shell rc files) and ask
#   4. non-interactive (CI, piped)      → ~/.claude
#
# Per target it touches (and nothing else):
#   hooks/tts-common.sh, tts-toggle.sh, tts-prompt-hook.sh, tts-stop-hook.sh
#   commands/tts.md           (the /tts slash command)
#   settings.json             (merged, timestamped backup made first)
#
# Idempotent: run it as often as you like — never duplicates hook entries.
#
# --kokoro also installs the optional Kokoro neural voices (≈2 GB, one time,
# shared by all instances; see kokoro/install-kokoro.sh). Re-run with
# --kokoro any time to add them later.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# --- target selection -------------------------------------------------------

TARGETS=()
KOKORO=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) [ $# -ge 2 ] || { echo "error: --dir needs a path" >&2; exit 1; }
           TARGETS+=("$2"); shift 2 ;;
    --kokoro) KOKORO=1; shift ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: unknown option $1 (try --dir PATH or --kokoro)" >&2; exit 1 ;;
  esac
done

# detect_instances — print candidate config dirs, one per line.
detect_instances() {
  local d rc
  [ -d "$HOME/.claude" ] && echo "$HOME/.claude"
  for d in "$HOME"/.claude-*; do
    # only dirs that look like Claude config dirs (have settings or history)
    [ -d "$d" ] || continue
    if [ -f "$d/settings.json" ] || [ -f "$d/config.json" ] || [ -d "$d/projects" ]; then
      echo "$d"
    fi
  done
  # aliases / exports in shell rc files: CLAUDE_CONFIG_DIR=/some/path
  for rc in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    [ -f "$rc" ] || continue
    sed -nE 's/.*CLAUDE_CONFIG_DIR=("([^"]+)"|'\''([^'\'']+)'\''|([^ "'\'']+)).*/\2\3\4/p' "$rc"
  done | while IFS= read -r d; do
    case "$d" in \$HOME*) d="$HOME${d#\$HOME}" ;; "~"*) d="$HOME${d#\~}" ;; esac
    [ -d "$d" ] && echo "$d"
  done
}

if [ ${#TARGETS[@]} -eq 0 ]; then
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    TARGETS=("$CLAUDE_CONFIG_DIR")
  elif [ -t 0 ] || [ -n "${CLAUDE_TTS_ASSUME_TTY:-}" ]; then
    # unique, order-preserving candidate list
    CANDIDATES=()
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      dup=0; for c in ${CANDIDATES[@]+"${CANDIDATES[@]}"}; do [ "$c" = "$d" ] && dup=1 && break; done
      [ "$dup" = 0 ] && CANDIDATES+=("$d")
    done < <(detect_instances)
    [ ${#CANDIDATES[@]} -eq 0 ] && CANDIDATES=("$HOME/.claude")

    if [ ${#CANDIDATES[@]} -eq 1 ]; then
      TARGETS=("${CANDIDATES[0]}")
      echo "Installing into detected Claude config dir: ${TARGETS[0]}"
    else
      echo "Multiple Claude instances detected:"
      i=1
      for c in "${CANDIDATES[@]}"; do echo "  $i) $c"; i=$((i+1)); done
      echo "Choose targets: numbers separated by spaces, 'all', or a custom path."
      printf "> "
      IFS= read -r answer
      if [ "$answer" = "all" ]; then
        TARGETS=("${CANDIDATES[@]}")
      else
        for tok in $answer; do
          case "$tok" in
            ''|*[!0-9]*) TARGETS+=("$tok") ;;  # custom path
            *) idx=$((tok-1))
               [ "$idx" -ge 0 ] && [ "$idx" -lt ${#CANDIDATES[@]} ] \
                 && TARGETS+=("${CANDIDATES[$idx]}") \
                 || { echo "error: no option $tok" >&2; exit 1; } ;;
          esac
        done
      fi
      [ ${#TARGETS[@]} -eq 0 ] && { echo "nothing selected, aborting" >&2; exit 1; }
    fi
  else
    TARGETS=("$HOME/.claude")
  fi
fi

# --- installation -----------------------------------------------------------

install_into() {
  local claude_dir="$1"
  local hooks_dir="$claude_dir/hooks"
  local settings="$claude_dir/settings.json"

  mkdir -p "$hooks_dir" "$claude_dir/commands"
  local f
  for f in tts-common.sh tts-toggle.sh tts-prompt-hook.sh tts-stop-hook.sh; do
    cp "$REPO_DIR/hooks/$f" "$hooks_dir/$f"
    chmod +x "$hooks_dir/$f"
  done
  cp "$REPO_DIR/commands/tts.md" "$claude_dir/commands/tts.md"

  # Backup existing settings before touching them.
  if [ -f "$settings" ]; then
    cp "$settings" "$settings.bak-$(date +%Y%m%d-%H%M%S)"
  fi

  local prompt_cmd="$hooks_dir/tts-prompt-hook.sh"
  local stop_cmd="$hooks_dir/tts-stop-hook.sh"

  if [ "$JSON_RUNNER" = python3 ]; then
    python3 - "$settings" "$prompt_cmd" "$stop_cmd" <<'PYEOF'
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
    node - "$settings" "$prompt_cmd" "$stop_cmd" <<'JSEOF'
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

  echo "claude-tts v$VERSION installed into $claude_dir"
}

for target in "${TARGETS[@]}"; do
  install_into "$target"
done

if [ "$KOKORO" = 1 ]; then
  bash "$REPO_DIR/kokoro/install-kokoro.sh"
fi

# shellcheck source=hooks/tts-common.sh
. "$REPO_DIR/hooks/tts-common.sh"
if ! kokoro_ready; then
  echo "Tip: for natural neural voices (English + Spanish, free, offline), run: ./install.sh --kokoro"
fi
if [ -z "$(tts_engine)" ] && ! kokoro_ready; then
  echo "warning: no speech engine found — toggle and brief-answer mode will work, but replies won't be spoken." >&2
  echo "         Linux: install speech-dispatcher (spd-say) or espeak. Windows: use Git Bash (PowerShell speech)." >&2
fi

echo "Restart your Claude Code session, then type:  tts on   (or /tts on)"
