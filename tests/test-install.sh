# test-install.sh — install.sh / uninstall.sh behavior against temp HOME.
# Sourced by run-tests.sh (assert + fresh_home available).

INSTALL="$REPO_DIR/install.sh"
UNINSTALL="$REPO_DIR/uninstall.sh"

jsonq() { # jsonq FILE PY-EXPR — evaluate expression against parsed settings `s`
  python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))
print(eval(sys.argv[2]))
' "$1" "$2"
}

# --- fresh HOME: settings created with both hooks ---------------------------
fresh_home
SETTINGS="$HOME/.claude/settings.json"
bash "$INSTALL" >/dev/null 2>&1
assert "install: exit 0"             [ $? -eq 0 ]
assert "install: settings created"   [ -f "$SETTINGS" ]
assert "install: valid json"         python3 -m json.tool "$SETTINGS" >/dev/null
assert "install: prompt hook"        grep -q "tts-prompt-hook.sh" "$SETTINGS"
assert "install: stop hook"          grep -q "tts-stop-hook.sh" "$SETTINGS"
assert "install: scripts copied"     [ -x "$HOME/.claude/hooks/tts-prompt-hook.sh" ]
assert "install: common copied"      [ -f "$HOME/.claude/hooks/tts-common.sh" ]
assert "install: toggle copied"      [ -x "$HOME/.claude/hooks/tts-toggle.sh" ]
assert "install: /tts command"       [ -f "$HOME/.claude/commands/tts.md" ]

# --- idempotent: run twice, no duplicates -----------------------------------
before="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$SETTINGS")"
bash "$INSTALL" >/dev/null 2>&1
after="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$SETTINGS")"
assert "install: idempotent"         [ "$before" = "$after" ]
n="$(jsonq "$SETTINGS" 'len(s["hooks"]["UserPromptSubmit"])')"
assert "install: one prompt group"   [ "$n" = "1" ]

# --- existing settings preserved --------------------------------------------
fresh_home
SETTINGS="$HOME/.claude/settings.json"
cat > "$SETTINGS" <<'EOF'
{
  "model": "opus",
  "env": {"FOO": "bar"},
  "hooks": {
    "UserPromptSubmit": [
      {"matcher": "", "hooks": [{"type": "command", "command": "/other/hook.sh"}]}
    ],
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "/other/pre.sh"}]}
    ]
  }
}
EOF
bash "$INSTALL" >/dev/null 2>&1
assert "merge: model kept"           [ "$(jsonq "$SETTINGS" 's["model"]')" = "opus" ]
assert "merge: env kept"             [ "$(jsonq "$SETTINGS" 's["env"]["FOO"]')" = "bar" ]
assert "merge: foreign hook kept"    grep -q "/other/hook.sh" "$SETTINGS"
assert "merge: pretooluse kept"      grep -q "/other/pre.sh" "$SETTINGS"
assert "merge: ours added"           grep -q "tts-prompt-hook.sh" "$SETTINGS"
assert "merge: backup made"          bash -c 'ls "$HOME/.claude/"settings.json.bak-* >/dev/null 2>&1'

# --- invalid JSON refused, file untouched -----------------------------------
fresh_home
SETTINGS="$HOME/.claude/settings.json"
echo '{broken' > "$SETTINGS"
bash "$INSTALL" >/dev/null 2>&1
rc=$?
assert "invalid json: non-zero exit" [ "$rc" -ne 0 ]
assert "invalid json: untouched"     grep -q '{broken' "$SETTINGS"

