#!/usr/bin/env bash
# ratmac-scope — sole/dual scope expand/contract mid-slice: edit scope.md + scope-history.md + log, then regen.
# POSIX shadow of scope.ps1 (R4: pwsh primary, this is the shadow at verb parity).
# Writes only under scheduler/ (R5). Reads slice/proj state first (R9). Spawns ratmac-regen, never itself (R18).
# All STOPs (R12) fire BEFORE any write so an ambiguous scope mutation never half-applies.
set -euo pipefail

. "$(dirname "$0")/_common.sh"

# --- arg parse (long flags, manual while-loop; mirrors pwsh params) ----------------
OP=""            # +|- (Mandatory)
REF=""           # goal topic (bare name; '.md' / path tail tolerated) (Mandatory)
REASON=""
CREATE_GOAL=0    # -Op + : scaffold goal/<ref>.md if missing
SLICE=""         # optional explicit slice ref; default = active slice
ROOT_ARG=""
PROJ=""
TS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --op)          OP="${2:-}"; shift 2 ;;
    --ref)         REF="${2:-}"; shift 2 ;;
    --reason)      REASON="${2:-}"; shift 2 ;;
    --create-goal) CREATE_GOAL=1; shift ;;
    --slice)       SLICE="${2:-}"; shift 2 ;;
    --root)        ROOT_ARG="${2:-}"; shift 2 ;;
    --proj)        PROJ="${2:-}"; shift 2 ;;
    --ts)          TS="${2:-}"; shift 2 ;;
    --op=*)          OP="${1#*=}"; shift ;;
    --ref=*)         REF="${1#*=}"; shift ;;
    --reason=*)      REASON="${1#*=}"; shift ;;
    --slice=*)       SLICE="${1#*=}"; shift ;;
    --root=*)        ROOT_ARG="${1#*=}"; shift ;;
    --proj=*)        PROJ="${1#*=}"; shift ;;
    --ts=*)          TS="${1#*=}"; shift ;;
    *) echo "BLOCKED unknown flag: $1" >&2
       ratmac_contract 'Run mode=single' "Blocked items=unknown flag $1"; exit 2 ;;
  esac
done

# --- validate the mandatory params ------------------------------------------------
case "$OP" in
  +|-) ;;
  *) echo "BLOCKED -Op must be one of +|- (got '$OP')"
     ratmac_contract 'Run mode=single' "Blocked items=bad -Op '$OP'"; exit 2 ;;
esac
if [ -z "$REF" ]; then
  echo "BLOCKED -Ref is required"
  ratmac_contract 'Run mode=single' 'Blocked items=missing -Ref'; exit 2
fi

# --- resolve stamp / date / proj / mode (R9: read state before any write) ---------
# Command substitution + status check: a `read < <(ratmac_proj ...)` process substitution
# does NOT propagate the function exit code and does NOT trip set -e, so a BLOCKED proj
# resolution would be silently swallowed and scope would proceed with empty paths (where
# pwsh throws and STOPS). Capture the line, exit 2 with a contract on failure, then split
# the tab-separated fields from the variable via a here-string (R4/R12 parity).
STAMP="$(ratmac_stamp "$TS")"
DATE="$(printf '%s' "$STAMP" | cut -d- -f1-3)"   # YYYY-MM-DD slice of the stamp (S14 history line)
if ! PROJ_LINE="$(ratmac_proj "$ROOT_ARG" "$PROJ")"; then
  ratmac_contract 'Run mode=single' 'Blocked items=cannot resolve project'; exit 2
fi
IFS=$'\t' read -r _SROOT PROJ_NAME PDIR <<EOF
$PROJ_LINE
EOF
MODE="$(ratmac_mode "$PDIR")"

# --- STOP: maintainer mode has no scope (contract stop-rule) ----------------------
if [ "$MODE" = "maintainer" ]; then
  echo "BLOCKED maintainer mode has no scope (scope.md/scope-history.md exist only in sole|dual)"
  ratmac_contract 'Run mode=single' "Active proj=$PROJ_NAME" 'Blocked items=maintainer mode has no scope'; exit 2
fi

# --- resolve slice ----------------------------------------------------------------
if [ -n "$SLICE" ]; then
  case "$SLICE" in s-*) SNAME="$SLICE" ;; *) SNAME="s-$SLICE" ;; esac
  SLICE_PATH="$PDIR/$SNAME"
  if [ ! -d "$SLICE_PATH" ]; then
    echo "BLOCKED slice '$SNAME' not found under $PROJ_NAME"
    ratmac_contract 'Run mode=single' "Active proj=$PROJ_NAME" "Blocked items=slice '$SNAME' missing"; exit 2
  fi
