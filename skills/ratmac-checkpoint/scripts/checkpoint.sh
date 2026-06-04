#!/usr/bin/env bash
# ratmac-checkpoint — POSIX shadow of checkpoint.ps1 (R4: pwsh primary, this is the shadow at verb parity).
# Snapshot pause: replace task ## status body, bump state.md time-modified, append task log.md,
# optional ## affects add, optional status change (frontmatter + slice table + slice log).
# Writes only under scheduler/ (R5). Reads the task state.md before writing (R9).
set -euo pipefail

. "$(dirname "$0")/_common.sh"

# --- arg parse (long flags, manual while-loop) ------------------------------------
# --add-affects takes a comma-separated value (CLI contract: <p1>,<p2>); split it
# into separate path elements here so the engine sees a real list — mirroring how
# the pwsh CLI binds a comma string into [string[]]$AddAffects (R4 parity). The
# engine (ratmac_affects_add) itself never splits, matching Add-RatmacAffects.
TASK=""; NOTE=""; STATUS=""; ROOT_ARG=""; PROJ_ARG=""; TS=""
ADD_AFFECTS=()
add_affects_push() {  # split arg on commas, append each non-empty piece
  local val="$1" piece
  local oldifs="$IFS"; IFS=','
  for piece in $val; do
    [ -n "$piece" ] && ADD_AFFECTS+=("$piece")
  done
  IFS="$oldifs"
}
while [ $# -gt 0 ]; do
  case "$1" in
    --task)        TASK="${2:-}"; shift 2 ;;
    --note)        NOTE="${2:-}"; shift 2 ;;
    --add-affects) add_affects_push "${2:-}"; shift 2 ;;
    --status)      STATUS="${2:-}"; shift 2 ;;
    --root)        ROOT_ARG="${2:-}"; shift 2 ;;
    --proj)        PROJ_ARG="${2:-}"; shift 2 ;;
    --ts)          TS="${2:-}"; shift 2 ;;
    --task=*)        TASK="${1#*=}"; shift ;;
    --note=*)        NOTE="${1#*=}"; shift ;;
    --add-affects=*) add_affects_push "${1#*=}"; shift ;;
    --status=*)      STATUS="${1#*=}"; shift ;;
    --root=*)        ROOT_ARG="${1#*=}"; shift ;;
    --proj=*)        PROJ_ARG="${1#*=}"; shift ;;
    --ts=*)          TS="${1#*=}"; shift ;;
    *) echo "BLOCKED unknown flag: $1" >&2
       ratmac_contract 'Run mode=single' "Blocked items=unknown flag $1"; exit 2 ;;
  esac
done

# --- validate required + enum ----------------------------------------------------
if [ -z "$TASK" ]; then
  echo "BLOCKED --task is required"
  ratmac_contract 'Run mode=single' 'Blocked items=missing --task'; exit 2
fi
if [ -z "$NOTE" ]; then
  echo "BLOCKED --note is required"
  ratmac_contract 'Run mode=single' 'Blocked items=missing --note'; exit 2
fi
if [ -n "$STATUS" ]; then
  case "$STATUS" in
    active|blocked) ;;
    *) echo "BLOCKED invalid --status '$STATUS' (want: active|blocked)"
       ratmac_contract 'Run mode=single' "Blocked items=bad status '$STATUS'"; exit 2 ;;
  esac
fi

# --- resolve context (engine fns) ------------------------------------------------
# Command substitution + status check: a `read < <(ratmac_proj ...)` process substitution
# does NOT propagate the function exit code and does NOT trip set -e, so a BLOCKED proj
# resolution would be silently swallowed and lint/checkpoint would proceed with empty paths
# (where pwsh throws and STOPS). Capture the line, exit 2 with a contract on failure, then
# split the tab-separated fields from the variable via a here-string (R4/R12 parity).
STAMP="$(ratmac_stamp "$TS")"
if ! PROJ_LINE="$(ratmac_proj "$ROOT_ARG" "$PROJ_ARG")"; then
  ratmac_contract 'Run mode=single' 'Blocked items=cannot resolve project'; exit 2
fi
IFS=$'\t' read -r P_ROOT P_PROJ P_PATH <<EOF
$PROJ_LINE
EOF

SLICE="$(ratmac_active_slice "$P_PATH")"
if [ -z "$SLICE" ]; then
  echo "BLOCKED no active slice under $P_PROJ"
  ratmac_contract 'Run mode=single' "Active proj=$P_PROJ" 'Blocked items=no active slice'; exit 2
fi
SLICE_NAME="$(basename "$SLICE")"

TDIR="$(ratmac_resolve_task "$SLICE" "$TASK")"
if [ -z "$TDIR" ]; then
  echo "BLOCKED task '$TASK' not found in $SLICE grad/ (archived tasks use ratmac-mutate or revive)"
  ratmac_contract 'Run mode=single' "Active proj=$P_PROJ" "Active slice=$SLICE_NAME" \
    "Blocked items=task '$TASK' not in grad/"; exit 2
fi
TASK_NAME="$(basename "$TDIR")"
TSTATE="$TDIR/state.md"
TLOG="$TDIR/log.md"
TOUCHED=()