# --- uninstall --------------------------------------------------------------
fresh_home
SETTINGS="$HOME/.claude/settings.json"
cat > "$SETTINGS" <<'EOF'
{"model": "opus", "hooks": {"Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "/other/stop.sh"}]}]}}
EOF
bash "$INSTALL" >/dev/null 2>&1
touch "$HOME/.claude/tts-enabled" "$HOME/.claude/tts-speech.pid" "$HOME/.claude/tts-voice"
bash "$UNINSTALL" >/dev/null 2>&1
assert "uninstall: exit 0"           [ $? -eq 0 ]
assert "uninstall: ours gone"        bash -c '! grep -q "tts-prompt-hook.sh" "$1"' _ "$SETTINGS"
assert "uninstall: ours stop gone"   bash -c '! grep -q "tts-stop-hook.sh" "$1"' _ "$SETTINGS"
assert "uninstall: foreign kept"     grep -q "/other/stop.sh" "$SETTINGS"
assert "uninstall: model kept"       [ "$(jsonq "$SETTINGS" 's["model"]')" = "opus" ]
assert "uninstall: valid json"       python3 -m json.tool "$SETTINGS" >/dev/null
assert "uninstall: scripts removed"  [ ! -f "$HOME/.claude/hooks/tts-prompt-hook.sh" ]
assert "uninstall: flag removed"     [ ! -f "$HOME/.claude/tts-enabled" ]
assert "uninstall: pid removed"      [ ! -f "$HOME/.claude/tts-speech.pid" ]
assert "uninstall: voice removed"    [ ! -f "$HOME/.claude/tts-voice" ]

# empty groups pruned: no lingering empty UserPromptSubmit array
n="$(jsonq "$SETTINGS" '"UserPromptSubmit" in s.get("hooks", {})')"
assert "uninstall: empty event gone" [ "$n" = "False" ]

# --- uninstall when never installed: clean no-op ----------------------------
fresh_home
bash "$UNINSTALL" >/dev/null 2>&1
assert "uninstall fresh: exit 0"     [ $? -eq 0 ]

# --- CLAUDE_CONFIG_DIR honored (multi-instance setups) ----------------------
fresh_home
ALT="$HOME/.claude-personal"
CLAUDE_CONFIG_DIR="$ALT" bash "$INSTALL" >/dev/null 2>&1
assert "configdir: settings there"   [ -f "$ALT/settings.json" ]
assert "configdir: hooks there"      [ -x "$ALT/hooks/tts-prompt-hook.sh" ]
assert "configdir: command there"    [ -f "$ALT/commands/tts.md" ]
assert "configdir: default untouched" [ ! -f "$HOME/.claude/settings.json" ]
CLAUDE_CONFIG_DIR="$ALT" bash "$UNINSTALL" >/dev/null 2>&1
assert "configdir: uninstall cleans" [ ! -f "$ALT/hooks/tts-prompt-hook.sh" ]

# --- --dir flag -------------------------------------------------------------
fresh_home
ALT="$HOME/.claude-dirflag"
bash "$INSTALL" --dir "$ALT" >/dev/null 2>&1
assert "dirflag: installed there"    [ -x "$ALT/hooks/tts-prompt-hook.sh" ]
assert "dirflag: default untouched"  [ ! -f "$HOME/.claude/settings.json" ]
bash "$UNINSTALL" --dir "$ALT" >/dev/null 2>&1
assert "dirflag: uninstall cleans"   [ ! -f "$ALT/hooks/tts-prompt-hook.sh" ]

# --- multi-instance detection + interactive selection -----------------------
fresh_home
mkdir -p "$HOME/.claude-work"
echo '{}' > "$HOME/.claude/settings.json"
echo '{}' > "$HOME/.claude-work/settings.json"
# pick only option 2 (~/.claude-work)
printf '2\n' | CLAUDE_TTS_ASSUME_TTY=1 bash "$INSTALL" >"$HOME/menu-out.txt" 2>&1
assert "detect: menu shown"          grep -q "Multiple Claude instances" "$HOME/menu-out.txt"
assert "detect: option listed"       grep -q ".claude-work" "$HOME/menu-out.txt"
assert "detect: chosen installed"    [ -x "$HOME/.claude-work/hooks/tts-prompt-hook.sh" ]
assert "detect: other skipped"       [ ! -f "$HOME/.claude/hooks/tts-prompt-hook.sh" ]
# 'all' installs into every candidate
printf 'all\n' | CLAUDE_TTS_ASSUME_TTY=1 bash "$INSTALL" >/dev/null 2>&1
assert "detect: all -> default too"  [ -x "$HOME/.claude/hooks/tts-prompt-hook.sh" ]

# rc-file alias detection: CLAUDE_CONFIG_DIR=$HOME/... in .zshrc
fresh_home
mkdir -p "$HOME/.claude-rc"
echo '{}' > "$HOME/.claude-rc/settings.json"
rm -rf "$HOME/.claude"
echo 'alias jarvis="CLAUDE_CONFIG_DIR=$HOME/.claude-rc claude"' > "$HOME/.zshrc"
printf '1\n' | CLAUDE_TTS_ASSUME_TTY=1 bash "$INSTALL" >"$HOME/menu-out.txt" 2>&1
assert "detect: rc alias found"      [ -x "$HOME/.claude-rc/hooks/tts-prompt-hook.sh" ]

# single instance: no menu, installs directly
fresh_home
CLAUDE_TTS_ASSUME_TTY=1 bash "$INSTALL" >"$HOME/menu-out.txt" 2>&1 </dev/null
assert "detect: single no menu"      bash -c '! grep -q "Multiple" "$1"' _ "$HOME/menu-out.txt"
assert "detect: single installed"    [ -x "$HOME/.claude/hooks/tts-prompt-hook.sh" ]

# --- installed hooks derive per-config state (no env override) --------------
fresh_home
bash "$INSTALL" >/dev/null 2>&1
unset CLAUDE_TTS_FLAG CLAUDE_TTS_PID_FILE
printf '{"prompt":"tts on"}' | bash "$HOME/.claude/hooks/tts-prompt-hook.sh" 2>/dev/null
assert "derived flag: exit 2"        [ $? -eq 2 ]
assert "derived flag: in config dir" [ -f "$HOME/.claude/tts-enabled" ]
