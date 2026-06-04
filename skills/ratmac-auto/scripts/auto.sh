#!/usr/bin/env bash
# ratmac-auto — orchestrator. INIT->CLASSIFY->EVIDENCE->ROUTE->EXECUTE->VERIFY->REPORT.
# CONSERVATIVE (mirrors arca-auto): AUTO-RUNS only the safe read/verify ops — regen + lint.
# For ANY write branch (kickoff/checkpoint/mutate/scope/close/transit) it STOPS with
# HUMAN_DECISION_REQUIRED naming the exact ratmac-* skill + args; it never guesses a write (R12).
# Stops on ambiguity (HUMAN_DECISION_REQUIRED, exit 3) or missing artifact (BLOCKED, exit 2).
# POSIX shadow of auto.ps1 (R4: pwsh primary, this is the faithful verb-parity port).
set -euo pipefail

. "$(dirname "$0")/_common.sh"

# --- arg parse (long flags, manual while-loop; mirror auto.ps1 params + engine flags)
INTENT=""
UNTIL="user-intervention"   # next-checkpoint | task-close | slice-transit | user-intervention
ROOT_ARG=""
PROJ_ARG=""
TS_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --intent) INTENT="${2:-}"; shift 2 ;;
    --until)  UNTIL="${2:-}";  shift 2 ;;
    --root)   ROOT_ARG="${2:-}"; shift 2 ;;
    --proj)   PROJ_ARG="${2:-}"; shift 2 ;;
    --ts)     TS_ARG="${2:-}";   shift 2 ;;
    --intent=*) INTENT="${1#*=}"; shift ;;
    --until=*)  UNTIL="${1#*=}";  shift ;;
    --root=*)   ROOT_ARG="${1#*=}"; shift ;;
    --proj=*)   PROJ_ARG="${1#*=}"; shift ;;
    --ts=*)     TS_ARG="${1#*=}";   shift ;;
    # No --force: auto.ps1 has no -Force param (R4 flag-surface parity); auto is
    # conservative and STOPS on every write branch (R12), so a force override is meaningless.
    *) echo "BLOCKED: unknown flag '$1' (expected --intent|--until|--root|--proj|--ts)" >&2
       ratmac_contract 'Run mode=auto' "Blocked items=unknown flag $1"; exit 2 ;;
  esac
done

# --until validation (parity with PS ValidateSet)
case "$UNTIL" in
  next-checkpoint|task-close|slice-transit|user-intervention) : ;;
  *) echo "BLOCKED: --until must be one of next-checkpoint|task-close|slice-transit|user-intervention" >&2
     ratmac_contract 'Run mode=auto' "Blocked items=bad --until '$UNTIL'"; exit 2 ;;
esac

# locate the skills dir so we can dispatch into sibling skills: .../skills/<name>/scripts/<verb>.sh
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$(dirname "$(dirname "$SCRIPTS_DIR")")"   # .../skills
skill() { printf '%s/%s/scripts/%s.sh' "$SKILLS_DIR" "$1" "$2"; }

# common pass-through flags for delegated sibling skills
delegate_flags=()
[ -n "$ROOT_ARG" ] && delegate_flags+=(--root "$ROOT_ARG")
[ -n "$PROJ_ARG" ] && delegate_flags+=(--proj "$PROJ_ARG")
ts_flags=()
[ -n "$TS_ARG" ] && ts_flags+=(--ts "$TS_ARG")

lc="$(printf '%s' "$INTENT" | tr '[:upper:]' '[:lower:]')"

# ---------------------------------------------------------------------------------
# INIT — note R-invariants loaded (composition: ratmac-init is the stateless loader).
# ---------------------------------------------------------------------------------
echo "== ratmac-auto =="
echo "Intent: $INTENT"
echo "Until: $UNTIL"
echo "INIT: R-invariants loaded (R4/R5/R6/R7/R9/R10/R11/R12/R18); ratmac-init contract in effect."

# ---------------------------------------------------------------------------------
# CLASSIFY — spawn ratmac-route (read-only) and capture its text. Fall back to the
# engine if the POSIX route shadow is not present yet (best-effort; still faithful).
# ---------------------------------------------------------------------------------
echo "-- CLASSIFY (ratmac-route) --"
route_sh="$(skill ratmac-route route)"
routeOut=""
if [ -f "$route_sh" ]; then
  routeOut="$(bash "$route_sh" "${delegate_flags[@]}" "${ts_flags[@]}" 2>&1 || true)"
  printf '%s\n' "$routeOut"
