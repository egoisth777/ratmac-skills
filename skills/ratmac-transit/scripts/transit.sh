#!/usr/bin/env bash
# ratmac-transit — POSIX shadow of transit.ps1 (R4 parity; pwsh is primary).
# slice/proj transition: final regen, write summary, status:done, mv tier → archive.
# Chain: ratmac-transit -> ratmac-regen -> ratmac-lint. Writes only under scheduler/ (R5).
# Reads state first (R9). All STOPs (R12) fire BEFORE any write or regen, so an
# ambiguous tier never half-transits.
set -euo pipefail

. "$(dirname "$0")/_common.sh"

# --- arg parse (long flags, manual while-loop) ------------------------------------
TIER=""; NEW_SLICE=""; SUMMARY=""; NO_SUCCESSOR=0
ROOT_ARG=""; PROJ_ARG=""; TS_ARG=""; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tier)         TIER="${2:-}"; shift 2 ;;
    --new-slice)    NEW_SLICE="${2:-}"; shift 2 ;;
    --summary)      SUMMARY="${2:-}"; shift 2 ;;
    --no-successor) NO_SUCCESSOR=1; shift ;;
    --root)         ROOT_ARG="${2:-}"; shift 2 ;;
    --proj)         PROJ_ARG="${2:-}"; shift 2 ;;
    --ts)           TS_ARG="${2:-}"; shift 2 ;;
    --force)        FORCE=1; shift ;;
    --tier=*)         TIER="${1#*=}"; shift ;;
    --new-slice=*)    NEW_SLICE="${1#*=}"; shift ;;
    --summary=*)      SUMMARY="${1#*=}"; shift ;;
    --root=*)         ROOT_ARG="${1#*=}"; shift ;;
    --proj=*)         PROJ_ARG="${1#*=}"; shift ;;
    --ts=*)           TS_ARG="${1#*=}"; shift ;;
    *) echo "BLOCKED unknown flag: $1" >&2
       ratmac_contract 'Run mode=single' "Blocked items=unknown flag $1"; exit 2 ;;
  esac
done

# --- validate required params -----------------------------------------------------
case "$TIER" in
  slice|proj) ;;
  *) echo "BLOCKED --tier must be one of slice|proj (got '$TIER')" >&2
     ratmac_contract 'Run mode=single' "Blocked items=bad tier '$TIER'"; exit 2 ;;
esac
if [ -z "$SUMMARY" ]; then
  echo "BLOCKED --summary is required (literal text OR path to an existing file)" >&2
  ratmac_contract 'Run mode=single' 'Blocked items=missing --summary'; exit 2
fi

# --- resolve context (engine fns) -------------------------------------------------
STAMP="$(ratmac_stamp "$TS_ARG")"
PROJ_LINE="$(ratmac_proj "$ROOT_ARG" "$PROJ_ARG")" || {
  ratmac_contract 'Run mode=single' 'Blocked items=cannot resolve project'; exit 2
}
IFS=$'\t' read -r SCHED PROJ PDIR <<EOF
$PROJ_LINE
EOF

TOUCHED=""
# Single carried regen result (mirrors close.sh:187): success string unless ANY spawned
# regen returns non-zero, in which case it flips to FAILED and the rollup is stale.
REGEN_RESULT="proj rollup rebuilt (final)"
touch_add() {  # arg1: abs path that was written/moved
  local p="${1//\\//}"
  case ", $TOUCHED," in
    *", $p,"*) return 0 ;;
  esac
  if [ -z "$TOUCHED" ]; then TOUCHED="$p"; else TOUCHED="$TOUCHED, $p"; fi
}

# --- resolve sibling skill scripts for spawning (R18: spawn another skill, never self)
SKILLS_ROOT="$(dirname "$(dirname "$(dirname "$0")")")"
REGEN_SH="$SKILLS_ROOT/ratmac-regen/scripts/regen.sh"
LINT_SH="$SKILLS_ROOT/ratmac-lint/scripts/lint.sh"

