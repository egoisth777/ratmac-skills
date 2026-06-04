#!/usr/bin/env bash
# ratmac-lint — read-only schema + invariant + fence audit (R11: NEVER writes, even --strict).
# POSIX shadow of lint.ps1 (R4 verb parity; pwsh is primary). Walks the resolved proj tree
# (proj state.md/log.md, each slice state.md/log.md, grad+archive task issue/task/state/log,
# residuals) and reports a violations table. Covers scheduler-sys invariants S5 (frontmatter),
# S7 (naming prefixes), S13 (residual sentinel), S15/S16 (issue tag), S18 (## affects on done
# tasks), S20 (GENERATED fence balance), plus dangling [[t-...]] links. --strict adds the
# per-mode required-files layout audit (layout.md table). Mirrors arca-lint shape.
set -euo pipefail

. "$(dirname "$0")/_common.sh"

# --- arg parse (long flags, manual while-loop; mirrors lint.ps1 params) ------------
ROOT_ARG=""; PROJ_ARG=""; STRICT=0; RULES_CSV=""; TS=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)    ROOT_ARG="${2:-}"; shift 2 ;;
    --proj)    PROJ_ARG="${2:-}"; shift 2 ;;
    --strict)  STRICT=1; shift ;;
    --rules)   RULES_CSV="${2:-}"; shift 2 ;;
    --ts)      TS="${2:-}"; shift 2 ;;
    --root=*)  ROOT_ARG="${1#*=}"; shift ;;
    --proj=*)  PROJ_ARG="${1#*=}"; shift ;;
    --rules=*) RULES_CSV="${1#*=}"; shift ;;
    --ts=*)    TS="${1#*=}"; shift ;;
    # No --force: lint.ps1 has no -Force param (R4 flag-surface parity); lint is read-only
    # (R11) so a force-write override is meaningless. --force falls through to BLOCKED.
    *) echo "BLOCKED: unknown flag '$1' (expected --root|--proj|--strict|--rules|--ts)" >&2
       ratmac_contract 'Run mode=single' 'Files touched=— (read-only, R11)' "Blocked items=unknown flag $1"
       exit 2 ;;
  esac
done

# want <rule> → 0 if rule is in scope (no --rules means all rules)
want() {
  [ -z "$RULES_CSV" ] && return 0
  printf '%s' "$RULES_CSV" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -qx "$1"
}

# --- resolve the proj tree (read-only; STOP if unresolvable — before the contract, exit 2)
# R11: lint NEVER writes — not even scratch files. Capture the resolver output (merging its
# BLOCKED stderr) into a shell variable via command substitution instead of a /tmp scratch
# file, so a read-only or shared /tmp can never break lint or leak a PID file. On success the
# captured text is the tab-separated proj line; on failure it carries the BLOCKED: reason.
PROJ_LINE=""
if ! PROJ_LINE="$(ratmac_proj "$ROOT_ARG" "$PROJ_ARG" 2>&1)"; then
  REASON="$(printf '%s\n' "$PROJ_LINE" | sed 's/^BLOCKED: *//' | head -n1)"
  [ -n "$REASON" ] || REASON="no resolvable project"
  echo "BLOCKED $REASON"
  ratmac_contract \
    "Run mode=single" \
    "Files touched=— (read-only, R11)" \
    "Blocked items=no resolvable project"
  exit 2
fi
IFS=$'\t' read -r SCHED PROJ PDIR <<EOF
$PROJ_LINE
EOF
MODE="$(ratmac_mode "$PDIR")"

# --- violation accumulator (mirror arca-lint V; collector-only, no stdout) ---------
VIOL=""   # one record per line: severity\trule\tpath\tmessage\tfix
ERRS=0; WARNS=0
V() {  # sev rule path msg fix
  local sev="$1" rule="$2" path="$3" msg="$4" fix="$5"
  path="$(printf '%s' "$path" | tr '\\' '/')"
  VIOL="${VIOL}${sev}	${rule}	${path}	${msg}	${fix}
"
  if [ "$sev" = "error" ]; then ERRS=$((ERRS+1)); else WARNS=$((WARNS+1)); fi
}

