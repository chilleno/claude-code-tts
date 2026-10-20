#!/usr/bin/env bash
# tts-common.sh — shared helpers for the claude-tts hooks.
# Sourced by tts-prompt-hook.sh, tts-stop-hook.sh and tts-toggle.sh.

# The Claude config dir is wherever these scripts are installed
# (<config>/hooks/tts-common.sh), so multiple instances via CLAUDE_CONFIG_DIR
# (e.g. ~/.claude-personal, ~/.claude-even) each get their own state.
_TTS_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TTS_CONFIG_DIR="$(dirname "$_TTS_COMMON_DIR")"

# State flag: file present = TTS on. Overridable for tests.
TTS_FLAG="${CLAUDE_TTS_FLAG:-$_TTS_CONFIG_DIR/tts-enabled}"
# PID of the currently-speaking process (so a new reply can interrupt it).
TTS_PID_FILE="${CLAUDE_TTS_PID_FILE:-$_TTS_CONFIG_DIR/tts-speech.pid}"
# Language override: file holds a code like "es" or "es-mx"; absent = default.
TTS_LANG_FILE="${CLAUDE_TTS_LANG_FILE:-$_TTS_CONFIG_DIR/tts-lang}"
# Voice override set via `tts voice NAME`; absent = auto-pick from language.
TTS_VOICE_FILE="${CLAUDE_TTS_VOICE_FILE:-$_TTS_CONFIG_DIR/tts-voice}"
# Kokoro voice gender set via `tts voice man|woman`: "male" or "female"; absent = female.
TTS_GENDER_FILE="${CLAUDE_TTS_GENDER_FILE:-$_TTS_CONFIG_DIR/tts-gender}"
# Optional Kokoro engine (./install.sh --kokoro), shared by every Claude instance.
TTS_KOKORO_HOME="${CLAUDE_TTS_KOKORO_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-tts/kokoro}"

# json_get FIELD < json-on-stdin
# Prints the top-level string FIELD, or nothing if absent/unparsable.
# Prefers jq, falls back to python3, then node (always present with Claude Code).
json_get() {
  local field="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
try:
    v = json.load(sys.stdin).get(sys.argv[1])
    if isinstance(v, str):
        sys.stdout.write(v)
except Exception:
    pass
' "$field" 2>/dev/null
  elif command -v node >/dev/null 2>&1; then
    node -e '
let d = "";
process.stdin.on("data", c => d += c);
process.stdin.on("end", () => {
  try {
    const v = JSON.parse(d)[process.argv[1]];
    if (typeof v === "string") process.stdout.write(v);
  } catch (e) {}
});
' "$field" 2>/dev/null
  fi
}

tts_is_on() { [ -f "$TTS_FLAG" ]; }

# tts_lang — configured language code ("es", "es-mx"), or nothing.
tts_lang() { [ -f "$TTS_LANG_FILE" ] && tr -d '[:space:]' < "$TTS_LANG_FILE"; return 0; }
# tts_voice — voice chosen with `tts voice NAME`, or nothing.
tts_voice() { [ -f "$TTS_VOICE_FILE" ] && sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$TTS_VOICE_FILE"; return 0; }
# tts_gender — "female" (default) or "male", chosen with `tts voice woman|man`.
tts_gender() {
  if [ "$( [ -f "$TTS_GENDER_FILE" ] && tr -d '[:space:]' < "$TTS_GENDER_FILE")" = male ]; then echo male; else echo female; fi
}
# gender_word GENDER — "woman" / "man" for messages.
gender_word() { if [ "$1" = male ]; then echo man; else echo woman; fi; }

# kokoro_ready — the optional Kokoro engine is installed.
kokoro_ready() { [ -x "$TTS_KOKORO_HOME/venv/bin/python" ] && [ -f "$TTS_KOKORO_HOME/tts_kokoro_say.py" ]; }
# kokoro_speaks CODE — Kokoro has voices for this language (default = English).
kokoro_speaks() { case "${1:-en}" in en|en-*|es|es-*) return 0 ;; *) return 1 ;; esac; }
# kokoro_voice CODE GENDER — Kokoro voice id; top-graded voice per language/gender.
kokoro_voice() {
  case "${1%%-*}:$2" in
    es:male) echo em_alex ;;    es:*) echo ef_dora ;;
    *:male)  echo am_michael ;; *)    echo af_heart ;;
  esac
}
# kokoro_voice_label ID — "af_heart" -> "Heart".
kokoro_voice_label() { local n="${1#*_}"; printf '%s%s\n' "$(printf '%s' "${n:0:1}" | tr '[:lower:]' '[:upper:]')" "${n:1}"; }
# use_kokoro — this reply goes to Kokoro: installed, speaks the language, and no
# Apple voice was explicitly chosen (TTS_VOICE env or `tts voice NAME`).
use_kokoro() { [ -z "${TTS_VOICE:-}" ] && [ -z "$(tts_voice)" ] && kokoro_ready && kokoro_speaks "$(tts_lang)"; }