else
  SLICE_PATH="$(ratmac_active_slice "$PDIR")"
  if [ -z "$SLICE_PATH" ]; then
    echo "BLOCKED no active slice under $PROJ_NAME"
    ratmac_contract 'Run mode=single' "Active proj=$PROJ_NAME" 'Blocked items=no active slice'; exit 2
  fi
  SNAME="$(basename "$SLICE_PATH")"
fi

SCOPE="$SLICE_PATH/scope.md"
HIST="$SLICE_PATH/scope-history.md"
SLOG="$SLICE_PATH/log.md"
if [ ! -f "$SCOPE" ]; then
  echo "BLOCKED scope.md missing in $SNAME (slice not sole/dual-scoped); kickoff the slice under a sole|dual proj"
  ratmac_contract 'Run mode=single' "Active proj=$PROJ_NAME" "Active slice=$SNAME" 'Blocked items=scope.md missing'; exit 2
fi

# --- normalize the goal ref -------------------------------------------------------
TOPIC="$(printf '%s' "$REF" | tr '\\' '/')"; TOPIC="${TOPIC##*/}"; TOPIC="${TOPIC%.md}"
GOAL_DIR="$PDIR/goal"
GOAL_FILE="$GOAL_DIR/$TOPIC.md"
TOUCHED=""
GOAL_CREATED=0

# helper: append a value to the comma-joined TOUCHED list (deduped at print time)
add_touched() { local v; v="$(printf '%s' "$1" | tr '\\' '/')"; if [ -z "$TOUCHED" ]; then TOUCHED="$v"; else TOUCHED="$TOUCHED, $v"; fi; }

# regex-safe topic for grep -E (escape regex metacharacters)
TOPIC_RE="$(printf '%s' "$TOPIC" | sed 's/[][\.^$*+?(){}|/]/\\&/g')"
# a [[ ... topic ... ]] wikilink: bare or path-prefixed, optionally aliased
LINK_RE="\[\[([^]|]*/)?${TOPIC_RE}(\||\])"

# --- STOP / scaffold: -Op + on a missing goal item (contract stop-rule) -----------
if [ "$OP" = "+" ] && [ ! -f "$GOAL_FILE" ]; then
  if [ "$CREATE_GOAL" -ne 1 ]; then
    echo "HUMAN_DECISION_REQUIRED goal item missing: goal/$TOPIC.md does not exist. Pass --create-goal to scaffold it, or create the goal item first."
    ratmac_contract 'Run mode=single' "Active proj=$PROJ_NAME" "Active slice=$SNAME" "Human decisions required=goal/$TOPIC.md missing — pass --create-goal"; exit 3
  fi
  # scaffold goal/<topic>.md from the goal-topic template (current: false; goal is SSoT, S12)
  TPL="$(dirname "$(dirname "$0")")/../ratmac-kickoff/templates/goal-topic.md.tpl"
  PROBLEM="$REASON"; [ -n "$PROBLEM" ] || PROBLEM="TODO: describe goal $TOPIC"
  BODY="$(ratmac_expand "$TPL" "STAMP=$STAMP" "NAME=$TOPIC" "PROBLEM=$PROBLEM")"
  mkdir -p "$(dirname "$GOAL_FILE")"
  # printf '%s\n' (NOT '%s') so the goal-topic file gets exactly one trailing LF, matching
  # kickoff.sh's emit and scope.ps1's Set-RatmacFileLines goal write (R4/R10; see defect 6).
  printf '%s\n' "$BODY" > "$GOAL_FILE"
  add_touched "$GOAL_FILE"
  GOAL_CREATED=1
fi

# --- STOP: -Op - on a ref that scope.md does not carry ----------------------------
if [ "$OP" = "-" ] && ! grep -qE "$LINK_RE" "$SCOPE"; then
  echo "BLOCKED scope contract: '$TOPIC' is not in $SNAME/scope.md (nothing to remove)"
  ratmac_contract 'Run mode=single' "Active proj=$PROJ_NAME" "Active slice=$SNAME" "Blocked items='$TOPIC' not in scope"; exit 2
fi