# --- shared helpers ---------------------------------------------------------------
# S5: every md needs time-created + time-modified frontmatter.
audit_frontmatter() {  # arg1: path
  local path="$1" k v
  [ -f "$path" ] || return 0
  for k in time-created time-modified; do
    v="$(ratmac_fm_get "$path" "$k")"
    if [ -z "$(printf '%s' "$v" | sed 's/^ *//; s/ *$//')" ] && want S5; then
      V error S5 "$path" "missing $k frontmatter" "add ${k}: <YYYY-MM-DD-HH:MM:SS> to frontmatter"
    fi
  done
  return 0
}

# S20: GENERATED / /GENERATED fence markers must balance (open==close, never close-before-open).
audit_fence() {  # arg1: path
  local path="$1"
  [ -f "$path" ] || return 0
  local bad
  bad="$(awk '
    BEGIN{opens=0; closes=0; depth=0; bad=0}
    /<!--[[:space:]]*\/GENERATED[[:space:]]*-->/ { closes++; depth--; if(depth<0){bad=1}; next }
    /<!--[[:space:]]*GENERATED/                  { opens++; depth++; next }
    END{ printf "%d\t%d\t%d", opens, closes, bad }
  ' "$path")"
  local opens closes flag
  IFS=$'\t' read -r opens closes flag <<EOF
$bad
EOF
  if { [ "$opens" != "$closes" ] || [ "$flag" = "1" ]; } && want S20; then
    V error S20 "$path" "unbalanced GENERATED fence ($opens open / $closes close)" 'restore matched <!-- GENERATED --> ... <!-- /GENERATED --> pair; rerun ratmac-regen'
  fi
  return 0
}

# dangling [[t-...]] link: target task dir must live in grad/ or archive/ of arg2 (slice path).
# R11: accumulate candidates in a shell variable (like the VIOL accumulator) — NO /tmp file.
# The grep candidates are captured via command substitution into a string, then iterated with
# a here-string so each V() call runs in THIS shell (a `grep | while` pipe would lose the
# VIOL/WARNS mutations to its subshell, which is why the old code shuttled through /tmp).
audit_dangling_task_links() {  # arg1: path, arg2: slice path
  local path="$1" sp="$2" tgt cand
  [ -f "$path" ] || return 0
  [ -n "$sp" ] || return 0
  want dangling || return 0
  cand="$(grep -oE '\[\[t-[^]|/]+' "$path" 2>/dev/null | sed 's/^\[\[//' || true)"
  [ -n "$cand" ] || return 0
  while IFS= read -r tgt; do
    tgt="$(printf '%s' "$tgt" | sed 's/^ *//; s/ *$//')"
    [ -n "$tgt" ] || continue
    if [ ! -d "$sp/grad/$tgt" ] && [ ! -d "$sp/archive/$tgt" ]; then
      V warn dangling "$path" "dangling link [[${tgt}]] — task in neither grad/ nor archive/" 'fix link target or kickoff the task'
    fi
  done <<EOF
$cand
EOF
  return 0
}

# --strict: assert a required file is present for the active mode (layout.md table).
audit_required() {  # arg1: path, arg2: reason
  local path="$1" reason="$2"
  [ "$STRICT" -eq 1 ] || return 0
  want layout || return 0
  if [ ! -e "$path" ]; then
    V error layout "$path" "required file missing ($reason)" 'scaffold via ratmac-kickoff for this tier/mode'
  fi
  return 0
}

# S13: residual files carry a "<!-- GENERATED" sentinel on line 1 (whole-file generated).
audit_residual() {  # arg1: path
  local path="$1" first
  [ -f "$path" ] || return 0
  audit_frontmatter "$path"
  if want S13; then
    first="$(head -n1 "$path")"
    case "$first" in
      '<!-- GENERATED'*|'<!--	GENERATED'*) : ;;
      *) V warn S13 "$path" 'residual missing "<!-- GENERATED" sentinel on line 1' 'rerun ratmac-regen (whole-file generated, S13)' ;;
    esac
  fi
  return 0
}

case "$MODE" in
  sole|dual) SOLE_DUAL=1 ;;
  *)         SOLE_DUAL=0 ;;
