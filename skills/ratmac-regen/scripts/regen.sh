#!/usr/bin/env bash
# ratmac-regen — POSIX shadow of regen.ps1 (R4 parity; pwsh is primary).
# Rebuild GENERATED content from source-of-truth (S13, S20). Idempotent (R10).
# Rebuilds: goal-residual / scope-residual / issues-residual (whole-file, S13) and
# the fenced ## affects rollups in slice + proj state.md (S20). Only generated
# regions are touched (R6). Writes only under scheduler/ (R5).
set -euo pipefail

. "$(dirname "$0")/_common.sh"

# --- arg parse (long flags, manual while-loop) ------------------------------------
ROOT_ARG=""; PROJ_ARG=""; TIER="all"; TS_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)   ROOT_ARG="${2:-}"; shift 2 ;;
    --proj)   PROJ_ARG="${2:-}"; shift 2 ;;
    --tier)   TIER="${2:-}"; shift 2 ;;
    --ts)     TS_ARG="${2:-}"; shift 2 ;;
    --root=*) ROOT_ARG="${1#*=}"; shift ;;
    --proj=*) PROJ_ARG="${1#*=}"; shift ;;
    --tier=*) TIER="${1#*=}"; shift ;;
    --ts=*)   TS_ARG="${1#*=}"; shift ;;
    *) echo "BLOCKED: unknown arg '$1' (expected --root|--proj|--tier|--ts)" >&2
       ratmac_contract 'Run mode=single' "Blocked items=unknown arg $1"; exit 2 ;;
  esac
done

case "$TIER" in
  all|proj|slice) ;;
  *) echo "BLOCKED: --tier must be one of all|proj|slice (got '$TIER')" >&2
     ratmac_contract 'Run mode=single' "Blocked items=bad tier '$TIER'"; exit 2 ;;
esac

# --- resolve context (engine fns) -------------------------------------------------
STAMP="$(ratmac_stamp "$TS_ARG")"
PROJ_LINE="$(ratmac_proj "$ROOT_ARG" "$PROJ_ARG")" || {
  ratmac_contract 'Run mode=single' 'Blocked items=cannot resolve project'; exit 2
}
IFS=$'\t' read -r SCHED PROJ PDIR <<EOF
$PROJ_LINE
EOF
MODE="$(ratmac_mode "$PDIR")"

REBUILT=0
GENERATED=""

gen_add() {  # arg1: abs path of a rebuilt generated file
  local p="${1//\\//}"
  if [ -z "$GENERATED" ]; then GENERATED="$p"; else GENERATED="$GENERATED, $p"; fi
}

# --- whole-file residual writer (S13: GENERATED sentinel on line 1) ---------------
# Mirrors Write-Residual: compares ignoring the time-(created|modified) lines so a
# stable input yields a stable result (R10); preserves the original time-created.
# Body lines arrive on stdin. Returns 0 if it wrote, 1 if no change.
write_residual() {  # arg1: path, arg2: title
  local path="$1" title="$2" body
  body="$(cat)"
  body="${body%$'\n'}"

  # assemble the new file
  local new
  new="$(printf '%s\n' \
    '<!-- GENERATED — do not edit -->' \
    '---' \
    "time-created: $STAMP" \
    "time-modified: $STAMP" \
    '---' \
    '' \
    "# $title" \
    '')"
  # blank line BETWEEN the "# <title>" header and the body, matching Write-Residual's
  # ($header + @('') + $body): the trailing '' arg above is eaten by $()'s newline strip,
  # so append the separator explicitly. Without it the two engines diverge by one blank
  # line on non-empty residuals and churn each other's whole-file output forever (R4/R10).
  if [ -n "$body" ]; then new="$new"$'\n\n'"$body"; fi

  # compare ignoring the time-(created|modified) lines
  local strip_old strip_new
  if [ -f "$path" ]; then
    strip_old="$(grep -vE '^time-(created|modified):' "$path" || true)"
  else
    strip_old=""
  fi
  strip_new="$(printf '%s\n' "$new" | grep -vE '^time-(created|modified):' || true)"
  if [ "$strip_old" = "$strip_new" ]; then return 1; fi

  # preserve original time-created if present
  if [ -f "$path" ]; then
    local tc; tc="$(ratmac_fm_get "$path" time-created)"
    if [ -n "$tc" ]; then
      new="$(printf '%s\n' "$new" | sed "0,/^time-created:.*/s//time-created: $tc/")"
    fi
  fi

  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$new" > "$path"
  return 0
}

