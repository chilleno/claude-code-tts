# Changelog

All notable changes to claude-tts are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added
- `/tts` slash command (`commands/tts.md`) as an alternative to the plain-text toggle.
- `CLAUDE_CONFIG_DIR` support: installer, uninstaller, and state files are per-instance for multi-instance setups.

- Speech-engine detection: installer warns when no engine is present; `tts status` reports the detected engine.
- CI workflow running the test suite on Ubuntu and macOS.
- `tts lang <code>` (e.g. `tts lang es`, `tts lang es-mx`): replies are answered and spoken in that language — auto-picks a matching macOS `say` voice (Premium/Enhanced first, novelty voices skipped), passes the code to `spd-say`/`espeak` on Linux; `tts lang` shows it, `tts lang off` resets.
- `tts voice <name>` / `tts voice off` / `tts voices [all]`: pick or list voices (macOS). Listing is filtered to the selected language, grouped by language/region, tags premium/enhanced/novelty voices and marks the one in use; picking a voice that doesn't match the selected language warns. `tts status` shows the effective voice.
- Installer detects multiple Claude instances (`~/.claude`, `~/.claude-*`, `CLAUDE_CONFIG_DIR` aliases in shell rc files) and interactively asks which to install into; `--dir PATH` flag on install and uninstall for scripted use.

- Optional Kokoro neural voices (`./install.sh --kokoro`): free, offline, English (Heart / Michael) and neutral Latin-American Spanish (Dora / Alex). Installed once into `~/.local/share/claude-tts/kokoro` with a private Python; a background server keeps the model loaded, speaks sentence by sentence, interrupts on a new reply and exits after 30 idle minutes. Falls back to the platform voice. `./uninstall.sh --kokoro` removes it.
- `tts off` stops the Kokoro server right away (frees its ~1 GB, even while it is still loading) and cuts off speech that is playing.
- `tts voice man` / `tts voice woman` (also `male`/`female`): switch the Kokoro voice gender; `tts status`, `tts lang` and `tts voices` show the Kokoro voice in use.

### Fixed
- Hook `timeout` written in seconds (was milliseconds).

## [0.1.0] - 2026-08-25

### Added
- `tts on` / `tts off` / `tts` / `tts status` in-session commands, intercepted by a UserPromptSubmit hook (never sent to the model).
- Flag file state at `~/.claude/tts-enabled`.
- Hidden "speak like a conversation" instruction injected into prompts while TTS is on.
- Stop hook that strips markdown/code/URLs from replies and speaks them in the background (macOS `say`; Linux `spd-say`/`espeak` and Windows PowerShell scaffolding).
- Interruption of in-progress speech when a new reply arrives.
- Idempotent `install.sh` (merges into `~/.claude/settings.json` with timestamped backup) and matching `uninstall.sh`.
- Test suite running against a temporary `$HOME`.