run_regen() {  # final regen of proj rollup before/after the tier freezes
  [ -f "$REGEN_SH" ] || return 0
  local args=()
  [ -n "$ROOT_ARG" ] && args+=(--root "$ROOT_ARG")
  args+=(--proj "$PROJ" --ts "$STAMP")
  # Capture the spawned regen exit code (mirrors close.sh:186-187): flip the carried
  # REGEN_RESULT to FAILED on any non-zero so the receipt does not hide a stale rollup.
  local rc=0
  bash "$REGEN_SH" "${args[@]}" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && REGEN_RESULT="FAILED (regen exit $rc; rollup stale)"
  return "$rc"
}

run_lint() {  # first non-empty line of lint output → echoed to caller
  if [ ! -f "$LINT_SH" ]; then printf '%s' "ratmac-lint not run"; return 0; fi
  local args=()
  [ -n "$ROOT_ARG" ] && args+=(--root "$ROOT_ARG")
  local out first
  out="$(bash "$LINT_SH" "${args[@]}" 2>&1 || true)"
  first="$(printf '%s\n' "$out" | sed '/^[[:space:]]*$/d' | head -n 1)"
  [ -n "$first" ] && printf '%s' "$first" || printf '%s' "ratmac-lint not run"
}

# --- write summary.md (copy supplied file verbatim, else wrap literal text, Q5) ----
write_summary() {  # arg1: dest path, arg2: title
  local dest="$1" title="$2"
  if [ -f "$SUMMARY" ]; then
    # canonical LF copy (R4/R10): strip CR + collapse to a single trailing LF so the bytes
    # match transit.ps1 (Get-Content -Raw → CRLF→LF → strip one trailing newline →
    # Set-RatmacFileLines re-adds one LF). A raw `cat` would preserve the source CRLF and
    # diverge byte-for-byte from the pwsh engine.
    awk '{ sub(/\r$/, ""); print }' "$SUMMARY" > "$dest"
  else
    {
      printf '%s\n' '---'
      printf 'time-created: %s\n' "$STAMP"
      printf 'time-modified: %s\n' "$STAMP"
      printf '%s\n' '---'
      printf '\n'
      printf '# summary — %s\n' "$title"
      printf '\n'
      printf '%s\n' "$SUMMARY"
    } > "$dest"
  fi
}