# --- [sole|dual] goal-residual: goal items where current: false -------------------
case "$MODE" in
  sole|dual)
    GOAL_DIR="$PDIR/goal"
    PROJ_NAME="$(basename "$PDIR")"
    # goal items in sorted basename order (Sort-Object Name in pwsh)
    PENDING=""
    if [ -d "$GOAL_DIR" ]; then
      while IFS= read -r g; do
        [ -n "$g" ] || continue
        cur="$(ratmac_fm_get "$g" current)"
        if [ "$(printf '%s' "$cur" | tr '[:upper:]' '[:lower:]')" != "true" ]; then
          base="$(basename "$g")"; base="${base%.md}"
          PENDING="${PENDING}- [[/$PROJ_NAME/goal/$base|$base]]"$'\n'
        fi
      done < <(find "$GOAL_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
    fi
    GR="$PDIR/goal-residual.md"
    if printf '%s' "${PENDING%$'\n'}" | write_residual "$GR" 'goal-residual (goal − current)'; then
      REBUILT=$((REBUILT + 1)); gen_add "$GR"
    fi
    ;;
esac

# --- per-slice residuals + fenced affects rollup ----------------------------------
# Accumulate slice rollups for the proj union (one tmp file per slice name).
ROLLUP_DIR="$(mktemp -d)"
trap 'rm -rf "$ROLLUP_DIR"' EXIT

for sdir in "$PDIR"/s-*; do
  [ -d "$sdir" ] || continue
  sname="$(basename "$sdir")"
  [ "$sname" = "archive" ] && continue

  # union of ## affects from archived tasks (frozen lists, S18) + in-flight grad tasks
  AFF=""
  arch="$sdir/archive"
  if [ -d "$arch" ]; then
    for td in "$arch"/t-*; do
      [ -d "$td" ] || continue
      while IFS= read -r a; do
        [ -n "$a" ] || continue
        AFF="${AFF}${a}"$'\n'
      done < <(ratmac_affects_list "$td/state.md")
    done
  fi
  grad="$sdir/grad"
  if [ -d "$grad" ]; then
    for td in "$grad"/t-*; do
      [ -d "$td" ] || continue
      while IFS= read -r a; do
        [ -n "$a" ] || continue
        AFF="${AFF}${a}"$'\n'
      done < <(ratmac_affects_list "$td/state.md")
    done
  fi

  # sorted, de-duplicated — LC_ALL=C forces byte-order collation so this matches the
  # ordinal Sort in regen.ps1; otherwise the two engines emit the same set in different
  # order and churn each other's GENERATED region forever (R6/R10/S20).
  SORTED=""
  if [ -n "$AFF" ]; then
    SORTED="$(printf '%s' "$AFF" | sed '/^$/d' | LC_ALL=C sort -u)"
  fi
  # stash for the proj rollup
  printf '%s\n' "$SORTED" > "$ROLLUP_DIR/$sname"

  # body: "- <item>" per affects entry, then write the fenced rollup in slice state
  SSTATE="$sdir/state.md"
  if [ -f "$SSTATE" ]; then
    BODY=""
    if [ -n "$SORTED" ]; then
      while IFS= read -r a; do
        [ -n "$a" ] || continue
        BODY="${BODY}- ${a}"$'\n'
      done <<EOF
$SORTED
EOF
    fi
    if printf '%s' "${BODY%$'\n'}" | ratmac_fence_set "$SSTATE" affects "$STAMP"; then
      REBUILT=$((REBUILT + 1)); gen_add "$SSTATE"
    fi
  fi

  # [sole|dual] scope-residual: scope refs whose goal item is still current:false
  case "$MODE" in
    sole|dual)
      PROJ_NAME="$(basename "$PDIR")"
      GOAL_DIR="$PDIR/goal"
      SCOPE="$sdir/scope.md"
      RESID=""
      if [ -f "$SCOPE" ]; then
        # extract last path segment of each [[...]] wikilink target
        while IFS= read -r r; do
          [ -n "$r" ] || continue
          gf="$GOAL_DIR/$r.md"
          if [ -f "$gf" ]; then
            cur="$(ratmac_fm_get "$gf" current)"
            if [ "$(printf '%s' "$cur" | tr '[:upper:]' '[:lower:]')" != "true" ]; then
              RESID="${RESID}- [[/$PROJ_NAME/goal/$r|$r]]"$'\n'
            fi
          else
            RESID="${RESID}- $r (goal item missing)"$'\n'
          fi
        done < <(grep -oE '\[\[[^]|]+' "$SCOPE" 2>/dev/null \
                   | sed 's/^\[\[//' \
                   | awk -F/ '{print $NF}')
      fi
      SR="$sdir/scope-residual.md"
      if printf '%s' "${RESID%$'\n'}" | write_residual "$SR" "scope-residual — $sname (scope − current)"; then
        REBUILT=$((REBUILT + 1)); gen_add "$SR"
      fi
      ;;
  esac

  # [maintainer|dual] issues-residual: open issue tags on grad tasks
  case "$MODE" in
    maintainer|dual)
      OPEN=""
      if [ -d "$grad" ]; then
        for td in "$grad"/t-*; do
          [ -d "$td" ] || continue
          tname="$(basename "$td")"
          issue="$(ratmac_fm_get "$td/state.md" issue)"
          status="$(ratmac_fm_get "$td/state.md" status)"
          if [ -n "$issue" ] && [ "$status" != "done" ]; then
            OPEN="${OPEN}- $issue — [[$tname]] ($status)"$'\n'
          fi
        done
      fi
      IR="$sdir/issues-residual.md"
      if printf '%s' "${OPEN%$'\n'}" | write_residual "$IR" "issues-residual — $sname (open assigned issues)"; then
        REBUILT=$((REBUILT + 1)); gen_add "$IR"
      fi
      ;;
  esac