else
  echo "(ratmac-route shadow not present; deriving route fields from engine)"
fi

# route field parser (matches route.ps1 "Label: value" lines)
route_field() {  # arg1: label
  printf '%s\n' "$routeOut" | awk -v lbl="$1" '
    BEGIN { FS=": " }
    {
      line=$0
      pfx=lbl ":"
      if (index(line, pfx)==1) {
        sub("^" lbl ": *", "", line)
        sub(/[[:space:]]*$/, "", line)
        print line
        exit
      }
    }'
}

proj="$(route_field 'Active project')"
mode="$(route_field 'Mode')"
slice="$(route_field 'Active slice')"
rawTasks="$(route_field 'Active tasks')"    # e.g. "[t-foo (active); t-bar (blocked)]"
suggest="$(route_field 'Suggested next-action mode')"

# If route was not available (or did not resolve), derive directly from the engine (R9).
if [ -z "$proj" ]; then
  if proj_line="$(ratmac_proj "$ROOT_ARG" "$PROJ_ARG" 2>/dev/null)"; then
    IFS=$'\t' read -r R_ROOT proj P_PATH <<EOF
$proj_line
EOF
    mode="$(ratmac_mode "$P_PATH")"
    sp="$(ratmac_active_slice "$P_PATH" || true)"
    if [ -n "$sp" ]; then slice="$(basename "$sp")"; else slice="—"; fi
    tasks=""
    if [ -n "$sp" ] && [ -d "$sp/grad" ]; then
      for td in "$sp"/grad/t-*; do
        [ -d "$td" ] || continue
        tst="$td/state.md"
        st="?"; [ -f "$tst" ] && st="$(ratmac_fm_get "$tst" status)"
        [ -n "$st" ] || st="?"
        if [ -n "$tasks" ]; then tasks="$tasks; $(basename "$td") ($st)"; else tasks="$(basename "$td") ($st)"; fi
      done
    fi
    rawTasks="[$tasks]"
  fi
fi

# route may have BLOCKED (no resolvable project / missing proj state). Propagate (exit 2).
if [ -z "$proj" ]; then
  echo "BLOCKED ratmac-route could not resolve the scheduler context (see route output above)."
  ratmac_contract \
    "Run mode=auto" \
    "Classification=BLOCKED" \
    "Skill chain=ratmac-route" \
    "Lint result=not-run" \
    "Regen result=not-run" \
    "Blocked items=route failed to resolve project/slice — fix scheduler context first" \
    "Next safe action=pass --root <scheduler> / --proj <p-name>, or repair the missing state.md"
  exit 2
fi

# normalize task list
tasksInner="$(printf '%s' "$rawTasks" | sed 's/^\[//; s/\]$//' | sed 's/^ *//; s/ *$//')"
activeTaskNames=()
if [ -n "$tasksInner" ]; then
  oldifs="$IFS"; IFS=';'
  for entry in $tasksInner; do
    entry="$(printf '%s' "$entry" | sed 's/^ *//; s/ *$//')"
    [ -n "$entry" ] || continue
    activeTaskNames+=("$(printf '%s' "$entry" | awk '{print $1}')")
  done
  IFS="$oldifs"
fi
hasSlice=0
case "$slice" in ""|"—") hasSlice=0 ;; *) hasSlice=1 ;; esac
singleActive=""
if [ "${#activeTaskNames[@]}" -eq 1 ]; then singleActive="${activeTaskNames[0]}"; fi

# ---------------------------------------------------------------------------------
# EVIDENCE — read the active task state.md if exactly one is in flight (R9).
# ---------------------------------------------------------------------------------
echo "-- EVIDENCE --"
taskStatus=""
evidence=""
if [ -n "$singleActive" ] && [ "$hasSlice" -eq 1 ]; then
  if proj_line="$(ratmac_proj "$ROOT_ARG" "$PROJ_ARG" 2>/dev/null)"; then
    IFS=$'\t' read -r E_ROOT E_PROJ E_PATH <<EOF
