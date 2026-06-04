#!/usr/bin/env bash
# ratmac-kickoff — scaffold a proj | slice | task tier with required files (S2, S3, layout).
# POSIX shadow of kickoff.ps1 (R4: pwsh primary, this is the shadow at verb parity).
# Writes only under scheduler/ (R5). Reads parent state before writing (R9).
set -euo pipefail

. "$(dirname "$0")/_common.sh"

# --- arg parse (long flags, manual while-loop) ------------------------------------
TIER=""; NAME=""
MODE=""; ROLE=""                       # proj-only
ISSUE=""; SPRINT=""; BLOCKEDBY=""; PROBLEM=""   # task-only
ROOT_ARG=""; PROJ=""; TS=""; FORCE=0   # common
while [ $# -gt 0 ]; do
  case "$1" in
    --tier)       TIER="${2:-}"; shift 2 ;;
    --name)       NAME="${2:-}"; shift 2 ;;
    --mode)       MODE="${2:-}"; shift 2 ;;
    --role)       ROLE="${2:-}"; shift 2 ;;
    --issue)      ISSUE="${2:-}"; shift 2 ;;
    --sprint)     SPRINT="${2:-}"; shift 2 ;;
    --blocked-by) BLOCKEDBY="${2:-}"; shift 2 ;;
    --problem)    PROBLEM="${2:-}"; shift 2 ;;
    --root)       ROOT_ARG="${2:-}"; shift 2 ;;
    --proj)       PROJ="${2:-}"; shift 2 ;;
    --ts)         TS="${2:-}"; shift 2 ;;
    --force)      FORCE=1; shift ;;
    # --flag=value forms (parity with close.sh / scope.sh / regen.sh)
    --tier=*)       TIER="${1#*=}"; shift ;;
    --name=*)       NAME="${1#*=}"; shift ;;
    --mode=*)       MODE="${1#*=}"; shift ;;
    --role=*)       ROLE="${1#*=}"; shift ;;
    --issue=*)      ISSUE="${1#*=}"; shift ;;
    --sprint=*)     SPRINT="${1#*=}"; shift ;;
    --blocked-by=*) BLOCKEDBY="${1#*=}"; shift ;;
    --problem=*)    PROBLEM="${1#*=}"; shift ;;
    --root=*)       ROOT_ARG="${1#*=}"; shift ;;
    --proj=*)       PROJ="${1#*=}"; shift ;;
    --ts=*)         TS="${1#*=}"; shift ;;
    *) echo "BLOCKED unknown flag: $1" >&2
       ratmac_contract 'Run mode=single' "Blocked items=unknown flag $1"; exit 2 ;;
  esac
done

# --- validate tier ----------------------------------------------------------------
case "$TIER" in
  proj|slice|task) ;;
  *) echo "BLOCKED invalid --tier '$TIER' (want: proj|slice|task)"
     ratmac_contract 'Run mode=single' "Blocked items=bad tier '$TIER'"; exit 2 ;;
esac
if [ -z "$NAME" ]; then
  echo "BLOCKED --name is required"
  ratmac_contract 'Run mode=single' 'Blocked items=missing --name'; exit 2
fi

# --- shared setup -----------------------------------------------------------------
STAMP="$(ratmac_stamp "$TS")"
TPLDIR="$(ratmac_tpl_dir "$0")"
TOUCHED=""

touched_add() {  # arg1: abs path → normalized, de-duplicated into TOUCHED
  local p; p="$(printf '%s' "$1" | tr '\\' '/')"
  case ",$TOUCHED," in *",$p,"*) return 0 ;; esac
  if [ -z "$TOUCHED" ]; then TOUCHED="$p"; else TOUCHED="$TOUCHED, $p"; fi
}

tpl() {  # arg1: template basename; remaining: KEY=VALUE pairs → expanded text
  ratmac_expand "$TPLDIR/$1" "${@:2}"
}

emit() {  # arg1: dest path; arg2: content → write (honors --force), track touched
  local path="$1" content="$2"
  if [ -e "$path" ] && [ "$FORCE" -ne 1 ]; then return 1; fi
  local parent; parent="$(dirname "$path")"
  [ -d "$parent" ] || mkdir -p "$parent"
  # $() command-substitution already stripped the template's trailing newline; restore
  # the terminating LF so files match pwsh Set-Content and appended log lines stay split.
  printf '%s\n' "$content" > "$path"
  touched_add "$path"
  return 0
}