# --- update ## status section body (first line of note) (R9: read first) ----------
NOTE_FIRST="$(printf '%s' "$NOTE" | head -n 1)"
# scratch entry = the remainder past the first line if present, else the first line itself
NOTE_REST="$(printf '%s' "$NOTE" | tail -n +2 | tr '\n' ' ' | sed 's/^ *//; s/ *$//')"
if [ -n "$NOTE_REST" ]; then SCRATCH_ENTRY="$NOTE_REST"; else SCRATCH_ENTRY="$NOTE_FIRST"; fi
if grep -qE '^##[[:space:]]+status[[:space:]]*$' "$TSTATE"; then
  # replace the section body (everything between the heading and the next ## heading) with the note
  awk -v repl="$NOTE_FIRST" '
    /^##[[:space:]]+status[[:space:]]*$/ { print; print repl; instat=1; next }
    instat && /^##[[:space:]]/ { instat=0; print; next }
    instat { next }
    { print }
  ' "$TSTATE" > "$TSTATE.tmp" && mv "$TSTATE.tmp" "$TSTATE"
fi
# append the note to ## scratch (contract + lifecycle require status + scratch + affects).
# Mirror checkpoint.ps1: create the section if absent, append the bullet at its end so
# cross-session scratch context is preserved (dated detail still lands in log.md per S19).
if ! grep -qE '^##[[:space:]]+scratch[[:space:]]*$' "$TSTATE"; then
  printf '\n## scratch\n' >> "$TSTATE"
fi
awk -v entry="- $STAMP $SCRATCH_ENTRY" '
  /^##[[:space:]]+scratch[[:space:]]*$/ { print; insc=1; next }
  insc && /^##[[:space:]]/ { print entry; insc=0; print; next }
  { print }
  END { if (insc) print entry }
' "$TSTATE" > "$TSTATE.tmp" && mv "$TSTATE.tmp" "$TSTATE"
ratmac_fm_set "$TSTATE" time-modified "$STAMP" "$STAMP"
TOUCHED+=("$(printf '%s' "$TSTATE" | tr '\\' '/')")

# --- affects add (S18, dedupe RQ13) ----------------------------------------------
AFF_MSG=""
if [ "${#ADD_AFFECTS[@]}" -gt 0 ]; then
  r="$(ratmac_affects_add "$TSTATE" "$STAMP" "${ADD_AFFECTS[@]}")"
  added="${r#added=}"; added="${added%% *}"
  dup="${r##*dup=}"
  AFF_MSG="affects +$added (dup $dup)"
fi

# --- status change → frontmatter + slice table + slice log ------------------------
STATUS_CHANGED=0
if [ -n "$STATUS" ]; then
  cur="$(ratmac_fm_get "$TSTATE" status)"
  if [ "$cur" != "$STATUS" ]; then
    ratmac_fm_set "$TSTATE" status "$STATUS" "$STAMP"
    STATUS_CHANGED=1
    t_issue="$(ratmac_fm_get "$TSTATE" issue)"
    t_sprint="$(ratmac_fm_get "$TSTATE" sprint)"
    ratmac_task_row "$SLICE/state.md" "$TASK_NAME" "$t_issue" "$t_sprint" "$STATUS" "$STAMP"
    TOUCHED+=("$(printf '%s' "$SLICE/state.md" | tr '\\' '/')")
    ratmac_log "$SLICE/log.md" 'task-status' "$TASK_NAME status:$STATUS" "$STAMP"
    TOUCHED+=("$(printf '%s' "$SLICE/log.md" | tr '\\' '/')")
  fi
fi

# --- append task log line ---------------------------------------------------------
LOG_ARGS="$NOTE_FIRST"
if [ -n "$AFF_MSG" ]; then LOG_ARGS="$LOG_ARGS | $AFF_MSG"; fi
ratmac_log "$TLOG" 'checkpoint' "$LOG_ARGS" "$STAMP"
TOUCHED+=("$(printf '%s' "$TLOG" | tr '\\' '/')")

# --- de-dup touched list (preserve order) ----------------------------------------
TOUCHED_JOINED=""
for t in "${TOUCHED[@]}"; do
  case ",$TOUCHED_JOINED," in
    *",$t,"*) ;;
    *) if [ -z "$TOUCHED_JOINED" ]; then TOUCHED_JOINED="$t"; else TOUCHED_JOINED="$TOUCHED_JOINED, $t"; fi ;;
  esac
done

# --- report + contract ------------------------------------------------------------
echo "checkpoint: $TASK_NAME — $NOTE_FIRST"
[ -n "$AFF_MSG" ] && echo "  $AFF_MSG"
[ "$STATUS_CHANGED" -eq 1 ] && echo "  status -> $STATUS (slice table + log updated)"

ratmac_contract \
  'Run mode=single' \
  "Active proj=$P_PROJ" \
  "Active slice=$SLICE_NAME" \
  "Active task=$TASK_NAME" \
  "Skill chain=ratmac-checkpoint" \
  "Files touched=$TOUCHED_JOINED" \
  'Next safe action=continue work, or ratmac-close when AC met; ratmac-lint to verify'
