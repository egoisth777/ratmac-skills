#!/usr/bin/env bash
# ratm-recite — open a recitation HTML doc in the browser for the user to read.
# POSIX shadow of recite.ps1. Presentation only; alignment happens in chat (design RR1/RR2).
#
# Usage:
#   recite.sh --html <path> [--title <t>] [--wrap] [--no-open]
#
# Prints the absolute path of the opened file to stdout (headless-safe).
set -euo pipefail

HTML=""
TITLE="Recitation"
WRAP=0
NO_OPEN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --html)    HTML="$2"; shift 2 ;;
        --title)   TITLE="$2"; shift 2 ;;
        --wrap)    WRAP=1; shift ;;
        --no-open) NO_OPEN=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

[ -n "$HTML" ] || { echo "--html is required" >&2; exit 2; }
[ -f "$HTML" ] || { echo "Html path not found: $HTML" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCH="${TMPDIR:-/tmp}/ratm-recite"
mkdir -p "$SCRATCH"

if [ "$WRAP" -eq 1 ]; then
    SHELL_HTML="$SCRIPT_DIR/../assets/shell.html"
    [ -f "$SHELL_HTML" ] || { echo "shell.html not found for --wrap: $SHELL_HTML" >&2; exit 1; }
    OUT_FILE="$SCRATCH/recite.html"
    SHELL_CONTENT="$(cat "$SHELL_HTML")"
    FRAGMENT="$(cat "$HTML")"
    # Inject the fragment by SPLIT + CONCATENATE, not pattern substitution. bash 5.2+ treats
    # '&' in a ${//} replacement as "the matched text", which would corrupt HTML entities in
    # the fragment (&ndash; &rarr; etc.). Concatenation is purely literal. CONTENT marker is
    # unique, so %%/# split on it cleanly: prefix = before, suffix = after.
    # Inject by SPLIT + CONCATENATE only. Never use ${var//pat/repl} with file/title content
    # as the replacement: bash 5.2+ expands '&' in the replacement to the matched text, which
    # corrupts HTML entities (&ndash; &rarr;) and any '&' in a title. Concatenation is literal.
    # Both markers are unique in shell.html, so %%/# prefix/suffix splits are unambiguous.
    inject() {  # inject <haystack> <marker> <replacement>  -> echoes haystack with first marker replaced
        local hay="$1" mark="$2" rep="$3"
        printf '%s' "${hay%%"${mark}"*}${rep}${hay#*"${mark}"}"
    }
    COMPOSED="$(inject "$SHELL_CONTENT" '__TITLE__' "$TITLE")"   # <title>
    COMPOSED="$(inject "$COMPOSED"      '__TITLE__' "$TITLE")"   # <h1>
    COMPOSED="$(inject "$COMPOSED"      '<!-- CONTENT_SLOT -->' "$FRAGMENT")"
    printf '%s\n' "$COMPOSED" > "$OUT_FILE"
else
    OUT_FILE="$(cd "$(dirname "$HTML")" && pwd)/$(basename "$HTML")"
fi

if [ "$NO_OPEN" -eq 0 ]; then
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$OUT_FILE" >/dev/null 2>&1 || true
    elif command -v open >/dev/null 2>&1; then
        open "$OUT_FILE" >/dev/null 2>&1 || true
    fi
fi

echo "$OUT_FILE"