# --- edit scope.md: add/remove the [[<topic>]] ref (regen scans these wikilinks) --
ALREADY=0
if grep -qE "$LINK_RE" "$SCOPE"; then ALREADY=1; fi
SCOPE_CHANGED=0
BULLET="- [[$TOPIC]]"
if [ "$OP" = "+" ]; then
  if [ "$ALREADY" -ne 1 ]; then
    # append the ref bullet after the last non-blank body line
    awk -v bullet="$BULLET" '
      { lines[NR] = $0 }
      END {
        last = NR
        while (last > 0 && lines[last] ~ /^[[:space:]]*$/) { last-- }
        for (i = 1; i <= last; i++) print lines[i]
        print bullet
        for (i = last + 1; i <= NR; i++) print lines[i]
      }
    ' "$SCOPE" > "$SCOPE.tmp" && mv "$SCOPE.tmp" "$SCOPE"
    SCOPE_CHANGED=1
  fi
else
  # remove the first bullet line carrying the topic wikilink. Build the ERE inside
  # awk from escaped bracket atoms (gawk warns on literal '\[' in the awk SOURCE, but
  # an escaped bracket assembled into a string VARIABLE is fine); semantics mirror the
  # grep -E LINK_RE above: \[\[ (opt path prefix) <topic> (\| | \]\]).
  awk -v topic="$TOPIC_RE" '
    BEGIN {
      lb = "\\["; rb = "\\]"
      re = lb lb "(" "[^" rb "|]*/" ")?" topic "(\\|" "|" rb rb ")"
    }
    !done && $0 ~ re { done=1; next }
    { print }
  ' "$SCOPE" > "$SCOPE.tmp" && mv "$SCOPE.tmp" "$SCOPE"
  SCOPE_CHANGED=1
fi
if [ "$SCOPE_CHANGED" -eq 1 ]; then
  ratmac_fm_set "$SCOPE" time-modified "$STAMP" "$STAMP"
  add_touched "$SCOPE"
fi

# --- append-only scope-history.md line (S14): "+/- <ref> <reason> <YYYY-MM-DD>" ----
REASON_TEXT="$REASON"; [ -n "$REASON_TEXT" ] || REASON_TEXT='—'
HIST_LINE="$OP $TOPIC $REASON_TEXT $DATE"
if [ ! -f "$HIST" ]; then
  mkdir -p "$(dirname "$HIST")"
  printf -- '---\ntime-created: %s\ntime-modified: %s\n---\n\n# scope-history — %s\n\n%s\n' \
    "$STAMP" "$STAMP" "$SNAME" "$HIST_LINE" > "$HIST"
else
  printf '%s\n' "$HIST_LINE" >> "$HIST"
  ratmac_fm_set "$HIST" time-modified "$STAMP" "$STAMP"
fi
add_touched "$HIST"

# --- slice log line (S19): "<ts> scope+|- <ref>" ----------------------------------
ratmac_log "$SLOG" "scope$OP" "$TOPIC" "$STAMP"
add_touched "$SLOG"

# --- post: trigger regen so scope-residual.md + goal-residual.md refresh (R18) ----
REGEN_SH="$(dirname "$(dirname "$0")")/../ratmac-regen/scripts/regen.sh"
REGEN_RESULT='not run'
if [ -f "$REGEN_SH" ]; then
  REGEN_ARGS=()
  [ -n "$ROOT_ARG" ] && REGEN_ARGS+=(--root "$ROOT_ARG")
  [ -n "$PROJ" ]     && REGEN_ARGS+=(--proj "$PROJ")
  [ -n "$TS" ]       && REGEN_ARGS+=(--ts "$TS")
  REGEN_RC=0
  bash "$REGEN_SH" "${REGEN_ARGS[@]+"${REGEN_ARGS[@]}"}" >/dev/null 2>&1 || REGEN_RC=$?
  if [ "$REGEN_RC" -eq 0 ]; then REGEN_RESULT='regen spawned'; else REGEN_RESULT="FAILED (regen exit $REGEN_RC; rollup stale)"; fi
fi

# --- report + contract ------------------------------------------------------------
if [ "$OP" = "+" ]; then VERB='scope+'; else VERB='scope-'; fi
if [ "$GOAL_CREATED" -eq 1 ]; then
  echo "$VERB $TOPIC in $SNAME (goal item scaffolded, current: false)"
else
  echo "$VERB $TOPIC in $SNAME"
fi
if [ "$SCOPE_CHANGED" -eq 0 ] && [ "$OP" = "+" ]; then
  echo "  note: '$TOPIC' already in scope (no-op add)"
fi

ratmac_contract \
  'Run mode=single' \
  "Active proj=$PROJ_NAME" \
  "Active slice=$SNAME" \
  "Classification=scope-mutation:$OP" \
  'Skill chain=ratmac-scope -> ratmac-regen' \
  "Files touched=$TOUCHED" \
  "Regen result=$REGEN_RESULT" \
  'Next safe action=ratmac-lint to verify scope/residual consistency'