# lang_name CODE — human-readable language name for the injected instruction.
# Region suffix (es-mx) is ignored for the name.
lang_name() {
  case "${1%%-*}" in
    en) echo "English" ;;     es) echo "Spanish" ;;     fr) echo "French" ;;
    de) echo "German" ;;      it) echo "Italian" ;;     pt) echo "Portuguese" ;;
    nl) echo "Dutch" ;;       pl) echo "Polish" ;;      ru) echo "Russian" ;;
    ja) echo "Japanese" ;;    zh) echo "Chinese" ;;     ko) echo "Korean" ;;
    ar) echo "Arabic" ;;      hi) echo "Hindi" ;;       tr) echo "Turkish" ;;
    sv) echo "Swedish" ;;     da) echo "Danish" ;;      fi) echo "Finnish" ;;
    nb|no) echo "Norwegian" ;; cs) echo "Czech" ;;      sk) echo "Slovak" ;;
    hu) echo "Hungarian" ;;   ro) echo "Romanian" ;;    bg) echo "Bulgarian" ;;
    el) echo "Greek" ;;       he) echo "Hebrew" ;;      hr) echo "Croatian" ;;
    sl) echo "Slovenian" ;;   sr) echo "Serbian" ;;     uk) echo "Ukrainian" ;;
    ca) echo "Catalan" ;;     eu) echo "Basque" ;;      gl) echo "Galician" ;;
    id) echo "Indonesian" ;;  ms) echo "Malay" ;;       th) echo "Thai" ;;
    vi) echo "Vietnamese" ;;  fa) echo "Persian" ;;     ur) echo "Urdu" ;;
    bn) echo "Bengali" ;;     ta) echo "Tamil" ;;       te) echo "Telugu" ;;
    kn) echo "Kannada" ;;     ml) echo "Malayalam" ;;   mr) echo "Marathi" ;;
    gu) echo "Gujarati" ;;    pa) echo "Punjabi" ;;     af) echo "Afrikaans" ;;
    sw) echo "Swahili" ;;     zu) echo "Zulu" ;;        cy) echo "Welsh" ;;
    ga) echo "Irish" ;;       lt) echo "Lithuanian" ;;  lv) echo "Latvian" ;;
    et) echo "Estonian" ;;    is) echo "Icelandic" ;;   mt) echo "Maltese" ;;
    sq) echo "Albanian" ;;    mk) echo "Macedonian" ;;  bs) echo "Bosnian" ;;
    yue) echo "Cantonese" ;;  wuu) echo "Shanghainese" ;;
    *)  echo "${1%%-*}" ;;   # unknown: return the code itself
  esac
}

# lang_locale_pattern CODE — regex prefix matching `say -v ?` locale column:
# "es" -> "es_", "es-mx" -> "es_MX".
lang_locale_pattern() {
  local base="${1%%-*}" region=""
  case "$1" in *-*) region="$(printf '%s' "${1#*-}" | tr '[:lower:]' '[:upper:]')" ;; esac
  if [ -n "$region" ]; then echo "${base}_${region}"; else echo "${base}_"; fi
}

