#!/usr/bin/env bash
# ratmac-route — read-only discovery of scheduler land. "where am I?" (R-prefix: no writes).
# POSIX shadow of route.ps1 (R4 parity). Windows pwsh is primary; this is a faithful port.
# Writes nothing, touches nothing (R5 trivially honoured); ends with the uniform contract (R7).
set -euo pipefail

. "$(dirname "$0")/_common.sh"

# --- arg parse (long flags, manual while-loop) ------------------------------------
ROOT_ARG=""; PROJ_ARG=""; TS_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)   ROOT_ARG="${2:-}"; shift 2 ;;
    --proj)   PROJ_ARG="${2:-}"; shift 2 ;;
    --ts)     TS_ARG="${2:-}";   shift 2 ;;
    --root=*) ROOT_ARG="${1#*=}"; shift ;;
    --proj=*) PROJ_ARG="${1#*=}"; shift ;;
    --ts=*)   TS_ARG="${1#*=}";   shift ;;
    *) echo "BLOCKED unknown flag: $1" >&2
       ratmac_contract 'Run mode=single' "Blocked items=unknown flag $1"; exit 2 ;;
  esac
done

# --- resolve active project (ratmac_proj BLOCKs+exits non-zero if unresolvable) ---
# Mirror route.ps1's try/catch: on failure, surface the message + contract, exit 2.
if ! PROJ_LINE="$(ratmac_proj "$ROOT_ARG" "$PROJ_ARG" 2>&1)"; then
  printf '%s\n' "$PROJ_LINE"
  ratmac_contract 'Run mode=single' 'Blocked items=no resolvable project'
  exit 2
fi
IFS=$'\t' read -r _SCHED PROJ PDIR <<EOF
$PROJ_LINE
EOF

PSTATE="$PDIR/state.md"
if [ ! -f "$PSTATE" ]; then
  echo "BLOCKED proj state.md missing at $PSTATE"
  ratmac_contract 'Run mode=single' "Active proj=$PROJ" "Blocked items=$PSTATE"
  exit 2
fi
MODE="$(ratmac_fm_get "$PSTATE" mode)"

# --- active slice -----------------------------------------------------------------
SLICE="$(ratmac_active_slice "$PDIR")"
if [ -n "$SLICE" ]; then SNAME="$(basename "$SLICE")"; else SNAME="—"; fi

# --- active tasks in the active slice (grad/t-*) ----------------------------------
TASKS=""
if [ -n "$SLICE" ]; then
  GRAD="$SLICE/grad"
  if [ -d "$GRAD" ]; then
    for td in "$GRAD"/t-*; do
      [ -d "$td" ] || continue
      tst="$td/state.md"
      if [ -f "$tst" ]; then
        st="$(ratmac_fm_get "$tst" status)"; [ -n "$st" ] || st="?"
        bb="$(ratmac_fm_get "$tst" blocked-by)"
        # normalize an inline [a,b] list into a bare comma list for display
        case "$bb" in
          \[*\]) bb="$(printf '%s' "${bb#[}" | sed 's/]$//; s/ *, */,/g; s/^ *//; s/ *$//')" ;;
        esac
      else
        st="?"; bb=""
      fi
      if [ -n "$bb" ]; then entry="$(basename "$td") ($st, blocked-by: $bb)"; else entry="$(basename "$td") ($st)"; fi
      if [ -z "$TASKS" ]; then TASKS="$entry"; else TASKS="$TASKS; $entry"; fi
    done
  fi
fi

# --- recent log entries (last 5 of slice log, else proj log) ----------------------
tail_log() {  # arg1: path, arg2: count → date-prefixed lines, newest last
  local path="$1" n="$2"
  [ -f "$path" ] || return 0
  grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}' "$path" | tail -n "$n" || true
}
if [ -n "$SLICE" ]; then RECENT="$(tail_log "$SLICE/log.md" 5)"; else RECENT="$(tail_log "$PDIR/log.md" 5)"; fi

# --- suggested next-action mode ---------------------------------------------------
if [ -z "$SLICE" ]; then
  SUGGEST="new-slice"
elif [ -z "$TASKS" ]; then
  SUGGEST="new-task"
else
  SUGGEST="continue-task | new-task | scope-mutation | slice-transit"
fi

# --- emit discovery report --------------------------------------------------------
echo "Active project: $PROJ"
if [ -n "$MODE" ]; then echo "Mode: $MODE"; else echo "Mode: ?"; fi
echo "Active slice: $SNAME"
echo "Active tasks: [$TASKS]"
echo "Recent log entries:"
[ -n "$RECENT" ] && printf '%s\n' "$RECENT" | sed 's#^#  #'
echo ""
echo "Suggested next-action mode: $SUGGEST"
echo ""

if [ -n "$TASKS" ]; then ATASK="$TASKS"; else ATASK="—"; fi
ratmac_contract \
  'Run mode=single' \
  "Active proj=$PROJ" \
  "Active slice=$SNAME" \
  "Active task=$ATASK" \
  'Files touched=— (read-only)' \
  'Lint result=not-run' \
  "Next safe action=pick a mode ($SUGGEST); invoke the matching ratmac-* skill"