case "$TIER" in

  # === proj ======================================================================
  proj)
    if [ -z "$MODE" ]; then
      echo "HUMAN_DECISION_REQUIRED proj kickoff needs --mode (maintainer|sole|dual)"
      ratmac_contract 'Run mode=single' 'Human decisions required=pick --mode'; exit 3
    fi
    case "$MODE" in
      maintainer|sole|dual) ;;
      *) echo "BLOCKED invalid --mode '$MODE' (want: maintainer|sole|dual)"
         ratmac_contract 'Run mode=single' "Blocked items=bad mode '$MODE'"; exit 2 ;;
    esac
    SCHED="$(ratmac_root "$ROOT_ARG")"
    case "$NAME" in p-*) PNAME="$NAME" ;; *) PNAME="p-$NAME" ;; esac
    PDIR="$SCHED/$PNAME"
    if [ -d "$PDIR" ] && [ "$FORCE" -ne 1 ]; then
      echo "BLOCKED project '$PNAME' already exists at $PDIR (use --force)"
      ratmac_contract 'Run mode=single' "Blocked items=$PDIR"; exit 2
    fi
    ROLETEXT="$ROLE"; [ -n "$ROLETEXT" ] || ROLETEXT="TODO: describe $PNAME direction"
    emit "$PDIR/state.md" "$(tpl 'proj-state.md.tpl' "STAMP=$STAMP" "NAME=$PNAME" "MODE=$MODE" "ROLE=$ROLETEXT" "SLICE=—")" || true
    emit "$PDIR/log.md"   "$(tpl 'proj-log.md.tpl'   "STAMP=$STAMP" "NAME=$PNAME" "MODE=$MODE")" || true
    # [sole|dual] goal dir is SSoT for deliverables (S12)
    case "$MODE" in
      sole|dual) [ -d "$PDIR/goal" ] || mkdir -p "$PDIR/goal" ;;
    esac
    echo "kickoff proj: $PNAME (mode $MODE)"
    ratmac_contract \
      'Run mode=single' \
      "Active proj=$PNAME" \
      "Files touched=$TOUCHED" \
      'Skill chain=ratmac-kickoff' \
      'Next safe action=ratmac-kickoff --tier slice --name <s-...>; then ratmac-lint'
    ;;

  # === slice =====================================================================
  slice)
    # command substitution + status check: process substitution (read < <(...)) swallows
    # the function exit code and does not trip set -e, so a BLOCKED proj resolution would
    # be silently consumed and kickoff would scaffold under empty paths (R4/R12 parity).
    if ! PROJ_LINE="$(ratmac_proj "$ROOT_ARG" "$PROJ")"; then
      ratmac_contract 'Run mode=single' 'Blocked items=cannot resolve project'; exit 2
    fi
    IFS=$'\t' read -r _ PROJNAME PDIR <<EOF
$PROJ_LINE
EOF
    case "$NAME" in s-*) SNAME="$NAME" ;; *) SNAME="s-$NAME" ;; esac
    SDIR="$PDIR/$SNAME"
    if [ -d "$SDIR" ] && [ "$FORCE" -ne 1 ]; then
      echo "BLOCKED slice '$SNAME' already exists at $SDIR (use --force)"
      ratmac_contract 'Run mode=single' "Active proj=$PROJNAME" "Blocked items=$SDIR"; exit 2
    fi
    MODE="$(ratmac_mode "$PDIR")"
    emit "$SDIR/state.md" "$(tpl 'slice-state.md.tpl' "STAMP=$STAMP" "NAME=$SNAME")" || true
    emit "$SDIR/log.md"   "$(tpl 'slice-log.md.tpl'   "STAMP=$STAMP" "NAME=$SNAME")" || true
    [ -d "$SDIR/grad" ] || mkdir -p "$SDIR/grad"
    # [sole|dual] scope files (S12, S14)
    case "$MODE" in
      sole|dual)
        emit "$SDIR/scope.md"         "$(tpl 'scope.md.tpl'         "STAMP=$STAMP" "NAME=$SNAME")" || true
        emit "$SDIR/scope-history.md" "$(tpl 'scope-history.md.tpl' "STAMP=$STAMP" "NAME=$SNAME")" || true
        ;;
    esac
    # update proj state active-slice pointer (## scratch) + log (R9: read before write)
    PSTATE="$PDIR/state.md"
    if [ -f "$PSTATE" ]; then
      # no ## scratch section: append one so the active-slice pointer is ALWAYS set
      # (parity with kickoff.ps1; see defect 22 — previously the awk left a scratch-less
      # proj state.md pointer-less while still bumping time-modified).
      if ! grep -qE '^##[[:space:]]+scratch[[:space:]]*$' "$PSTATE"; then
        printf '\n## scratch\n' >> "$PSTATE"
      fi
      awk -v slice="$SNAME" '
        /^##[[:space:]]+scratch[[:space:]]*$/ { print; insec=1; next }
        insec && /^##[[:space:]]/ { if (!set) { print "active slice: " slice; set=1 } insec=0; print; next }
        insec && /^active slice:/ { print "active slice: " slice; set=1; next }
        { print }
        END { if (insec && !set) print "active slice: " slice }
      ' "$PSTATE" > "$PSTATE.tmp" && mv "$PSTATE.tmp" "$PSTATE"
      ratmac_fm_set "$PSTATE" time-modified "$STAMP" "$STAMP"
      touched_add "$PSTATE"
    fi
    ratmac_log "$PDIR/log.md" 'active-slice' "$SNAME" "$STAMP"
    touched_add "$PDIR/log.md"
    echo "kickoff slice: $SNAME under $PROJNAME"
    ratmac_contract \
      'Run mode=single' \
      "Active proj=$PROJNAME" \
      "Active slice=$SNAME" \
      "Files touched=$TOUCHED" \
      'Skill chain=ratmac-kickoff' \
      'Next safe action=ratmac-kickoff --tier task --name <t-...>; then ratmac-lint'
    ;;

  # === task ======================================================================
  task)
    # command substitution + status check (see slice tier note): never swallow a BLOCKED.
    if ! PROJ_LINE="$(ratmac_proj "$ROOT_ARG" "$PROJ")"; then
      ratmac_contract 'Run mode=single' 'Blocked items=cannot resolve project'; exit 2
    fi
    IFS=$'\t' read -r _ PROJNAME PDIR <<EOF
