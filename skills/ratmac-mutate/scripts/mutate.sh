#!/usr/bin/env bash
# ratmac-mutate — in-place plan/approach/ticket revision (S15, S16). One task per issue; revise, never fork.
# POSIX shadow of mutate.ps1 (R4: pwsh primary, this is the shadow at verb parity).
# Writes only under scheduler/ (R5). Reads state first (R9).
set -euo pipefail

. "$(dirname "$0")/_common.sh"

# --- arg parse (long flags, manual while-loop) ------------------------------------
TASK=""; KIND=""; REASON=""; DIFF=""; ROOT_ARG=""; PROJ=""; TS=""; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --task)     TASK="${2:-}"; shift 2 ;;
    --kind)     KIND="${2:-}"; shift 2 ;;
    --reason)   REASON="${2:-}"; shift 2 ;;
    --diff)     DIFF="${2:-}"; shift 2 ;;
    --root)     ROOT_ARG="${2:-}"; shift 2 ;;
    --proj)     PROJ="${2:-}"; shift 2 ;;
    --ts)       TS="${2:-}"; shift 2 ;;
    --force)    FORCE=1; shift ;;
    --task=*)   TASK="${1#*=}"; shift ;;
    --kind=*)   KIND="${1#*=}"; shift ;;
    --reason=*) REASON="${1#*=}"; shift ;;
    --diff=*)   DIFF="${1#*=}"; shift ;;
    --root=*)   ROOT_ARG="${1#*=}"; shift ;;
    --proj=*)   PROJ="${1#*=}"; shift ;;
    --ts=*)     TS="${1#*=}"; shift ;;
    *) echo "BLOCKED unknown flag: $1" >&2
       ratmac_contract 'Run mode=single' "Blocked items=unknown flag $1"; exit 2 ;;
  esac
done

# --- validate mandatory params + --kind set (BLOCKED on bad input) ----------------
if [ -z "$TASK" ]; then
  echo "BLOCKED --task is required"
  ratmac_contract 'Run mode=single' 'Blocked items=missing --task'; exit 2
fi
case "$KIND" in
  plan|approach|ticket) ;;
  *) echo "BLOCKED invalid --kind '$KIND' (want: plan|approach|ticket)"
     ratmac_contract 'Run mode=single' "Blocked items=bad kind '$KIND'"; exit 2 ;;
esac
if [ -z "$REASON" ]; then
  echo "BLOCKED --reason is required"
  ratmac_contract 'Run mode=single' 'Blocked items=missing --reason'; exit 2
fi

# --- resolve context (engine fns) -------------------------------------------------
# Command substitution + status check: a `read < <(ratmac_proj ...)` process substitution
# does NOT propagate the function exit code and does NOT trip set -e, so a BLOCKED proj
# resolution would be silently swallowed and mutate would proceed with empty paths (where
# pwsh throws and STOPS). Capture the line, exit 2 with a contract on failure, then split
# the tab-separated fields from the variable via a here-string (R4/R12 parity).
STAMP="$(ratmac_stamp "$TS")"
if ! PROJ_LINE="$(ratmac_proj "$ROOT_ARG" "$PROJ")"; then
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

TDIR="$(ratmac_resolve_task "$SLICE" "$TASK")"
if [ -z "$TDIR" ]; then
  echo "BLOCKED task '$TASK' not found in grad/"
  ratmac_contract 'Run mode=single' "Active proj=$P_PROJ" "Blocked items=task '$TASK' not in grad/"; exit 2
fi

TASK_MD="$TDIR/task.md"
ISSUE_MD="$TDIR/issue.md"
STATE_MD="$TDIR/state.md"
LOG_MD="$TDIR/log.md"
TASK_LEAF="$(basename "$TDIR")"
SLICE_LEAF="$(basename "$SLICE")"
TOUCHED=""

