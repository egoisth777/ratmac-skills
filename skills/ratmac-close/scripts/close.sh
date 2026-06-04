#!/usr/bin/env bash
# ratmac-close — task done or abandoned: freeze affects, set status, archive, regen (lifecycle "task done / abandoned").
# POSIX shadow of close.ps1 (R4: pwsh primary, this is the shadow at verb parity).
# Writes only under scheduler/ (R5). Reads task state first (R9). Spawns ratmac-regen, never itself (R18).
set -euo pipefail

. "$(dirname "$0")/_common.sh"

# --- arg parse (long flags, manual while-loop; mirrors close.ps1 param block) ------
TASK=""; STATUS=""; CL=""; OUTCOME=""; GOAL=""; ROOT_ARG=""; PROJ_ARG=""; TS=""; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --task)    TASK="${2:-}"; shift 2 ;;
    --status)  STATUS="${2:-}"; shift 2 ;;
    --cl)      CL="${2:-}"; shift 2 ;;
    --outcome) OUTCOME="${2:-}"; shift 2 ;;
    --goal)    GOAL="${2:-}"; shift 2 ;;
    --root)    ROOT_ARG="${2:-}"; shift 2 ;;
    --proj)    PROJ_ARG="${2:-}"; shift 2 ;;
    --ts)      TS="${2:-}"; shift 2 ;;
    --force)   FORCE=1; shift ;;
    --task=*)    TASK="${1#*=}"; shift ;;
    --status=*)  STATUS="${1#*=}"; shift ;;
    --cl=*)      CL="${1#*=}"; shift ;;
    --outcome=*) OUTCOME="${1#*=}"; shift ;;
    --goal=*)    GOAL="${1#*=}"; shift ;;
    --root=*)    ROOT_ARG="${1#*=}"; shift ;;
    --proj=*)    PROJ_ARG="${1#*=}"; shift ;;
    --ts=*)      TS="${1#*=}"; shift ;;
    *) echo "BLOCKED unknown flag: $1" >&2
       ratmac_contract 'Run mode=single' "Blocked items=unknown flag $1"; exit 2 ;;
  esac
done

# --- validate mandatory params (Task, Status w/ ValidateSet done|abandoned) --------
if [ -z "$TASK" ]; then
  echo "BLOCKED --task is required"
  ratmac_contract 'Run mode=single' 'Blocked items=missing --task'; exit 2
fi
case "$STATUS" in
  done|abandoned) ;;
  *) echo "BLOCKED invalid --status '$STATUS' (want: done|abandoned)"
     ratmac_contract 'Run mode=single' "Blocked items=bad status '$STATUS'"; exit 2 ;;
esac

# --- resolve context (engine fns) -------------------------------------------------
# Use command substitution + status check: process substitution (read < <(...)) does
# not propagate the function exit code and does not trip set -e, so a BLOCKED proj
# resolution would be silently swallowed (R4/R12 parity with the pwsh throw).
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
SNAME="$(basename "$SLICE")"

TDIR="$(ratmac_resolve_task "$SLICE" "$TASK")"
if [ -z "$TDIR" ]; then
  echo "BLOCKED task '$TASK' not found in $SNAME grad/"
  ratmac_contract 'Run mode=single' "Active proj=$P_PROJ" "Active slice=$SNAME" "Blocked items=task '$TASK' not in grad/"; exit 2
fi
TNAME="$(basename "$TDIR")"
TSTATE="$TDIR/state.md"
TISSUE="$TDIR/issue.md"
TLOG="$TDIR/log.md"
MODE="$(ratmac_mode "$P_PATH")"
TOUCHED=""

add_touched() {  # accumulate unique, forward-slashed display paths
  local pth; pth="$(printf '%s' "$1" | tr '\\' '/')"
  case ",$TOUCHED," in *",$pth,"*) return 0 ;; esac
  if [ -z "$TOUCHED" ]; then TOUCHED="$pth"; else TOUCHED="$TOUCHED, $pth"; fi
}

