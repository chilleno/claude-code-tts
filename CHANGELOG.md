# Changelog

All notable changes to claude-tts are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added
- `/tts` slash command (`commands/tts.md`) as an alternative to the plain-text toggle.
- `CLAUDE_CONFIG_DIR` support: installer, uninstaller, and state files are per-instance for multi-instance setups.

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
