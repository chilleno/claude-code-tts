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

# malformed JSON: exit 0, silent
out="$(printf 'this is not json' | bash "$HOOK" 2>/dev/null)"; rc=$?
assert "malformed json -> exit 0"    [ "$rc" -eq 0 ]
assert "malformed json -> silent"    [ -z "$out" ]