# --- done-only gates --------------------------------------------------------------
# The non-empty ## affects gate is data-integrity (S18): a done task with no affects
# record is permanent data loss once archived, so --force MUST NOT bypass it (only an
# abandoned task may archive with empty affects). --force bypasses only the softer
# AC-incomplete check.
if [ "$STATUS" = "done" ]; then
  AFF_COUNT="$(ratmac_affects_list "$TSTATE" | grep -c . || true)"
  if [ "$AFF_COUNT" = "0" ]; then
    echo "BLOCKED need affects: task $TNAME has an empty ## affects list (status=done). Add affects via ratmac-checkpoint (status=done cannot archive empty, even with --force)."
    ratmac_contract 'Run mode=single' "Active proj=$P_PROJ" "Active slice=$SNAME" "Active task=$TNAME" 'Blocked items=empty ## affects'; exit 2
  fi
  if [ "$FORCE" -ne 1 ] && [ -f "$TISSUE" ]; then
    UNCHECKED="$(grep -cE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$TISSUE" || true)"
    if [ "$UNCHECKED" != "0" ]; then
      echo "HUMAN_DECISION_REQUIRED AC incomplete: $UNCHECKED unchecked '- [ ]' item(s) in $TNAME/issue.md. Resolve them, or pass --force to close anyway."
      ratmac_contract 'Run mode=single' "Active proj=$P_PROJ" "Active slice=$SNAME" "Active task=$TNAME" "Human decisions required=$UNCHECKED unchecked AC item(s)"; exit 3
    fi
  fi
fi

# --- set status frontmatter on task state.md (lifecycle 2) -------------------------
ratmac_fm_set "$TSTATE" status "$STATUS" "$STAMP"

# --- write outcome into ## scratch (replace body) ---------------------------------
if [ -n "$OUTCOME" ]; then
  if ! grep -qE '^##[[:space:]]+scratch[[:space:]]*$' "$TSTATE"; then
    printf '\n## scratch\n' >> "$TSTATE"
  fi
  # drop the existing body of ## scratch, then insert the outcome right under the heading
  awk -v body="$OUTCOME" '
    /^##[[:space:]]+scratch[[:space:]]*$/ { print; print body; ins=1; insec=1; next }
    insec && /^##[[:space:]]/ { insec=0 }
    insec { next }
    { print }
  ' "$TSTATE" > "$TSTATE.tmp" && mv "$TSTATE.tmp" "$TSTATE"
  ratmac_fm_set "$TSTATE" time-modified "$STAMP" "$STAMP"
fi
add_touched "$TSTATE"

# --- task log line (lifecycle 3) --------------------------------------------------
if [ "$STATUS" = "done" ]; then
  TLOG_ARGS="cl:${CL:-—}"
else
  TLOG_ARGS="reason:${OUTCOME:-—}"
fi
ratmac_log "$TLOG" "status:$STATUS" "$TLOG_ARGS" "$STAMP"
add_touched "$TLOG"

# --- slice log line (lifecycle 4) -------------------------------------------------
SLOG="$SLICE/log.md"
ratmac_log "$SLOG" 'close-task' "$TNAME status:$STATUS" "$STAMP"
add_touched "$SLOG"

# --- [sole|dual] flip goal item current: true (lifecycle 5) -----------------------
GOAL_FLIPPED=0
if [ -n "$GOAL" ] && { [ "$MODE" = "sole" ] || [ "$MODE" = "dual" ]; }; then
  GOAL_NAME="$(printf '%s' "$GOAL" | tr '\\' '/')"; GOAL_NAME="${GOAL_NAME##*/}"; GOAL_NAME="${GOAL_NAME%.md}"
  GOAL_FILE="$P_PATH/goal/$GOAL_NAME.md"
  if [ -f "$GOAL_FILE" ]; then
    ratmac_fm_set "$GOAL_FILE" current 'true' "$STAMP"
    add_touched "$GOAL_FILE"
    GOAL_FLIPPED=1
  else
    echo "  note: goal item '$GOAL_NAME' not found at goal/$GOAL_NAME.md — skipping current flip"
  fi
