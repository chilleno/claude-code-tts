# test-kokoro.sh — optional Kokoro engine: voice routing, man/woman switch, fallback.
# Sourced by run-tests.sh (assert + fresh_home + fake_kokoro available).

STOP="$REPO_DIR/hooks/tts-stop-hook.sh"
PROMPT="$REPO_DIR/hooks/tts-prompt-hook.sh"
TOGGLE="$REPO_DIR/hooks/tts-toggle.sh"

speak() { # speak TEXT — run the Stop hook, wait for whichever stub got the text
  rm -f "$HOME/kokoro.log" "$HOME/say.log"
  printf '{"hook_event_name":"Stop","last_assistant_message":"%s"}' "$1" \
    | TTS_SAY_CMD="$HOME/stub-bin/say" bash "$STOP" >/dev/null 2>&1
  for _ in $(seq 30); do [ -s "$HOME/kokoro.log" ] || [ -s "$HOME/say.log" ] && break; sleep 0.1; done
}
kargs() { grep '^ARGS:' "$HOME/kokoro.log" 2>/dev/null; }
prompt() { # prompt TEXT — run the prompt hook; sets rc, err
  printf '{"hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1" | bash "$PROMPT" >/dev/null 2>"$HOME/err.txt"
  rc=$?; err="$(cat "$HOME/err.txt")"
}

fresh_home
touch "$HOME/.claude/tts-enabled"

# --- not installed: say as before, man/woman points to the installer ---------
speak "plain reply"
assert "no kokoro: say speaks"            grep -q "STDIN:plain reply" "$HOME/say.log"
out="$(bash "$TOGGLE" voice man)"
assert "no kokoro: voice man saved"       [ "$(cat "$HOME/.claude/tts-gender")" = male ]
assert "no kokoro: hint to install"       grep -q "install.sh --kokoro" <<<"$out"
rm -f "$HOME/.claude/tts-gender"

# --- installed: Kokoro speaks, say is the fallback -----------------------------
fake_kokoro
speak "hello there"
assert "kokoro: used when installed"      grep -q "STDIN:hello there" "$HOME/kokoro.log"
assert "kokoro: say not called directly"  [ ! -s "$HOME/say.log" ]
assert "kokoro: default woman (Heart)"    grep -q -- "--voice af_heart" <<<"$(kargs)"
assert "kokoro: default lang en"          grep -q -- "--lang en " <<<"$(kargs)"
assert "kokoro: say fallback after --"    grep -q -- "-- $HOME/stub-bin/say -r 200" <<<"$(kargs)"
assert "kokoro: status shows engine"      grep -q "speech engine: kokoro" <<<"$(bash "$TOGGLE" status)"

# man / woman via the prompt hook (case-insensitive, never reaches the model)
prompt "tts voice Man"
assert "voice man: exit 2"                [ "$rc" -eq 2 ]
assert "voice man: confirms Michael"      grep -q "Michael (man, Kokoro)" <<<"$err"
speak "hi"
assert "voice man: Michael speaks"        grep -q -- "--voice am_michael" <<<"$(kargs)"

bash "$TOGGLE" lang es >/dev/null
speak "hola"
assert "es + man: Alex"                   grep -q -- "--voice em_alex" <<<"$(kargs)"
prompt "tts voice woman"
assert "voice woman: confirms Dora"       grep -q "Dora (woman, Kokoro)" <<<"$err"
bash "$TOGGLE" lang es-mx >/dev/null
speak "hola"
assert "es-mx + woman: Dora"              grep -q -- "--voice ef_dora" <<<"$(kargs)"
assert "es-mx: region passed through"     grep -q -- "--lang es-mx " <<<"$(kargs)"
for w in male female men women; do
  assert "voice $w accepted"              bash "$TOGGLE" voice "$w"
done

# languages Kokoro has no voices for stay on say
bash "$TOGGLE" lang fr >/dev/null
speak "bonjour"
assert "fr: say speaks"                   grep -q "STDIN:bonjour" "$HOME/say.log"
assert "fr: kokoro not called"            [ ! -s "$HOME/kokoro.log" ]
assert "fr: status explains"              grep -q "has no French voices" <<<"$(bash "$TOGGLE" status)"
bash "$TOGGLE" lang off >/dev/null

# an Apple voice picked by name wins; man/woman hands back to Kokoro
printf 'Samantha\n' > "$HOME/.claude/tts-voice"
speak "apple"
assert "apple voice: say speaks"          grep -q "STDIN:apple" "$HOME/say.log"
assert "apple voice: kokoro skipped"      [ ! -s "$HOME/kokoro.log" ]
bash "$TOGGLE" voice woman >/dev/null
assert "voice woman: apple pick cleared"  [ ! -f "$HOME/.claude/tts-voice" ]
speak "back"
assert "voice woman: kokoro again"        grep -q "STDIN:back" "$HOME/kokoro.log"

bash "$TOGGLE" voice off >/dev/null
assert "voice off: gender cleared"        [ ! -f "$HOME/.claude/tts-gender" ]

# --- uninstall --kokoro --------------------------------------------------------
bash "$REPO_DIR/uninstall.sh" >/dev/null 2>&1
assert "uninstall: kokoro kept by default" [ -d "$CLAUDE_TTS_KOKORO_HOME" ]
touch "$CLAUDE_TTS_KOKORO_HOME/tts_kokoro_server.py"
bash "$REPO_DIR/uninstall.sh" --kokoro >/dev/null 2>&1
assert "uninstall --kokoro: removed"      [ ! -e "$CLAUDE_TTS_KOKORO_HOME" ]
mkdir -p "$HOME/not-ours" && touch "$HOME/not-ours/keep"
CLAUDE_TTS_KOKORO_HOME="$HOME/not-ours" bash "$REPO_DIR/uninstall.sh" --kokoro >/dev/null 2>&1
assert "uninstall --kokoro: foreign kept" [ -f "$HOME/not-ours/keep" ]