# === slice tier ===================================================================
if [ "$TIER" = "slice" ]; then
  SLICE="$(ratmac_active_slice "$PDIR")"
  if [ -z "$SLICE" ]; then
    echo "BLOCKED no active slice under $PROJ"
    ratmac_contract 'Run mode=single' "Active proj=$PROJ" 'Blocked items=no active slice'; exit 2
  fi
  SNAME="$(basename "$SLICE")"

  # STOP: live tasks still in grad/ (R12 — never archive a slice with work in flight) unless --force
  LIVE=""
  GRAD="$SLICE/grad"
  if [ -d "$GRAD" ]; then
    for td in "$GRAD"/t-*; do
      [ -d "$td" ] || continue
      tname="$(basename "$td")"
      if [ -z "$LIVE" ]; then LIVE="$tname"; else LIVE="$LIVE, $tname"; fi
    done
  fi
  if [ -n "$LIVE" ] && [ "$FORCE" -ne 1 ]; then
    echo "HUMAN_DECISION_REQUIRED active tasks present: $LIVE"
    ratmac_contract \
      'Run mode=single' \
      "Active proj=$PROJ" \
      "Active slice=$SNAME" \
      'Human decisions required=close/migrate live tasks (ratmac-close) then retry, or pass --force' \
      "Blocked items=$LIVE"
    exit 3
  fi

  # STOP: no successor and not explicitly terminal (R12) — decide before any write
  if [ -z "$NEW_SLICE" ] && [ "$NO_SUCCESSOR" -ne 1 ]; then
    echo "HUMAN_DECISION_REQUIRED no successor slice"
    ratmac_contract \
      'Run mode=single' \
      "Active proj=$PROJ" \
      "Active slice=$SNAME" \
      'Human decisions required=pass --new-slice <s-name> for the successor, or --no-successor to end the line'
    exit 3
  fi

  # STOP: archive collision (close-style guard) — pre-check BEFORE any write so the mv
  # can never nest the source into an existing archive/<s-name> (R12, fires before the
  # contract). Placed after the STOP gates and before the first write.
  ARCHIVE="$PDIR/archive"
  DEST="$ARCHIVE/$SNAME"
  if [ -e "$DEST" ]; then
    echo "BLOCKED archive collision: $DEST already exists; cannot move $SNAME"
    ratmac_contract \
      'Run mode=single' \
      "Active proj=$PROJ" \
      "Active slice=$SNAME" \
      "Blocked items=archive/$SNAME exists"
    exit 2
  fi

  # 1. trigger regen so the final ## affects rollup reflects this slice before it freezes
  run_regen || true   # rc recorded into REGEN_RESULT; do not let set -e abort on stale rollup

  # 2. write summary.md
  SUMMARY_MD="$SLICE/summary.md"
  write_summary "$SUMMARY_MD" "$SNAME"
  touch_add "$SUMMARY_MD"

  # 3. status: done on slice state.md
  SSTATE="$SLICE/state.md"
  if [ -f "$SSTATE" ]; then
    ratmac_fm_set "$SSTATE" status done "$STAMP"
    touch_add "$SSTATE"
  fi

  # 3b. final proj-rollup regen BEFORE the mv (lifecycle step 7 regen-then-mv order):
  # regen enumerates only LIVE s-* children, so the closing slice's ## affects must be
  # folded into the proj rollup while the slice is still in place. Running this after the
  # mv would drop the contribution and empty the proj rollup when the last slice closes.
  run_regen || true   # rc recorded into REGEN_RESULT; do not let set -e abort on stale rollup

  # 4. mv slice dir → <proj>/archive/<s-name>  (collision pre-checked above)
  [ -d "$ARCHIVE" ] || mkdir -p "$ARCHIVE"
  mv "$SLICE" "$DEST"
  touch_add "$DEST"

  # 5. proj-tier bookkeeping: close-slice log; if --new-slice, point the proj at it (do NOT auto-create)
  PLOG="$PDIR/log.md"
  ratmac_log "$PLOG" close-slice "$SNAME" "$STAMP"
  touch_add "$PLOG"

  NEXT_NOTE=""
  if [ -n "$NEW_SLICE" ]; then
    case "$NEW_SLICE" in s-*) NEW_NAME="$NEW_SLICE" ;; *) NEW_NAME="s-$NEW_SLICE" ;; esac
    # update proj state.md "active slice:" pointer (lives under ## scratch)
    PSTATE="$PDIR/state.md"
    if [ -f "$PSTATE" ]; then
      if grep -qE '^##[[:space:]]+scratch[[:space:]]*$' "$PSTATE"; then
        if awk '
            /^##[[:space:]]+scratch[[:space:]]*$/ {ins=1; next}
            ins && /^##[[:space:]]/ {ins=0}
            ins && /^active slice:/ {found=1}
            END{exit found?0:1}
          ' "$PSTATE"; then
          # replace existing active slice line within the scratch section
          awk -v ns="$NEW_NAME" '
            /^##[[:space:]]+scratch[[:space:]]*$/ {ins=1; print; next}
            ins && /^##[[:space:]]/ {ins=0}
            ins && /^active slice:/ {print "active slice: " ns; next}
            {print}
          ' "$PSTATE" > "$PSTATE.tmp" && mv "$PSTATE.tmp" "$PSTATE"
        else
          # insert an active slice line right after the scratch heading
          awk -v ns="$NEW_NAME" '
            {print}
            !ins && /^##[[:space:]]+scratch[[:space:]]*$/ {print "active slice: " ns; ins=1}
          ' "$PSTATE" > "$PSTATE.tmp" && mv "$PSTATE.tmp" "$PSTATE"
        fi
      else
        # no scratch section — append one
        printf '\n## scratch\nactive slice: %s\n' "$NEW_NAME" >> "$PSTATE"
      fi
      ratmac_fm_set "$PSTATE" time-modified "$STAMP" "$STAMP"
      touch_add "$PSTATE"
    fi
    ratmac_log "$PLOG" active-slice "$NEW_NAME" "$STAMP"
    NEXT_NOTE="ratmac-kickoff -Tier slice -Name $NEW_NAME (NOT auto-created — kickoff is the next step)"
  else
    NEXT_NOTE="no successor (--no-successor): slice line ended"
  fi

  # 6. lint to verify the archived tree. NOTE: do NOT regen here — the proj rollup was
  # already settled at step 3b while the slice was live; a post-mv regen would re-enumerate
  # only the remaining live slices and drop the just-archived slice's affects (lifecycle 7).
  LINT_RESULT="$(run_lint)"

  echo "transit slice: $SNAME archived under $PROJ"
  if [ -n "$NEW_SLICE" ]; then echo "  next: $NEXT_NOTE"; else echo "  $NEXT_NOTE"; fi
  ratmac_contract \
    'Run mode=single' \
    "Active proj=$PROJ" \
    "Active slice=$SNAME (archived)" \
    'Classification=slice-transit' \
    'Skill chain=ratmac-transit -> ratmac-regen -> ratmac-lint' \
    "Files touched=$TOUCHED" \
    "Regen result=$REGEN_RESULT" \
    "Lint result=$LINT_RESULT" \
    "Next safe action=$NEXT_NOTE"
  exit 0