fi

# --- read slice-row frontmatter BEFORE the destructive move (R9) ------------------
# Read issue/sprint into locals from the pre-move state.md so a degenerate frontmatter
# can never fail AFTER mv has already archived the dir (which would leave the slice row
# un-flipped and regen never spawned — a half-archived non-rollback state).
A_ISSUE="$(ratmac_fm_get "$TSTATE" issue)"
A_SPRINT="$(ratmac_fm_get "$TSTATE" sprint)"

# --- mv grad/<t> -> <slice>/archive/<t> (lifecycle 9) -----------------------------
ARCHIVE_DIR="$SLICE/archive"
mkdir -p "$ARCHIVE_DIR"
DEST="$ARCHIVE_DIR/$TNAME"
if [ -e "$DEST" ]; then
  echo "BLOCKED archive collision: $DEST already exists; cannot move $TNAME"
  ratmac_contract 'Run mode=single' "Active proj=$P_PROJ" "Active slice=$SNAME" "Active task=$TNAME" "Blocked items=archive/$TNAME exists"; exit 2
fi
mv "$TDIR" "$DEST"
TSTATE="$DEST/state.md"   # re-point post-move (not re-read, just for record)

# --- slice table row -> status (lifecycle 10) -------------------------------------
SSTATE="$SLICE/state.md"
ratmac_task_row "$SSTATE" "$TNAME" "$A_ISSUE" "$A_SPRINT" "$STATUS" "$STAMP"
add_touched "$SSTATE"

# --- trigger regen (lifecycle 6/7/8): spawn sibling skill, never self (R18) -------
# Path needs three dirnames up to reach .../skills (scripts -> ratmac-close -> skills),
# matching the scope.sh / transit.sh idiom; two hops landed at .../ratmac-close/ratmac-regen
# which never exists, so the guard was always false and regen silently skipped on POSIX.
# Forward the resolved $STAMP (not the maybe-empty raw --ts), capture the spawned regen
# exit code, and surface a non-zero as FAILED so the receipt does not hide a stale rollup.
REGEN_SCRIPT="$(dirname "$(dirname "$(dirname "$0")")")/ratmac-regen/scripts/regen.sh"
REGEN_RESULT="not run"
if [ -f "$REGEN_SCRIPT" ]; then
  REGEN_ARGS=(--ts "$STAMP")
  [ -n "$ROOT_ARG" ] && REGEN_ARGS+=(--root "$ROOT_ARG")
  [ -n "$PROJ_ARG" ] && REGEN_ARGS+=(--proj "$PROJ_ARG")
  REGEN_RC=0
  bash "$REGEN_SCRIPT" "${REGEN_ARGS[@]}" >/dev/null 2>&1 || REGEN_RC=$?
  if [ "$REGEN_RC" -eq 0 ]; then REGEN_RESULT="regen spawned"; else REGEN_RESULT="FAILED (regen exit $REGEN_RC; rollup stale)"; fi
fi

# --- receipt + uniform contract (R7) ----------------------------------------------
echo "close: $TNAME status:$STATUS -> archived under $SNAME/archive/"
[ "$GOAL_FLIPPED" -eq 1 ] && echo "  goal '$GOAL' flipped current: true"
ratmac_contract \
  'Run mode=single' \
  "Active proj=$P_PROJ" \
  "Active slice=$SNAME" \
  "Active task=$TNAME" \
  "Classification=close-task:$STATUS" \
  'Skill chain=ratmac-close -> ratmac-regen' \
  "Files touched=$TOUCHED" \
  "Regen result=$REGEN_RESULT" \
  'Next safe action=ratmac-lint to verify post-archive'