# helper: append a unique slash-normalized path to the touched list
add_touched() {  # arg1: abs path
  local pth; pth="$(printf '%s' "$1" | tr '\\' '/')"
  case ", $TOUCHED," in *", $pth,"*) return 0 ;; esac
  if [ -z "$TOUCHED" ]; then TOUCHED="$pth"; else TOUCHED="$TOUCHED, $pth"; fi
}

case "$KIND" in
  plan|approach)
    # S15 stop: task.md newer than state.md => likely already revised by hand
    if [ "$FORCE" -ne 1 ] && [ -f "$TASK_MD" ] && [ -f "$STATE_MD" ]; then
      T_TM="$(ratmac_fm_get "$TASK_MD" time-modified)"
      S_TM="$(ratmac_fm_get "$STATE_MD" time-modified)"
      if [ -n "$T_TM" ] && [ -n "$S_TM" ] && [ "$T_TM" \> "$S_TM" ]; then
        echo "HUMAN_DECISION_REQUIRED task.md is newer than state.md — likely already revised manually (S15). Pass --force to override."
        ratmac_contract 'Run mode=single' "Active proj=$P_PROJ" "Active task=$TASK_LEAF" \
          'Human decisions required=confirm in-place revise vs manual edit'; exit 3
      fi
    fi
    if [ -n "$DIFF" ]; then
      if [ ! -f "$DIFF" ]; then
        echo "BLOCKED --diff path '$DIFF' not found"
        ratmac_contract 'Run mode=single' "Blocked items=$DIFF"; exit 2
      fi
      cat "$DIFF" > "$TASK_MD"
      ratmac_fm_set "$TASK_MD" time-modified "$STAMP" "$STAMP"
    else
      # no diff supplied: just bump time-modified; agent edits task.md body separately
      if [ -f "$TASK_MD" ]; then ratmac_fm_set "$TASK_MD" time-modified "$STAMP" "$STAMP"; fi
    fi
    add_touched "$TASK_MD"
    ratmac_log "$LOG_MD" replan "$REASON" "$STAMP"
    add_touched "$LOG_MD"
    echo "mutate $KIND: $TASK_LEAF — $REASON"
    ;;

  ticket)
    # append a ## ticket updates block to issue.md (S16)
    if [ -n "$DIFF" ] && [ -f "$DIFF" ]; then UPD="$(cat "$DIFF")"; else UPD="$REASON"; fi
    ENTRY="- $STAMP — $UPD"
    if grep -qE '^##[[:space:]]+ticket updates[[:space:]]*$' "$ISSUE_MD"; then
      # insert the entry after the last line of the existing section (mirrors sec.End)
      awk -v entry="$ENTRY" '
        /^##[[:space:]]+ticket updates[[:space:]]*$/ { print; ina=1; next }
        ina && /^##[[:space:]]/ { print entry; ina=0 }
        { print }
        END { if (ina) print entry }
      ' "$ISSUE_MD" > "$ISSUE_MD.tmp" && mv "$ISSUE_MD.tmp" "$ISSUE_MD"
    else
      printf '\n## ticket updates\n%s\n' "$ENTRY" >> "$ISSUE_MD"
    fi
    ratmac_fm_set "$ISSUE_MD" time-modified "$STAMP" "$STAMP"
    add_touched "$ISSUE_MD"
    ratmac_log "$LOG_MD" ticket-update "$REASON" "$STAMP"
    add_touched "$LOG_MD"
    echo "mutate ticket: $TASK_LEAF — $REASON"
    ;;
esac

# --- uniform contract (R7) --------------------------------------------------------
ratmac_contract \
  'Run mode=single' \
  "Active proj=$P_PROJ" \
  "Active slice=$SLICE_LEAF" \
  "Active task=$TASK_LEAF" \
  "Skill chain=ratmac-mutate" \
  "Files touched=$TOUCHED" \
  'Next safe action=update task state.md via ratmac-checkpoint; ratmac-lint'