done

# --- proj fenced affects rollup (union of LIVE slice rollups + ARCHIVED slices) ---
# Lifecycle step-7 durability (defect 2): the proj ## affects rollup is a CUMULATIVE record.
# transit freezes the closing slice's affects into the proj rollup via a regen-before-mv, but
# a later standalone regen would rebuild from live slices only and ERASE the archived
# contribution. Fold each <proj>/archive/s-*/state.md's already-frozen ## affects rollup into
# the union too (ratmac_affects_list skips the GENERATED markers and yields the frozen bullets).
case "$TIER" in
  all|proj)
    PALL=""
    for rf in "$ROLLUP_DIR"/*; do
      [ -e "$rf" ] || continue
      while IFS= read -r a; do
        [ -n "$a" ] || continue
        PALL="${PALL}${a}"$'\n'
      done < "$rf"
    done
    if [ -d "$PDIR/archive" ]; then
      for asd in "$PDIR"/archive/s-*; do
        [ -d "$asd" ] || continue
        while IFS= read -r a; do
          [ -n "$a" ] || continue
          PALL="${PALL}${a}"$'\n'
        done < <(ratmac_affects_list "$asd/state.md")
      done
    fi
    PSORTED=""
    if [ -n "$PALL" ]; then
      # LC_ALL=C byte-order collation to match the ordinal Sort in regen.ps1 (see slice note).
      PSORTED="$(printf '%s' "$PALL" | sed '/^$/d' | LC_ALL=C sort -u)"
    fi
    PBODY=""
    if [ -n "$PSORTED" ]; then
      while IFS= read -r a; do
        [ -n "$a" ] || continue
        PBODY="${PBODY}- ${a}"$'\n'
      done <<EOF
$PSORTED
EOF
    fi
    PSTATE="$PDIR/state.md"
    if [ -f "$PSTATE" ]; then
      if printf '%s' "${PBODY%$'\n'}" | ratmac_fence_set "$PSTATE" affects "$STAMP"; then
        REBUILT=$((REBUILT + 1)); gen_add "$PSTATE"
      fi
    fi
    ;;
esac

# --- report + contract ------------------------------------------------------------
echo "regen: $REBUILT generated region(s) rebuilt"

if [ "$REBUILT" -eq 0 ]; then
  RESULT="hash-stable (no drift)"
else
  RESULT="$REBUILT regions rebuilt"
fi

ratmac_contract \
  'Run mode=single' \
  "Active proj=$PROJ" \
  "Files generated=$GENERATED" \
  "Regen result=$RESULT" \
  'Next safe action=ratmac-lint to verify'