$proj_line
EOF
    sp="$(ratmac_active_slice "$E_PATH" || true)"
    if [ -n "$sp" ]; then
      tdir="$(ratmac_resolve_task "$sp" "$singleActive" || true)"
      if [ -n "$tdir" ]; then
        tstate="$tdir/state.md"
        if [ -f "$tstate" ]; then
          taskStatus="$(ratmac_fm_get "$tstate" status)"
          # pass the scheduler root UNMODIFIED so ratmac_relpath's internal dirname yields
          # the root's PARENT — matching Get-RatmacRelPath -Root $p.Root in auto.ps1. The old
          # "$E_ROOT/x" sentinel made dirname yield the root itself (one dir too shallow).
          rel="$(ratmac_relpath "$tstate" "$E_ROOT")"
          evidence="task=$singleActive status=$taskStatus state=$rel"
          echo "  $evidence"
        else
          echo "  (active task $singleActive has no state.md)"
        fi
      else
        echo "  (active task $singleActive not resolvable under grad/)"
      fi
    fi
  else
    echo "  (evidence read skipped: project not resolvable for evidence pass)"
  fi
else
  echo "  (no single active task to inspect; tasks=[$tasksInner])"
fi

# helper: STOP-with-HUMAN_DECISION_REQUIRED emitter (exit 3) ------------------------
# usage: stop_human "<reason>" "Key=Val" "Key=Val" ...
stop_human() {
  local reason="$1"; shift
  local at; if [ -n "$tasksInner" ]; then at="$tasksInner"; else at="—"; fi
  echo "HUMAN_DECISION_REQUIRED $reason"
  ratmac_contract \
    "Run mode=auto" \
    "Active proj=$proj" \
    "Active slice=$slice" \
    "Active task=$at" \
    "Skill chain=ratmac-route" \
    "Lint result=not-run" \
    "Regen result=not-run" \
    "$@"
  exit 3
}

# ---------------------------------------------------------------------------------
# ROUTE — derive the branch from route classification + intent keywords.
# Safe (AUTO-RUN): regen, lint. Everything else is a WRITE → STOP with the command.
# ---------------------------------------------------------------------------------
echo "-- ROUTE --"

# Hard stop conditions first (orchestration.md "stop conditions").
case "$mode" in
  maintainer|sole|dual) : ;;
  *)
    stop_human "proj mode undefined or invalid (mode='$mode'); cannot classify safely" \
      "Classification=STOP-MODE" \
      "Human decisions required=set a valid mode: in $proj/state.md (maintainer|sole|dual)" \
      "Next safe action=fix mode: in $proj/state.md frontmatter, then re-run ratmac-auto"
    ;;
esac

# scope-changing intent words → always escalate (orchestration.md).
if printf '%s' "$lc" | grep -qE '\b(rewrite|redesign|scrap|re-architect|overhaul)\b'; then
  stop_human "intent contains scope-changing words; needs a human design call" \
    "Classification=STOP-SCOPE" \
    "Human decisions required=rewrite/redesign/scrap is out of auto scope — decide direction by hand" \
    "Next safe action=clarify the scope change with a human before any scheduler write"
fi

# RQ14: "continue" intent but no active task to continue.
if printf '%s' "$lc" | grep -qE '\b(continue|resume|carry on|keep going)\b' && [ -z "$singleActive" ]; then
  stop_human "intent says continue but there is no single active task to resume (RQ14)" \
    "Classification=STOP" \
    "Human decisions required=which task? tasks=[$tasksInner]" \
    "Next safe action=name the task explicitly, or kickoff one: ratmac-kickoff --tier task --name <kebab>"
fi

# task slot used in suggested write commands
if [ -n "$singleActive" ]; then taskSlot="$singleActive"; else taskSlot="<t-name>"; fi

# Branch derivation. WRITE branches map to the exact skill + args; only F/G auto-run.
branch=""
writeCmd=""

if   printf '%s' "$lc" | grep -qE '\b(regen|rollup|rebuild|refresh)\b'; then
  branch="F"
elif printf '%s' "$lc" | grep -qE '\b(lint|verify|check|audit|drift|dangling)\b'; then
  branch="G"
elif { printf '%s' "$lc" | grep -qE '\b(start|new|create)\b' && printf '%s' "$lc" | grep -qE '\bproject\b'; } \
     || printf '%s' "$lc" | grep -qE '\bnew proj\b'; then
  branch="A"; writeCmd="ratmac-kickoff --tier proj --name <kebab> --mode maintainer|sole|dual"
