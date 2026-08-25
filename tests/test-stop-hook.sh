# test-stop-hook.sh — Stop hook behavior with stubbed `say`.
# Sourced by run-tests.sh (assert + fresh_home available).

HOOK="$REPO_DIR/hooks/tts-stop-hook.sh"

stop_json() { # stop_json MESSAGE (already JSON-escaped)
  printf '{"hook_event_name":"Stop","last_assistant_message":"%s"}' "$1"
}

run_stop() { # run_stop JSON
  # Retry loop: process spawn can transiently fail under the CI sandbox's
  # process limits (fork EAGAIN bursts), which is outside the hook's control.
  local attempt
  for attempt in 1 2 3; do
    printf '%s' "$1" | TTS_SAY_CMD="$HOME/stub-bin/say" bash "$HOOK" >/dev/null 2>&1
    rc=$?
    # let the backgrounded stub finish writing its log
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$HOME/say.log" ] && break; sleep 0.1; done
    [ -s "$HOME/say.log" ] && break
  done
}

fresh_home
FLAG="$HOME/.claude/tts-enabled"
LOG="$HOME/say.log"
PIDFILE="$HOME/.claude/tts-speech.pid"

# flag off: say never invoked
run_stop "$(stop_json 'hello there')"
assert "off: exit 0"                 [ "$rc" -eq 0 ]
assert "off: say not invoked"        [ ! -f "$LOG" ]

# flag on: speaks the text
: > "$FLAG"
run_stop "$(stop_json 'hello there friend')"
assert "on: exit 0"                  [ "$rc" -eq 0 ]
assert "on: say invoked"             grep -q "STDIN:hello there friend" "$LOG"
assert "on: rate arg passed"         grep -q -- "-r 200" "$LOG"
assert "on: pid file written"        [ -f "$PIDFILE" ]

# markdown sanitized: code block replaced, backticks/headers/urls/lists gone
rm -f "$LOG"
msg='# Title\n\nUse the `foo` flag.\n\n```js\nconsole.log(1)\n```\n\n- item one\n- see [docs](https://example.com/x) and https://example.com/raw\n\n**bold** text'
run_stop "$(stop_json "$msg")"
spoken="$(grep '^STDIN:' "$LOG")"
assert "sanitize: code -> omitted"   grep -q "Code omitted." <<<"$spoken"
assert "sanitize: no console.log"    ! grep -q "console.log" <<<"$spoken"
assert "sanitize: no backticks"      ! grep -q '`' <<<"$spoken"
assert "sanitize: no hash header"    ! grep -q '#' <<<"$spoken"
assert "sanitize: no urls"           ! grep -q 'https' <<<"$spoken"
assert "sanitize: link text kept"    grep -q 'docs' <<<"$spoken"
assert "sanitize: no bold markers"   ! grep -q '\*\*' <<<"$spoken"
assert "sanitize: words kept"        grep -q 'bold text' <<<"$spoken"

# interruption: second run kills the first (stub sleeps)
rm -f "$LOG" "$PIDFILE"
printf '%s' "$(stop_json 'long first reply')" \
  | TTS_SAY_CMD="$HOME/stub-bin/say" STUB_SAY_SLEEP=5 bash "$HOOK" >/dev/null 2>&1
first_pid="$(cat "$PIDFILE")"
run_stop "$(stop_json 'second reply')"
second_pid="$(cat "$PIDFILE")"
assert "interrupt: pid rotated"      [ "$first_pid" != "$second_pid" ]
sleep 0.3
assert "interrupt: first killed"     ! kill -0 "$first_pid" 2>/dev/null

# empty / missing message: clean silent exit
rm -f "$LOG"
run_stop '{"hook_event_name":"Stop"}'
assert "no message: exit 0"          [ "$rc" -eq 0 ]
assert "no message: say not run"     [ ! -f "$LOG" ]
run_stop "$(stop_json '')"
assert "empty message: exit 0"       [ "$rc" -eq 0 ]

# malformed json: exit 0
printf 'not json' | TTS_SAY_CMD="$HOME/stub-bin/say" bash "$HOOK" >/dev/null 2>&1
assert "malformed json: exit 0"      [ $? -eq 0 ]
