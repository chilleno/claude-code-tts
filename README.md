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
| `tts status` | Report current state (+ language and detected speech engine) |
| `tts lang es` | Speak and answer in Spanish — any ISO code works (`es`, `fr`, `de`, `pt`, …); region too (`es-mx`, `pt-br`) |
| `tts lang` | Show configured language |
| `tts lang off` | Back to default language |
| `tts voices` | List installed voices for the selected language, grouped by language/region, with quality tags and the voice in use marked |
| `tts voices all` | Same, for every installed language |
| `tts voice Paulina` | Use a specific voice (macOS; case-insensitive, validated; warns if it doesn't match your language) |
| `tts voice man` / `tts voice woman` | With [Kokoro voices](#better-voices-kokoro) installed: switch between the man and woman voice for your language (`male`/`female` work too) |
| `tts voice off` | Back to automatic voice selection |

Voices are language-specific — a Spanish voice reading English sounds wrong and vice versa — so `tts voices` shows only voices for your `tts lang` selection unless you ask for `all`.

Case-insensitive; leading/trailing spaces ignored. `tts` inside a sentence ("how does tts work?") is left alone.

There is also a real slash command: `/tts`, `/tts on`, `/tts off`, `/tts status` — installed as `<config>/commands/tts.md`. Unlike the plain-text form it does reach the model (one short turn), but works even where prompt hooks are unavailable.

### Multiple Claude instances

Run interactively, the installer detects your instances — `~/.claude`, any `~/.claude-*` config dir, and `CLAUDE_CONFIG_DIR=…` paths found in your shell aliases — and asks which to install into (pick numbers, `all`, or type a custom path). Non-interactive selection also works:

```sh
CLAUDE_CONFIG_DIR=~/.claude-personal ./install.sh   # env var, no questions
./install.sh --dir ~/.claude-work                    # explicit flag, repeatable
./uninstall.sh --dir ~/.claude-work
```

In CI or piped runs it defaults to `~/.claude`. Each instance gets its own flag file (`<config>/tts-enabled`), so toggles are independent.

## Install

Requires `python3` or `node` for the settings merge — no other dependencies, `jq` optional. Everything runs locally; no accounts, APIs, or paid services.

| Platform | Speech engine | Status |
|---|---|---|
| macOS | `say` (built in) | Primary target |
| Linux | `spd-say` (speech-dispatcher) or `espeak` | Supported; install one of them |
| Windows (Git Bash) | PowerShell `System.Speech` | Supported |

No speech engine? Everything still works — toggling, `/tts`, and the brief conversational answers — you just get no audio. The installer warns if it can't find an engine, and `tts status` reports which one it detected.

```sh
git clone https://github.com/chilleno/claude-code-tts.git && cd claude-code-tts
./install.sh
```

The installer:

- copies three small shell hooks into `~/.claude/hooks/`,
- merges two hook entries into `~/.claude/settings.json` — a timestamped `.bak-*` backup is made first, all your other settings and hooks are preserved, and running it twice never duplicates entries,
- touches nothing else.

Then restart (or start) a Claude Code session and type `tts on`.

### Better voices: Kokoro

The built-in voices sound robotic, especially in Spanish. For natural neural voices — free, MIT/Apache licensed, and fully offline after setup — add the optional [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M) engine:

```sh
./install.sh --kokoro
```

| Language | Woman (default) | Man |
|---|---|---|
| English (`tts lang en`, or no language set) | Heart | Michael |
| Spanish (`tts lang es`, `es-mx`, …) — neutral Latin American | Dora | Alex |

Switch with `tts voice man` / `tts voice woman`. `tts lang es-es` keeps Castilian pronunciation; every other Spanish code uses Latin-American (*hice* → "ise", not "ithe"). Other languages keep using the platform voice.

- **Cost:** about 2 GB of downloads, once, into `~/.local/share/claude-tts/kokoro` (override with `CLAUDE_TTS_KOKORO_HOME`) — a private Python 3.11, PyTorch, the 82M-parameter model and the four voices. Shared by every Claude instance; nothing is installed system-wide. Needs `python3` (any version) to bootstrap; macOS and Linux.
- **Speed:** on Apple Silicon the first words start about a second after the reply arrives, 10–20× faster than real time; replies are spoken sentence by sentence.
- **Memory:** a small background server keeps the model loaded (~1 GB RAM) so replies start instantly. It is started on the first spoken reply and exits on its own after 30 idle minutes (`TTS_KOKORO_IDLE`, seconds). A new reply interrupts the one playing.
- **Fallback:** if Kokoro can't start or answer, the platform voice (`say`) reads the reply instead. Picking an Apple voice by name (`tts voice Paulina`) also uses `say`; `tts voice woman`/`man` goes back to Kokoro.
- **Speed control:** `TTS_KOKORO_SPEED` (default `1.0`) in the stop hook's config block or the environment. Server log: `~/.local/share/claude-tts/kokoro/server.log`.

## Uninstall

```sh
./uninstall.sh
```

Removes the two hook entries from `settings.json` (backup made first, foreign hooks untouched), the hook scripts, the flag file, and the speech pid file. The shared Kokoro folder is kept (other instances may use it); `./uninstall.sh --kokoro` removes it too.

## Changing voice and speed

Open `~/.claude/hooks/tts-stop-hook.sh` (or `hooks/tts-stop-hook.sh` in the repo before installing) — the config block sits at the top:

```sh
TTS_VOICE=""     # macOS voice name, e.g. "Samantha", "Daniel"; `say -v ?` lists them. Empty = system default.
TTS_RATE="200"   # words per minute; typical 150–250
```

Both are also plain environment variables, so `TTS_VOICE=Daniel claude` works too. Rate applies to macOS `say` only.

`tts lang <code>` stores a language in `<config>/tts-lang`. While set, replies are asked for in that language, and the speaker adapts: on Linux the code is passed to `spd-say -l` / `espeak -v`; on macOS a `say` voice is auto-picked for it.

Voice precedence on macOS: `TTS_VOICE` env → `tts voice NAME` → auto-pick. Auto-pick prefers Apple's **Premium/Enhanced** voices, then regular ones (Mónica, Paulina, Samantha, …), and skips the novelty voices (Eddy, Grandma, Rocko, …) that ship enabled by default. For noticeably better quality, download Premium/Enhanced voices in **System Settings › Accessibility › Spoken Content › System Voice › Manage Voices** — they show up in `tts voices` and are picked automatically. The injected "speak conversationally" instruction lives at the top of `~/.claude/hooks/tts-prompt-hook.sh` in the `TTS_INSTRUCTION` variable — edit it to taste.

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

Runs the whole suite against a temporary `$HOME` with a stubbed `say` — your real `~/.claude` is never touched. Covers toggle commands, exit codes, instruction injection, markdown stripping, speech interruption, installer merge/idempotency, uninstall cleanup, and Kokoro routing (voice per language and gender, fallback, `uninstall --kokoro`) with a stand-in Kokoro install.