$PROJ_LINE
EOF
    SLICE="$(ratmac_active_slice "$PDIR")"
    if [ -z "$SLICE" ]; then
      echo "BLOCKED no active slice under $PROJNAME; kickoff a slice first"
      ratmac_contract 'Run mode=single' "Active proj=$PROJNAME" 'Blocked items=no active slice'; exit 2
    fi
    SNAME="$(basename "$SLICE")"
    MODE="$(ratmac_mode "$PDIR")"
    # S15: maintainer mode requires an issue tag
    if [ "$MODE" = "maintainer" ] && [ -z "$ISSUE" ]; then
      echo "BLOCKED maintainer mode requires --issue <ticket-id> (S15)"
      ratmac_contract 'Run mode=single' "Active proj=$PROJNAME" "Active slice=$SNAME" 'Blocked items=missing --issue'; exit 2
    fi
    case "$NAME" in t-*) TNAME="$NAME" ;; *) TNAME="t-$NAME" ;; esac
    TDIR="$SLICE/grad/$TNAME"
    if [ -d "$TDIR" ] && [ "$FORCE" -ne 1 ]; then
      echo "BLOCKED task '$TNAME' already exists at $TDIR (use --force)"
      ratmac_contract 'Run mode=single' "Active proj=$PROJNAME" "Active slice=$SNAME" "Blocked items=$TDIR"; exit 2
    fi
    PROBLEMTEXT="$PROBLEM"; [ -n "$PROBLEMTEXT" ] || PROBLEMTEXT="TODO: state the problem"
    emit "$TDIR/issue.md" "$(tpl 'task-issue.md.tpl' "STAMP=$STAMP" "NAME=$TNAME" "PROBLEM=$PROBLEMTEXT")" || true
    emit "$TDIR/task.md"  "$(tpl 'task-task.md.tpl'  "STAMP=$STAMP" "NAME=$TNAME")" || true
    emit "$TDIR/state.md" "$(tpl 'task-state.md.tpl' "STAMP=$STAMP" "NAME=$TNAME" "SPRINT=$SPRINT" "ISSUE=$ISSUE" "BLOCKEDBY=$BLOCKEDBY")" || true
    emit "$TDIR/log.md"   "$(tpl 'task-log.md.tpl'   "STAMP=$STAMP" "NAME=$TNAME")" || true
    # slice table row + slice log
    SSTATE="$SLICE/state.md"
    ratmac_task_row "$SSTATE" "$TNAME" "$ISSUE" "$SPRINT" 'active' "$STAMP"
    touched_add "$SSTATE"
    ratmac_log "$SLICE/log.md" 'kickoff-task' "$TNAME" "$STAMP"
    touched_add "$SLICE/log.md"
    echo "kickoff task: $TNAME under $SNAME"
    ratmac_contract \
      'Run mode=single' \
      "Active proj=$PROJNAME" \
      "Active slice=$SNAME" \
      "Active task=$TNAME" \
      "Files touched=$TOUCHED" \
      'Skill chain=ratmac-kickoff' \
      'Next safe action=fill issue.md/task.md; ratmac-checkpoint as work proceeds; ratmac-lint'
    ;;
esac
