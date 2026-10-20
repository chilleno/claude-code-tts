# test-prompt-hook.sh — UserPromptSubmit hook behavior.
# Sourced by run-tests.sh (assert + fresh_home available).

HOOK="$REPO_DIR/hooks/tts-prompt-hook.sh"

run_hook() { # run_hook PROMPT-JSON; sets rc, out, err
  local json="$1"
  out="$(printf '%s' "$json" | bash "$HOOK" 2>"$HOME/err.txt")"
  rc=$?
  err="$(cat "$HOME/err.txt")"
}

prompt_json() { # prompt_json TEXT
  printf '{"hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1"
}

fresh_home
FLAG="$HOME/.claude/tts-enabled"

# tts on: creates flag, exit 2, confirmation on stderr, nothing on stdout
run_hook "$(prompt_json 'tts on')"
assert "tts on -> exit 2"            [ "$rc" -eq 2 ]
assert "tts on -> flag created"      [ -f "$FLAG" ]
assert "tts on -> stderr confirms"   grep -q "TTS on" "$HOME/err.txt"
assert "tts on -> stdout empty"      [ -z "$out" ]

# normal prompt with flag on: instruction injected, exit 0
run_hook "$(prompt_json 'what time is it')"
assert "on: normal prompt exit 0"    [ "$rc" -eq 0 ]
assert "on: instruction injected"    grep -q "text-to-speech" <<<"$out"

# tts status while on
run_hook "$(prompt_json 'tts status')"
assert "status on -> exit 2"         [ "$rc" -eq 2 ]
assert "status on -> reports on"     grep -q "TTS is on" "$HOME/err.txt"
assert "status -> flag untouched"    [ -f "$FLAG" ]

# tts off: removes flag, exit 2
run_hook "$(prompt_json 'tts off')"
assert "tts off -> exit 2"           [ "$rc" -eq 2 ]
assert "tts off -> flag removed"     [ ! -f "$FLAG" ]
assert "tts off -> stderr confirms"  grep -q "TTS off" "$HOME/err.txt"

# normal prompt with flag off: no injection
run_hook "$(prompt_json 'what time is it')"
assert "off: normal prompt exit 0"   [ "$rc" -eq 0 ]
assert "off: stdout empty"           [ -z "$out" ]

# tts status while off
run_hook "$(prompt_json 'tts status')"
assert "status off -> reports off"   grep -q "TTS is off" "$HOME/err.txt"

# bare tts toggles on, then off
run_hook "$(prompt_json 'tts')"
assert "bare tts -> exit 2"          [ "$rc" -eq 2 ]
assert "bare tts -> toggled on"      [ -f "$FLAG" ]
run_hook "$(prompt_json 'tts')"
assert "bare tts -> toggled off"     [ ! -f "$FLAG" ]

# case-insensitive + surrounding whitespace
run_hook "$(prompt_json '  TTS ON  ')"
assert "TTS ON (caps/ws) -> exit 2"  [ "$rc" -eq 2 ]
assert "TTS ON -> flag created"      [ -f "$FLAG" ]
rm -f "$FLAG"

# 'tts' inside a sentence must NOT be intercepted
run_hook "$(prompt_json 'how does tts work on macos')"
assert "tts-in-sentence not caught"  [ "$rc" -eq 0 ]

# legacy field name prompt_text also works
out="$(printf '{"prompt_text":"tts on"}' | bash "$HOOK" 2>/dev/null)"; rc=$?
assert "prompt_text field -> exit 2" [ "$rc" -eq 2 ]
assert "prompt_text -> flag created" [ -f "$FLAG" ]
rm -f "$FLAG"