elif printf '%s' "$lc" | grep -qE '\b(start|new|create)\b' && printf '%s' "$lc" | grep -qE '\bslice\b'; then
  branch="B"; writeCmd="ratmac-kickoff --tier slice --name <kebab>"
elif printf '%s' "$lc" | grep -qE '\b(start|new|create|kickoff)\b' && printf '%s' "$lc" | grep -qE '\btask\b'; then
  branch="C"; writeCmd="ratmac-kickoff --tier task --name <kebab> [--issue <id>] [--sprint <id>]"
elif printf '%s' "$lc" | grep -qE '\b(checkpoint|pause|snapshot|note|progress|blocked)\b'; then
  branch="D"
  writeCmd="ratmac-checkpoint --task $taskSlot --note \"<note>\" [--add-affects <p1>,<p2>] [--status active|blocked]"
elif printf '%s' "$lc" | grep -qE '\b(ticket|cr feedback|ticket update|requirement change)\b'; then
  branch="E"; writeCmd="ratmac-mutate --task $taskSlot --kind ticket --reason \"<short>\""
elif printf '%s' "$lc" | grep -qE '\b(replan|revise plan|new plan)\b'; then
  branch="F-plan"; writeCmd="ratmac-mutate --task $taskSlot --kind plan --reason \"<short>\" [--diff <task.md path>]"
elif printf '%s' "$lc" | grep -qE '\b(approach|pivot|re-approach)\b'; then
  branch="G-approach"; writeCmd="ratmac-mutate --task $taskSlot --kind approach --reason \"<short>\""
elif printf '%s' "$lc" | grep -qE '\b(done|complete|finish|land(ed)?|ship(ped)?)\b'; then
  branch="H"; writeCmd="ratmac-close --task $taskSlot --status done --cl <id> [--outcome <text>]"
elif printf '%s' "$lc" | grep -qE '\b(abandon|drop|cancel|give up)\b'; then
  branch="I"; writeCmd="ratmac-close --task $taskSlot --status abandoned --outcome \"<reason>\""
elif printf '%s' "$lc" | grep -qE '\b(scope|defer|discovered)\b'; then
  branch="J"; writeCmd="ratmac-scope --slice $slice --op +|- --ref <goal-topic> --reason \"<short>\""
elif printf '%s' "$lc" | grep -qE '\b(transit|close slice|end slice|next slice)\b'; then
  branch="K"; writeCmd="ratmac-transit --tier slice [--new-slice <name>] --summary \"<text|path>\""
elif printf '%s' "$lc" | grep -qE '\b(retire|close project|end project)\b'; then
  branch="L"; writeCmd="ratmac-transit --tier proj --summary \"<text|path>\""
fi

# No branch matched → ambiguous: do NOT guess a write (R12).
if [ -z "$branch" ]; then
  stop_human "intent did not map to a single branch; auto will not guess a write" \
    "Classification=STOP" \
    "Open questions=route suggests: $suggest" \
    "Human decisions required=pick a branch and run that ratmac-* skill explicitly" \
    "Next safe action=re-run with a clearer --intent, or invoke a ratmac-* write skill directly"
fi
echo "  Classification: $branch (intent-keyed)"

# Status ambiguity guard for write branches that target the active task.
case "$branch" in
  D|E|F-plan|G-approach|H|I)
    if [ -n "$singleActive" ] && [ -n "$taskStatus" ]; then
      case "$taskStatus" in
        active|blocked) : ;;
        *)
          stop_human "task '$singleActive' status is '$taskStatus' (not active/blocked); ambiguous for branch $branch" \
            "Classification=STOP ($branch)" \
            "Human decisions required=resolve task status before $branch" \
            "Next safe action=inspect $singleActive state.md; reconcile status, then run the write skill by hand"
          ;;
      esac
    fi
    ;;
esac

# ---------------------------------------------------------------------------------
# EXECUTE — AUTO-RUN only the safe branches (F=regen, G=lint). All writes STOP here.
# ---------------------------------------------------------------------------------
echo "-- EXECUTE --"
chain="ratmac-route"
regenResult="not-run"
lintResult="not-run"