fi

# === proj tier ====================================================================
if [ "$TIER" = "proj" ]; then
  PSTATE="$PDIR/state.md"

  # STOP: archive collision (close-style guard) — pre-check BEFORE any write so the mv
  # can never nest the source into an existing archive/<p-name> (R12).
  ARCHIVE="$SCHED/archive"
  DEST="$ARCHIVE/$PROJ"
  if [ -e "$DEST" ]; then
    echo "BLOCKED archive collision: $DEST already exists; cannot move $PROJ"
    ratmac_contract \
      'Run mode=single' \
      "Active proj=$PROJ" \
      "Blocked items=archive/$PROJ exists"
    exit 2
  fi

  # 1. final regen of proj ## affects rollup
  run_regen || true   # rc recorded into REGEN_RESULT; do not let set -e abort on stale rollup

  # 2. write proj summary.md
  SUMMARY_MD="$PDIR/summary.md"
  write_summary "$SUMMARY_MD" "$PROJ"
  touch_add "$SUMMARY_MD"

  # 3. retired log line + status: done
  PLOG="$PDIR/log.md"
  ratmac_log "$PLOG" retired "" "$STAMP"
  touch_add "$PLOG"
  if [ -f "$PSTATE" ]; then
    ratmac_fm_set "$PSTATE" status done "$STAMP"
    touch_add "$PSTATE"
  fi

  # 4. mv proj dir → <schedRoot>/archive/<p-name>  (collision pre-checked above)
  [ -d "$ARCHIVE" ] || mkdir -p "$ARCHIVE"
  mv "$PDIR" "$DEST"
  touch_add "$DEST"

  # 5. lint to verify the archived tree
  LINT_RESULT="$(run_lint)"

  echo "transit proj: $PROJ retired → ${DEST//\\//}"
  ratmac_contract \
    'Run mode=single' \
    "Active proj=$PROJ (retired)" \
    'Classification=proj-retire' \
    'Skill chain=ratmac-transit -> ratmac-regen -> ratmac-lint' \
    "Files touched=$TOUCHED" \
    "Regen result=$REGEN_RESULT" \
    "Lint result=$LINT_RESULT" \
    'Next safe action=none — project archived'
  exit 0
fi