# region_name CODE — readable region for a locale suffix (MX -> Mexico).
region_name() {
  case "$1" in
    US) echo "United States" ;; GB) echo "United Kingdom" ;; AU) echo "Australia" ;;
    IE) echo "Ireland" ;;       IN) echo "India" ;;          ZA) echo "South Africa" ;;
    CA) echo "Canada" ;;        ES) echo "Spain" ;;          MX) echo "Mexico" ;;
    AR) echo "Argentina" ;;     CL) echo "Chile" ;;          CO) echo "Colombia" ;;
    BR) echo "Brazil" ;;        PT) echo "Portugal" ;;       FR) echo "France" ;;
    BE) echo "Belgium" ;;       CH) echo "Switzerland" ;;    DE) echo "Germany" ;;
    AT) echo "Austria" ;;       IT) echo "Italy" ;;          NL) echo "Netherlands" ;;
    JP) echo "Japan" ;;         CN) echo "China" ;;          TW) echo "Taiwan" ;;
    HK) echo "Hong Kong" ;;     KR) echo "Korea" ;;          RU) echo "Russia" ;;
    SE) echo "Sweden" ;;        NO) echo "Norway" ;;         DK) echo "Denmark" ;;
    FI) echo "Finland" ;;       PL) echo "Poland" ;;         TR) echo "Turkey" ;;
    SA) echo "Saudi Arabia" ;;  IL) echo "Israel" ;;         GR) echo "Greece" ;;
    BG) echo "Bulgaria" ;;      CZ) echo "Czechia" ;;        HU) echo "Hungary" ;;
    RO) echo "Romania" ;;       UA) echo "Ukraine" ;;        HR) echo "Croatia" ;;
    SI) echo "Slovenia" ;;      SK) echo "Slovakia" ;;       RS) echo "Serbia" ;;
    ID) echo "Indonesia" ;;     MY) echo "Malaysia" ;;       TH) echo "Thailand" ;;
    VN) echo "Vietnam" ;;       NZ) echo "New Zealand" ;;    SG) echo "Singapore" ;;
    AE) echo "UAE" ;;           EG) echo "Egypt" ;;          IR) echo "Iran" ;;
    PK) echo "Pakistan" ;;      BD) echo "Bangladesh" ;;     SCOTLAND) echo "Scotland" ;;
    *)  echo "$1" ;;
  esac
}

# locale_label xx_YY — "Spanish (Mexico)".
locale_label() {
  local lang="${1%%_*}" region="${1#*_}"
  region="${region%%[^A-Za-z]*}"   # strip trailing junk if any
  echo "$(lang_name "$lang") ($(region_name "$region"))"
}

# voice_locale NAME — locale (xx_YY) of an installed voice, or nothing.
voice_locale() {
  list_voices | awk -v want="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" '
    { n = ""; for (i = 1; i <= NF; i++) { if ($i ~ /^[a-z][a-z][a-z]?_[A-Z][A-Z]/) { loc = $i; break }; n = n (i > 1 ? " " : "") $i }
      if (tolower(n) == want) { print loc; exit } }'
}

# tts_engine — print the speech engine available on this platform, or nothing.
tts_engine() {
  case "$(uname -s)" in
    Darwin)
      command -v say >/dev/null 2>&1 && echo "say" ;;
    Linux)
      if command -v spd-say >/dev/null 2>&1; then echo "spd-say"
      elif command -v espeak >/dev/null 2>&1; then echo "espeak"
      fi ;;
    MINGW*|MSYS*|CYGWIN*)
      command -v powershell.exe >/dev/null 2>&1 && echo "powershell" ;;
  esac
}

# list_voices [CODE] — `say -v ?` lines (macOS), optionally filtered by language.
# TTS_VOICE_LIST_CMD override lets tests inject a fake voice list.
list_voices() {
  local pat=""
  [ -n "${1:-}" ] && pat="$(lang_locale_pattern "$1")"
  ${TTS_VOICE_LIST_CMD:-say -v '?'} 2>/dev/null | awk -v p="$pat" '
    p == "" { print; next }
    { for (i = 2; i <= NF; i++) if ($i ~ "^" p) { print; break } }'
}

# pick_voice CODE — best `say` voice for a language: Premium/Enhanced first,
# then regular voices, skipping Apple's novelty voices (Eddy, Grandma, ...).
pick_voice() {
  list_voices "$1" | awk '
    function name(   n, i) {
      # voice name = fields before the locale column (xx_YY)
      n = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[a-z][a-z][a-z]?_[A-Z][A-Z]/) break
        n = n (i > 1 ? " " : "") $i
      }
      return n
    }
    BEGIN {
      split("Albert Bad Bahh Bells Boing Bubbles Cellos Eddy Flo Fred Good Grandma Grandpa Jester Junior Kathy Organ Ralph Reed Rocko Sandy Shelley Superstar Trinoids Whisper Wobble Zarvox", nv, " ")
      for (k in nv) novelty[nv[k]] = 1
    }
    {
      v = name()
      if (v == "") next
      first = v; sub(/ .*/, "", first)
      if (v ~ /\((Premium|Enhanced)\)/) { if (!best1) best1 = v }
      else if (!(first in novelty))    { if (!best2) best2 = v }
      else                             { if (!best3) best3 = v }
    }
    END { if (best1) print best1; else if (best2) print best2; else if (best3) print best3 }'
}
