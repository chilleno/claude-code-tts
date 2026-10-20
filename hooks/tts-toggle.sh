#!/usr/bin/env bash
# tts-toggle.sh — flip/report TTS state. Shared by the prompt hook and the
# /tts slash command.
#
# Usage: tts-toggle.sh [on|off|status|lang [CODE|off]|voice [NAME|man|woman|off]|voices]
#        (no argument = toggle)
# Prints the resulting state to stdout.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tts-common.sh
. "$SCRIPT_DIR/tts-common.sh"

turn_on()  { mkdir -p "$(dirname "$TTS_FLAG")"; touch "$TTS_FLAG"; echo "🔊 TTS on"; }
turn_off() { rm -f "$TTS_FLAG"; echo "🔇 TTS off"; }

# kokoro_status_voice — "Dora (woman, Kokoro) — switch with: tts voice man"
kokoro_status_voice() {
  local g other; g="$(tts_gender)"
  if [ "$g" = male ]; then other=woman; else other=man; fi
  echo "$(kokoro_voice_label "$(kokoro_voice "$(tts_lang)" "$g")") ($(gender_word "$g"), Kokoro) — switch with: tts voice $other"
}

case "${1:-}" in
  on)  turn_on ;;
  off) turn_off ;;
  status)
    if tts_is_on; then echo "🔊 TTS is on"; else echo "🔇 TTS is off"; fi
    cur="$(tts_lang)"
    [ -n "$cur" ] && echo "language: $cur ($(lang_name "$cur"))"
    v="$(tts_voice)"
    if use_kokoro; then echo "voice: $(kokoro_status_voice)"
    elif [ -n "$v" ]; then echo "voice: $v"
    elif [ -n "$cur" ] && [ "$(tts_engine)" = say ]; then
      auto="$(pick_voice "$cur")"
      [ -n "$auto" ] && echo "voice: $auto (auto for $cur)"
    fi
    engine="$(tts_engine)"
    if use_kokoro; then
      echo "speech engine: kokoro${engine:+ (fallback: $engine)}"
    elif [ -n "$engine" ]; then
      echo "speech engine: $engine"
      if kokoro_ready && [ -n "$v" ]; then echo "kokoro: installed, not used while an Apple voice is chosen — back to Kokoro with: tts voice woman (or man)"
      elif kokoro_ready; then echo "kokoro: installed, but has no $(lang_name "$cur") voices — using $engine"; fi
    else
      echo "speech engine: none found — replies won't be spoken (Linux: install speech-dispatcher or espeak)"
    fi
    ;;
  ""|toggle)
    if tts_is_on; then turn_off; else turn_on; fi
    ;;
  lang)
    code="$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
    case "$code" in
      "")
        cur="$(tts_lang)"
        if [ -n "$cur" ]; then echo "🌐 TTS language: $cur ($(lang_name "$cur"))"
        else echo "🌐 TTS language: default (not set)"; fi
        ;;
      off|clear|default)
        rm -f "$TTS_LANG_FILE"
        echo "🌐 TTS language reset to default"
        ;;
      [a-z][a-z]|[a-z][a-z][a-z]|[a-z][a-z]-[a-z][a-z]|[a-z][a-z][a-z]-[a-z][a-z])
        mkdir -p "$(dirname "$TTS_LANG_FILE")"
        printf '%s\n' "$code" > "$TTS_LANG_FILE"
        echo "🌐 TTS language: $code ($(lang_name "$code"))"
        if use_kokoro; then
          echo "voice: $(kokoro_status_voice)"
        elif [ "$(tts_engine)" = say ] && [ -z "$(tts_voice)" ]; then
          auto="$(pick_voice "$code")"
          if [ -n "$auto" ]; then echo "voice: $auto (auto — change with: tts voice NAME, list with: tts voices)"
          else echo "warning: no $code voice installed — add one in System Settings › Accessibility › Spoken Content"; fi
        fi
        ;;
      *)
        echo "usage: tts lang [code|off]  — e.g. tts lang es, tts lang es-mx" >&2
        exit 1
        ;;
    esac
    ;;
  voice)
    shift
    name="$*"
    case "$name" in
      "")
        v="$(tts_voice)"
        if use_kokoro; then echo "🗣 TTS voice: $(kokoro_status_voice)"
        elif [ -n "$v" ]; then echo "🗣 TTS voice: $v"
        else echo "🗣 TTS voice: auto (from language) — set with: tts voice NAME"; fi
        ;;
      off|clear|default|auto)
        rm -f "$TTS_VOICE_FILE" "$TTS_GENDER_FILE"
        echo "🗣 TTS voice reset to auto"
        ;;
      [Mm][Aa][Nn]|[Mm][Ee][Nn]|[Mm][Aa][Ll][Ee]|[Ww][Oo][Mm][Aa][Nn]|[Ww][Oo][Mm][Ee][Nn]|[Ff][Ee][Mm][Aa][Ll][Ee])
        # Kokoro voice gender; also drops any Apple voice pick so Kokoro takes over.
        case "$name" in [Mm]*) g=male ;; *) g=female ;; esac
        mkdir -p "$(dirname "$TTS_GENDER_FILE")"
        printf '%s\n' "$g" > "$TTS_GENDER_FILE"
        rm -f "$TTS_VOICE_FILE"
        if use_kokoro; then echo "🗣 TTS voice: $(kokoro_status_voice)"
        elif kokoro_ready; then echo "🗣 TTS voice: $(gender_word "$g") — Kokoro has no $(lang_name "$(tts_lang)") voices, so $(tts_engine) speaks for now"
        else echo "🗣 TTS voice: $(gender_word "$g") — applies to Kokoro voices; install them with: ./install.sh --kokoro"; fi
        ;;
      *)
        # On macOS, validate against installed voices (case-insensitive name match).
        if [ "$(tts_engine)" = say ]; then
          match="$(list_voices | awk -v want="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" '
            { n = ""; for (i = 1; i <= NF; i++) { if ($i ~ /^[a-z][a-z][a-z]?_[A-Z][A-Z]/) break; n = n (i > 1 ? " " : "") $i }
              if (tolower(n) == want) { print n; exit } }')"
          if [ -z "$match" ]; then
            echo "error: no installed voice named '$name' — see: tts voices" >&2
            exit 1
          fi
          name="$match"
        fi
        mkdir -p "$(dirname "$TTS_VOICE_FILE")"
        printf '%s\n' "$name" > "$TTS_VOICE_FILE"
        loc="$(voice_locale "$name")"
        if [ -n "$loc" ]; then echo "🗣 TTS voice: $name — $(locale_label "$loc")"
        else echo "🗣 TTS voice: $name"; fi
        # warn when the voice's language doesn't match the selected language
        cur="$(tts_lang)"
        if [ -n "$cur" ] && [ -n "$loc" ]; then
          pat="$(lang_locale_pattern "$cur")"
          case "$loc" in "$pat"*) ;; *)
            echo "warning: $name speaks $(locale_label "$loc") but TTS language is $cur ($(lang_name "$cur")) — speech will sound wrong. Try: tts voices" ;;
          esac
        fi
        ;;
    esac
    ;;
  voices)
    if [ "$(tts_engine)" != say ]; then
      echo "voice listing is only available on macOS (say); on Linux configure the engine directly" >&2
      exit 1
    fi
    cur="$(tts_lang)"
    filter="$cur"
    [ "${2:-}" = all ] && filter=""
    chosen="$(tts_voice)"
    auto=""; [ -z "$chosen" ] && [ -n "$cur" ] && auto="$(pick_voice "$cur")"

    if [ -n "$filter" ]; then
      label="$(lang_name "$filter")"
      case "$filter" in *-*) label="$label ($(region_name "$(printf '%s' "${filter#*-}" | tr '[:lower:]' '[:upper:]')"))" ;; esac
      echo "Voices for $label — showing only your selected language ($filter). See every language with: tts voices all"
    else
      echo "All installed voices, grouped by language. Select a language first (tts lang es) to see just those."
    fi
    if use_kokoro; then
      echo "In use: Kokoro — $(kokoro_status_voice). The Apple voices below are used only if you pick one by name."
      chosen=""; auto=""
    fi
    echo "  ★ = in use   [premium]/[enhanced] = high quality   [novelty] = joke voice, skipped by auto-pick"
    echo "  More/better voices: System Settings › Accessibility › Spoken Content › System Voice › Manage Voices"
    # rows: name<TAB>locale, sorted by locale then name
    list_voices "$filter" | awk '
      { n = ""; for (i = 1; i <= NF; i++) { if ($i ~ /^[a-z][a-z][a-z]?_[A-Z][A-Z]/) { loc = $i; break }; n = n (i > 1 ? " " : "") $i }
        if (n != "") printf "%s\t%s\n", loc, n }' | sort -t "$(printf '\t')" -k1,1 -k2,2 \
    | while IFS="$(printf '\t')" read -r loc n; do
        if [ "$loc" != "${last_loc:-}" ]; then
          echo; echo "$(locale_label "$loc")  [$loc]"; last_loc="$loc"
        fi
        tag=""
        case "$n" in
          *"(Premium)"*)  tag=" [premium]" ;;
          *"(Enhanced)"*) tag=" [enhanced]" ;;
        esac
        first="${n%% *}"
        case " Albert Bad Bahh Bells Boing Bubbles Cellos Eddy Flo Fred Good Grandma Grandpa Jester Junior Kathy Organ Ralph Reed Rocko Sandy Shelley Superstar Trinoids Whisper Wobble Zarvox " in
          *" $first "*) tag=" [novelty]" ;;
        esac
        mark="  "
        if [ -n "$chosen" ] && [ "$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$chosen" | tr '[:upper:]' '[:lower:]')" ]; then mark="★ "
        elif [ -z "$chosen" ] && [ "$n" = "$auto" ]; then mark="★ "; fi
        printf '  %s%-34s%s\n' "$mark" "$n" "$tag"
      done
    echo
    echo "Pick one with: tts voice NAME   (e.g. tts voice ${auto:-${chosen:-Paulina}})"
    ;;
  *)
    echo "usage: tts-toggle.sh [on|off|status|lang [CODE|off]|voice [NAME|man|woman|off]|voices]" >&2
    exit 1
    ;;
esac