# language: tts lang es intercepted, stored, injected; tts lang off clears
run_hook "$(prompt_json 'tts lang es')"
assert "lang es -> exit 2"           [ "$rc" -eq 2 ]
assert "lang es -> stored"           grep -q "es" "$HOME/.claude/tts-lang"
assert "lang es -> confirms Spanish" grep -q "Spanish" "$HOME/err.txt"
run_hook "$(prompt_json 'tts lang')"
assert "lang query -> exit 2"        [ "$rc" -eq 2 ]
assert "lang query -> reports es"    grep -q "es" "$HOME/err.txt"
touch "$HOME/.claude/tts-enabled"
run_hook "$(prompt_json 'hola')"
assert "lang: injection has Spanish" grep -q "Reply entirely in Spanish" <<<"$out"
run_hook "$(prompt_json 'tts lang off')"
assert "lang off -> exit 2"          [ "$rc" -eq 2 ]
assert "lang off -> file removed"    [ ! -f "$HOME/.claude/tts-lang" ]
run_hook "$(prompt_json 'hola')"
assert "lang off: no lang line"      ! grep -q "Reply entirely" <<<"$out"
run_hook "$(prompt_json 'tts lang notacode')"
assert "lang invalid -> exit 2"      [ "$rc" -eq 2 ]
assert "lang invalid -> not stored"  [ ! -f "$HOME/.claude/tts-lang" ]
rm -f "$HOME/.claude/tts-enabled"

# voice: tts voice NAME (case-insensitive match on macOS), query, off, voices, region lang
run_hook "$(prompt_json 'tts voice paulina')"
assert "voice set -> exit 2"         [ "$rc" -eq 2 ]
assert "voice set -> stored"         grep -qi "paulina" "$HOME/.claude/tts-voice"
run_hook "$(prompt_json 'tts voice')"
assert "voice query -> exit 2"       [ "$rc" -eq 2 ]
assert "voice query -> reports"      grep -qi "paulina" "$HOME/err.txt"
run_hook "$(prompt_json 'tts voice off')"
assert "voice off -> cleared"        [ ! -f "$HOME/.claude/tts-voice" ]
run_hook "$(prompt_json 'tts voices')"
assert "voices -> exit 2"            [ "$rc" -eq 2 ]
# voices listing filtered by language, with 'all' escape hatch (macOS only)
if [ "$(uname -s)" = Darwin ]; then
  echo es-mx > "$HOME/.claude/tts-lang"
  run_hook "$(prompt_json 'tts voices')"
  assert "voices: filtered header"     grep -q "showing only your selected language (es-mx)" "$HOME/err.txt"
  assert "voices: Paulina listed"      grep -q "Paulina" "$HOME/err.txt"
  assert "voices: Samantha hidden"     ! grep -q "Samantha" "$HOME/err.txt"
  assert "voices: auto marked"         grep -q "★ Paulina" "$HOME/err.txt"
  assert "voices: region label"        grep -q "Spanish (Mexico)" "$HOME/err.txt"
  run_hook "$(prompt_json 'tts voices all')"
  assert "voices all: everything"      grep -q "Samantha" "$HOME/err.txt"
  assert "voices all: novelty tagged"  grep -q "Eddy.*\[novelty\]" "$HOME/err.txt"
  # mismatched voice warns
  run_hook "$(prompt_json 'tts voice samantha')"
  assert "voice mismatch warns"        grep -q "warning:.*English" "$HOME/err.txt"
  run_hook "$(prompt_json 'tts voice off')"
  rm -f "$HOME/.claude/tts-lang"
fi
run_hook "$(prompt_json 'tts lang es-MX')"
assert "lang region -> exit 2"       [ "$rc" -eq 2 ]
assert "lang region -> stored lower" grep -q "^es-mx$" "$HOME/.claude/tts-lang"
rm -f "$HOME/.claude/tts-lang"

# toggle script directly: status reports engine detection line
tstat="$(bash "$REPO_DIR/hooks/tts-toggle.sh" status)"
assert "toggle: status exit 0"       [ $? -eq 0 ]
assert "toggle: engine reported"     grep -q "speech engine:" <<<"$tstat"

# malformed JSON: exit 0, silent
out="$(printf 'this is not json' | bash "$HOOK" 2>/dev/null)"; rc=$?
assert "malformed json -> exit 0"    [ "$rc" -eq 0 ]
assert "malformed json -> silent"    [ -z "$out" ]