esac
case "$MODE" in
  maintainer|dual) MAINT_DUAL=1 ;;
  *)               MAINT_DUAL=0 ;;
esac

# --- proj tier --------------------------------------------------------------------
PSTATE="$PDIR/state.md"
if [ -f "$PSTATE" ]; then
  audit_frontmatter "$PSTATE"
  if [ -z "$(ratmac_fm_get "$PSTATE" status | sed 's/^ *//; s/ *$//')" ] && want S5; then
    V error S5 "$PSTATE" 'state.md missing status' 'add status: active|done|abandoned'
  fi
  if [ -z "$(ratmac_fm_get "$PSTATE" mode | sed 's/^ *//; s/ *$//')" ] && want S5; then
    V error S5 "$PSTATE" 'proj state.md missing mode' 'add mode: maintainer|sole|dual'
  fi
  audit_fence "$PSTATE"
elif want S5; then
  V error S5 "$PSTATE" 'proj state.md missing' 'scaffold proj via ratmac-kickoff -Tier proj'
fi
# S7: proj dir name prefix
PLEAF="$(basename "$PDIR")"
case "$PLEAF" in
  p-*) : ;;
  *) if want S7; then V error S7 "$PDIR" "proj dir '$PLEAF' lacks p- prefix" 'rename dir to p-<name> (breaks [[…]] links; fix manually)'; fi ;;
esac
# --strict proj-tier required files.
# NOTE: *-residual.md files are GENERATED lazily by ratmac-regen, NOT scaffolded by
# ratmac-kickoff, so a freshly-kicked-off tier legitimately lacks them until the first
# regen. They are therefore EXCLUDED from the --strict required-files audit (only their
# S13 sentinel is checked, in audit_residual, once they exist) — keeping lint in agreement
# with kickoff's scaffold set and with lint.ps1 (R4). Run ratmac-regen to materialize them.
audit_required "$PDIR/log.md" 'proj log.md (all modes)'
if [ "$SOLE_DUAL" -eq 1 ]; then
  audit_required "$PDIR/goal" 'goal/ dir (sole|dual)'
fi