case "$branch" in
  F)
    regen_sh="$(skill ratmac-regen regen)"
    execOut=""
    if [ -f "$regen_sh" ]; then
      execOut="$(bash "$regen_sh" "${delegate_flags[@]}" "${ts_flags[@]}" 2>&1 || true)"
      printf '%s\n' "$execOut"
    else
      echo "(ratmac-regen shadow not present)"
    fi
    chain="$chain -> ratmac-regen"
    r="$(printf '%s\n' "$execOut" | awk -F': ' '/^Regen result: /{sub(/^Regen result: */,"");print;exit}')"
    [ -z "$r" ] && r="$(printf '%s\n' "$execOut" | awk -F': ' '/^regen: /{sub(/^regen: */,"");print;exit}')"
    [ -n "$r" ] && regenResult="$r"
    ;;
  G)
    # handled in VERIFY below (lint is the verify op); nothing extra to execute.
    :
    ;;
  *)
    # WRITE branch — STOP with the exact command line + evidence (R12 / RQ9a).
    at="—"; [ -n "$tasksInner" ] && at="$tasksInner"
    oq="—"; [ -n "$evidence" ] && oq="$evidence"
    echo "HUMAN_DECISION_REQUIRED write branch '$branch' — auto will not perform a scheduler write."
    echo "  run this: $writeCmd"
    [ -n "$evidence" ] && echo "  evidence: $evidence"
    ratmac_contract \
      "Run mode=auto" \
      "Active proj=$proj" \
      "Active slice=$slice" \
      "Active task=$at" \
      "Classification=$branch" \
      "Skill chain=ratmac-route" \
      "Lint result=not-run" \
      "Regen result=not-run" \
      "Open questions=$oq" \
      "Human decisions required=confirm + run: $writeCmd" \
      "Next safe action=$writeCmd" \
      "Residual risk=no scheduler files were written by auto (conservative stance)"
    exit 3
    ;;
esac

# ---------------------------------------------------------------------------------
# VERIFY — spawn ratmac-lint (read-only, R11) and capture its result.
# ---------------------------------------------------------------------------------
echo "-- VERIFY (ratmac-lint) --"
lint_sh="$(skill ratmac-lint lint)"
lintOut=""
if [ -f "$lint_sh" ]; then
  lintOut="$(bash "$lint_sh" "${delegate_flags[@]}" 2>&1 || true)"
  printf '%s\n' "$lintOut"
else
  echo "(ratmac-lint shadow not present)"
fi
chain="$chain -> ratmac-lint"
lr="$(printf '%s\n' "$lintOut" | awk -F': ' '/^Lint result: /{sub(/^Lint result: */,"");print;exit}')"
if [ -n "$lr" ]; then
  lintResult="$lr"
else
  errn="$(printf '%s\n' "$lintOut" | grep -oiE '[0-9]+ error' | head -n1 | awk '{print $1}')"
  if [ -n "$errn" ]; then
    lintResult="$errn error(s)"
  elif [ -n "$(printf '%s' "$lintOut" | tr -d '[:space:]')" ]; then
    lintResult="ran (see output)"
  fi
fi

# ---------------------------------------------------------------------------------
# REPORT — merge into the uniform auto contract.
# ---------------------------------------------------------------------------------
case "$branch" in
  F) nextSafe="review regen diff; run ratmac-lint again if drift remained" ;;
  G) nextSafe="review lint violations; fix flagged files then re-run ratmac-lint" ;;
  *) nextSafe="invoke the suggested ratmac-* write skill explicitly" ;;
esac

at="—"; [ -n "$tasksInner" ] && at="$tasksInner"
filesGen="— (none / hash-stable)"
if [ "$branch" = "F" ] && ! printf '%s' "$regenResult" | grep -qi 'hash-stable'; then
  filesGen="see regen output"
fi
oq="—"; [ -n "$suggest" ] && oq="route suggested: $suggest"

echo "-- REPORT --"
ratmac_contract \
  "Run mode=auto" \
  "Active proj=$proj" \
  "Active slice=$slice" \
  "Active task=$at" \
  "Classification=$branch" \
  "Skill chain=$chain" \
  "Files touched=— (auto ran only read/verify ops)" \
  "Files generated=$filesGen" \
  "Lint result=$lintResult" \
  "Regen result=$regenResult" \
  "Open questions=$oq" \
  "Human decisions required=— (safe branch auto-completed; any write still needs explicit skill invocation)" \
  "Blocked items=—" \
  "Next safe action=$nextSafe" \
  "Residual risk=auto wrote nothing; only ratmac-regen (generated regions, R6/R10) may have changed bytes"
