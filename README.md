# claude-tts

An in-session text-to-speech toggle for [Claude Code](https://code.claude.com). Type `tts on` in any session and Claude's replies are read aloud with your computer's voice — and Claude is quietly told to answer the way a person would speak, not in walls of markdown. Type `tts off` and everything is back to normal.

Current version: see [`VERSION`](VERSION). Changes: [`CHANGELOG.md`](CHANGELOG.md). License: MIT.

## Commands

Type these as a normal prompt inside Claude Code. They are intercepted by a hook and **never reach the model** (you'll see a short confirmation instead):

| Command | Effect |
|---|---|
| `tts on` | Enable speech + conversational answers |
| `tts off` | Disable |
| `tts` | Toggle |
| `tts status` | Report current state |

Case-insensitive; leading/trailing spaces ignored. `tts` inside a sentence ("how does tts work?") is left alone.

There is also a real slash command: `/tts`, `/tts on`, `/tts off`, `/tts status` — installed as `<config>/commands/tts.md`. Unlike the plain-text form it does reach the model (one short turn), but works even where prompt hooks are unavailable.

### Multiple Claude instances

Everything installs into `$CLAUDE_CONFIG_DIR` if set, else `~/.claude`. If you run instances via aliases like `CLAUDE_CONFIG_DIR=~/.claude-personal claude`, install per instance:

```sh
CLAUDE_CONFIG_DIR=~/.claude-personal ./install.sh
```

Each instance gets its own flag file (`<config>/tts-enabled`), so toggles are independent.

## Install

Requires macOS (speech via `say`) and `python3` or `node` for the settings merge — no other dependencies, `jq` optional. Linux (`spd-say`/`espeak`) and Windows (PowerShell speech) have scaffolded support in the speak hook.

```sh
git clone <this-repo> && cd claude-code-tts
./install.sh
```

The installer:

- copies three small shell hooks into `~/.claude/hooks/`,
- merges two hook entries into `~/.claude/settings.json` — a timestamped `.bak-*` backup is made first, all your other settings and hooks are preserved, and running it twice never duplicates entries,
- touches nothing else.

Then restart (or start) a Claude Code session and type `tts on`.

## Uninstall

```sh
./uninstall.sh
```

Removes the two hook entries from `settings.json` (backup made first, foreign hooks untouched), the hook scripts, the flag file, and the speech pid file.

## Changing voice and speed

Open `~/.claude/hooks/tts-stop-hook.sh` (or `hooks/tts-stop-hook.sh` in the repo before installing) — the config block sits at the top:

```sh
TTS_VOICE=""     # macOS voice name, e.g. "Samantha", "Daniel"; `say -v ?` lists them. Empty = system default.
TTS_RATE="200"   # words per minute; typical 150–250
```

Both are also plain environment variables, so `TTS_VOICE=Daniel claude` works too. The injected "speak conversationally" instruction lives at the top of `~/.claude/hooks/tts-prompt-hook.sh` in the `TTS_INSTRUCTION` variable — edit it to taste.

## How it works

State is a single flag file: `<config>/tts-enabled` (present = on), derived from where the hooks are installed. It is shared by all sessions of that instance.

Two Claude Code hooks:

- **`tts-prompt-hook.sh`** (`UserPromptSubmit`) reads each submitted prompt. Toggle commands flip the flag file and exit with code 2, which blocks the prompt from reaching the model and shows the confirmation from stderr. For ordinary prompts while TTS is on, it prints a short "you're being listened to, answer conversationally" instruction on stdout, which Claude Code adds to the model's context.
- **`tts-stop-hook.sh`** (`Stop`) fires when a reply finishes. If the flag is on, it takes the reply text from the hook's `last_assistant_message` input field, strips markdown, code blocks (replaced with "Code omitted"), URLs, and file paths so they aren't read symbol-by-symbol, kills any still-running speech, and pipes the result to `say` in the background — the session never waits for speech to finish.

JSON parsing in the hooks tries `jq`, then `python3`, then `node`, so nothing extra needs installing.

### Version caveats

The hooks and settings schema are Claude Code internals and may shift between versions:

- The prompt field has been documented both as `prompt` and `prompt_text` — the hook reads both.
- `last_assistant_message` on the Stop hook is relatively new. If a future version renames it, speech silently stops (the hook exits cleanly rather than break your session) — check this field first when debugging.
- Blocked-prompt UX (exit code 2) renders as a hook block message; that's the intended interception, just styled by Claude Code.

## Tests

```sh
./tests/run-tests.sh
```

Runs the whole suite against a temporary `$HOME` with a stubbed `say` — your real `~/.claude` is never touched. Covers toggle commands, exit codes, instruction injection, markdown stripping, speech interruption, installer merge/idempotency, and uninstall cleanup.