# --- residuals (proj-level): S13 sentinel on line 1 -------------------------------
for r in "$PDIR"/*-residual.md; do
  [ -f "$r" ] || continue
  audit_residual "$r"
done

# --- slice tier -------------------------------------------------------------------
for sdir in "$PDIR"/s-*; do
  [ -d "$sdir" ] || continue
  SLEAF="$(basename "$sdir")"
  if [ "$SLEAF" = "archive" ]; then continue; fi
  SPATH="$sdir"
  # S7: slice dir prefix (already filtered to s-*, but assert for completeness on odd casing)
  case "$SLEAF" in
    s-*) : ;;
    *) if want S7; then V error S7 "$SPATH" "slice dir '$SLEAF' lacks s- prefix" 'rename dir to s-<name>'; fi ;;
  esac
  SSTATE="$SPATH/state.md"
  if [ -f "$SSTATE" ]; then
    audit_frontmatter "$SSTATE"
    if [ -z "$(ratmac_fm_get "$SSTATE" status | sed 's/^ *//; s/ *$//')" ] && want S5; then
      V error S5 "$SSTATE" 'state.md missing status' 'add status: active|done|abandoned'
    fi
    audit_fence "$SSTATE"
    audit_dangling_task_links "$SSTATE" "$SPATH"
  elif want S5; then
    V error S5 "$SSTATE" 'slice state.md missing' 'scaffold slice via ratmac-kickoff -Tier slice'
  fi
  audit_required "$SSTATE" 'slice state.md (all modes)'
  audit_required "$SPATH/log.md" 'slice log.md (all modes)'
  if [ "$SOLE_DUAL" -eq 1 ]; then
    audit_required "$SPATH/scope.md" 'scope.md (sole|dual)'
    audit_required "$SPATH/scope-history.md" 'scope-history.md (sole|dual)'
    # scope-residual.md is regen-generated, not kickoff-scaffolded — excluded (see proj note).
  fi
  # issues-residual.md is regen-generated, not kickoff-scaffolded — excluded (see proj note).
  # slice residuals: S13 sentinel
  for r in "$SPATH"/*-residual.md; do
    [ -f "$r" ] || continue
    audit_residual "$r"
  done
  # slice log frontmatter
  audit_frontmatter "$SPATH/log.md"

  # --- task tier (grad/ + archive/) ---------------------------------------------
  for bucket in grad archive; do
    BDIR="$SPATH/$bucket"
    [ -d "$BDIR" ] || continue
    for td in "$BDIR"/*; do
      [ -d "$td" ] || continue
      TPATH="$td"
      TLEAF="$(basename "$td")"
      # S7: task dir prefix
      case "$TLEAF" in
        t-*) : ;;
        *) if want S7; then V error S7 "$TPATH" "task dir '$TLEAF' lacks t- prefix" 'rename dir to t-<kebab>'; fi ;;
      esac
      # S5 frontmatter on issue/task/state/log
      for leaf in issue.md task.md state.md log.md; do
        audit_frontmatter "$TPATH/$leaf"
      done
      TSTATE="$TPATH/state.md"
      if [ -f "$TSTATE" ]; then
        TSTATUS="$(ratmac_fm_get "$TSTATE" status | sed 's/^ *//; s/ *$//')"
        if [ -z "$TSTATUS" ] && want S5; then
          V error S5 "$TSTATE" 'state.md missing status' 'add status: active|blocked|done|abandoned'
        fi
        # S15/S16: maintainer mode requires an issue: tag (one active task per issue)
        if [ "$MAINT_DUAL" -eq 1 ] && [ "$MODE" = "maintainer" ] && want S15; then
          if [ -z "$(ratmac_fm_get "$TSTATE" issue | sed 's/^ *//; s/ *$//')" ]; then
            V error S15 "$TSTATE" 'maintainer-mode task missing issue: tag' 'add issue: <ticket-id> (one active task per issue, S15/S16)'
          fi
        fi
        # S18: a done task must carry a ## affects section
        if [ "$(printf '%s' "$TSTATUS" | tr 'A-Z' 'a-z')" = "done" ] && want S18; then
          if ! grep -qE '^##[[:space:]]+affects[[:space:]]*$' "$TSTATE"; then
            V warn S18 "$TSTATE" 'done task lacks "## affects" section' 'add ## affects with the files/assets touched (frozen on done, S18)'
          fi
        fi
        audit_fence "$TSTATE"
        audit_dangling_task_links "$TSTATE" "$SPATH"
      elif want S5; then
        V error S5 "$TSTATE" 'task state.md missing' 'scaffold task via ratmac-kickoff -Tier task'
      fi
      # dangling links may also live in issue.md / task.md
      audit_dangling_task_links "$TPATH/issue.md" "$SPATH"
      audit_dangling_task_links "$TPATH/task.md" "$SPATH"
    done
  done
done

# --- report (mirror arca-lint table shape) ----------------------------------------
echo "| severity | rule | path | message | fix-hint |"
echo "|---|---|---|---|---|"
if [ -n "$VIOL" ]; then
  printf '%s' "$VIOL" | while IFS=$'\t' read -r sev rule path msg fix; do
    [ -n "$sev" ] || continue
    echo "| $sev | $rule | $path | $msg | $fix |"
  done
else
  echo "| pass | — | — | no violations | — |"
fi
echo ""

if [ "$ERRS" -gt 0 ]; then
  LINT_RESULT="$ERRS error, $WARNS warn"
elif [ "$WARNS" -gt 0 ]; then
  LINT_RESULT="$WARNS warn"
else
  LINT_RESULT="pass"
fi
if [ "$STRICT" -eq 1 ]; then
  RESIDUAL="strict: per-mode layout audit run"
else
  RESIDUAL="lenient default (RQ7/a); pass --strict for the full layout audit"
fi

ratmac_contract \
  "Run mode=single" \
  "Active proj=$PROJ" \
  "Files touched=— (read-only, R11)" \
  "Lint result=$LINT_RESULT" \
  "Residual risk=$RESIDUAL"

if [ "$ERRS" -gt 0 ]; then exit 1; else exit 0; fi
