#!/usr/bin/env bash
# run-tests.sh — claude-tts test runner.
# Every test file runs with HOME pointed at a fresh temp dir, so the real
# ~/.claude is never touched. A stub `say` (and friends) sits first in PATH.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"
export REPO_DIR

PASS=0
FAIL=0
FAILED_NAMES=()

# assert NAME COMMAND... — run in current test file's env, count result.
# A leading "!" inverts the expectation.
assert() {
  local name="$1"; shift
  local invert=0
  if [ "${1:-}" = "!" ]; then invert=1; shift; fi
  "$@"
  local rc=$?
  [ "$invert" -eq 1 ] && { [ "$rc" -eq 0 ] && rc=1 || rc=0; }
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "  ok   $name"
  else
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$name")
    echo "  FAIL $name"
  fi
}
export -f assert 2>/dev/null || true

# fresh_home — create and export a sandbox HOME with stub speech binaries.
fresh_home() {
  HOME="$(mktemp -d "${TMPDIR:-/tmp}/claude-tts-test.XXXXXX")"
  export HOME
  mkdir -p "$HOME/.claude" "$HOME/stub-bin"
  # Hooks running from the repo checkout would otherwise derive state paths
  # from their own location; pin them to the sandbox HOME.
  export CLAUDE_TTS_FLAG="$HOME/.claude/tts-enabled"
  export CLAUDE_TTS_PID_FILE="$HOME/.claude/tts-speech.pid"
  export CLAUDE_TTS_LANG_FILE="$HOME/.claude/tts-lang"
  export CLAUDE_TTS_VOICE_FILE="$HOME/.claude/tts-voice"
  export CLAUDE_TTS_GENDER_FILE="$HOME/.claude/tts-gender"
  # absent unless a test calls fake_kokoro, so the default engine stays `say`
  export CLAUDE_TTS_KOKORO_HOME="$HOME/kokoro"
  unset CLAUDE_CONFIG_DIR
  # fake macOS voice list (novelty voice first to exercise ranking)
  cat > "$HOME/stub-bin/voices" <<'EOF'
#!/usr/bin/env bash
echo "Samantha             en_US    # Hello!"
echo "Eddy (Spanish (Spain)) es_ES    # Hola!"
echo "Mónica               es_ES    # Hola!"
echo "Paulina              es_MX    # Hola!"
echo "Thomas               fr_FR    # Bonjour!"
EOF
  chmod +x "$HOME/stub-bin/voices"
  export TTS_VOICE_LIST_CMD="$HOME/stub-bin/voices"
  # Stub `say`: log invocation + stdin, then linger so interruption is testable.
  cat > "$HOME/stub-bin/say" <<'EOF'
#!/usr/bin/env bash
{ echo "ARGS:$*"; echo "STDIN:$(cat)"; } >> "$HOME/say.log"
sleep "${STUB_SAY_SLEEP:-0}"
EOF
  chmod +x "$HOME/stub-bin/say"
  PATH="$HOME/stub-bin:$PATH"
  export PATH
}

# fake_kokoro — a stand-in Kokoro install: its `python` logs the client's
# arguments and stdin to $HOME/kokoro.log instead of speaking.
fake_kokoro() {
  mkdir -p "$CLAUDE_TTS_KOKORO_HOME/venv/bin"
  : > "$CLAUDE_TTS_KOKORO_HOME/tts_kokoro_say.py"
  cat > "$CLAUDE_TTS_KOKORO_HOME/venv/bin/python" <<'EOF'
#!/usr/bin/env bash
{ echo "ARGS:$*"; echo "STDIN:$(cat)"; } >> "$HOME/kokoro.log"
EOF
  chmod +x "$CLAUDE_TTS_KOKORO_HOME/venv/bin/python"
}

overall_fail=0
for t in "$TESTS_DIR"/test-*.sh; do
  echo "== $(basename "$t")"
  PASS=0; FAIL=0; FAILED_NAMES=()
  # shellcheck disable=SC1090
  . "$t"
  echo "   $PASS passed, $FAIL failed"
  [ "$FAIL" -gt 0 ] && overall_fail=1
done

if [ "$overall_fail" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "TESTS FAILED"
fi
exit "$overall_fail"
