#!/usr/bin/env bash
# smoke-test.sh — POSIX shadow of smoke-test.ps1. Drives the FULL ratmac lifecycle against the
# *.sh skill scripts on a throwaway scheduler tree with PINNED --ts values, asserting each step.
# Uses ONLY the ratmac skill scripts under skills/ratmac-*/scripts/*.sh.
# Exits 0 iff every assertion passes (else nonzero). Cleans temp unless --keep-temp.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SK="$HERE/../skills"
KEEP=0
[ "${1:-}" = "--keep-temp" ] && KEEP=1

# source the engine for the ratmac_* read helpers used in assertions
. "$SK/ratmac-kickoff/scripts/_common.sh"

run() {  # run <skill> <verb> [args...]
  local skill="$1" verb="$2"; shift 2
  bash "$SK/$skill/scripts/$verb.sh" "$@"
}

# run a .sh skill, capturing stdout (RUN_OUT) AND exit code (RUN_RC). Used by the new
# assertions that pin exact exit codes (BLOCKED=2 / HUMAN_DECISION_REQUIRED=3) and parse
# the emitted contract block. set -e is disabled inside so a non-zero exit is captured, not fatal.
run_cap() {  # run_cap <skill> <verb> [args...]
  local skill="$1" verb="$2"; shift 2
  set +e
  RUN_OUT="$(bash "$SK/$skill/scripts/$verb.sh" "$@" 2>&1)"
  RUN_RC=$?
  set -e
}

# Resolve a usable pwsh (the OTHER engine for the cross-engine byte-parity test). Empty if none.
PWSH="$(command -v pwsh 2>/dev/null || true)"

# Run the OTHER engine (pwsh *.ps1) against an already-authored tree. Sets PWSH_OUT/PWSH_RC.
# Path args destined for -Root/-Proj must be Windows-form (cygpath -m) so pwsh Resolve-Path
# accepts them. Used by the cross-engine byte-parity test (#2): a sh-authored tree regen'd by
# the pwsh engine must yield byte-identical GENERATED regions (R4 same-side-effects, R10/S20).
run_pwsh() {  # run_pwsh <skill> <verb> [args...]
  local skill="$1" verb="$2"; shift 2
  if [ -z "$PWSH" ]; then PWSH_OUT="<no pwsh found>"; PWSH_RC=127; return 0; fi
  set +e
  PWSH_OUT="$("$PWSH" -NoProfile -File "$(cygpath -m "$SK/$skill/scripts/$verb.ps1")" "$@" 2>&1)"
  PWSH_RC=$?
  set -e
}

# pull a single contract field's value out of skill stdout (the "Key: value" line inside the
# ```contract block). Echoes '' if absent. Used to assert declared chain/regen/lint verdicts (R7).
contract_field() {  # contract_field <text> <key>
  printf '%s\n' "$1" | sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" | head -n1
}

# true (0) iff text has NO interpreter stack-trace markers (degenerate-input crash guard, #3).
no_stack() {  # no_stack <text>
  ! printf '%s' "$1" | grep -qiE 'Traceback|line [0-9]+:|syntax error|unbound variable|System\.Management\.Automation|ParameterBindingException'
}

fail=0
chk(){ if [ "$1" = "1" ]; then echo "  PASS $2"; else echo "  FAIL $2"; fail=$((fail+1)); fi; }
yes_no(){ [ "$1" = "1" ] && echo 1 || echo 0; }

tmp="$(mktemp -d)"
sched="$tmp/scheduler"
mkdir -p "$sched"
export RATMAC_SCHEDULER_ROOT="$sched"
echo "sh smoke tree: $tmp"

proj="$sched/p-test"
slice="$proj/s-smoke"

# === a. kickoff proj (mode sole) ===================================================
run ratmac-kickoff kickoff --tier proj --name p-test --mode sole --ts '2026-06-03-00:00:00' >/dev/null 2>&1 || true
pstate="$proj/state.md"
[ -f "$pstate" ] && chk 1 'a. proj state.md exists' || chk 0 'a. proj state.md exists'
[ "$(ratmac_fm_get "$pstate" mode)"   = "sole" ]   && chk 1 'a. proj frontmatter mode: sole (S5)'   || chk 0 'a. proj frontmatter mode: sole (S5)'
[ "$(ratmac_fm_get "$pstate" status)" = "active" ] && chk 1 'a. proj frontmatter status: active (S5)' || chk 0 'a. proj frontmatter status: active (S5)'
[ -d "$proj/goal" ] && chk 1 'a. proj goal/ dir exists (sole)' || chk 0 'a. proj goal/ dir exists (sole)'

# === b. kickoff slice ==============================================================
run ratmac-kickoff kickoff --tier slice --name s-smoke --ts '2026-06-03-00:00:01' >/dev/null 2>&1 || true
[ -f "$slice/state.md" ]         && chk 1 'b. slice state.md exists'         || chk 0 'b. slice state.md exists'
[ -f "$slice/scope.md" ]         && chk 1 'b. slice scope.md exists (sole)'  || chk 0 'b. slice scope.md exists (sole)'
[ -f "$slice/scope-history.md" ] && chk 1 'b. slice scope-history.md exists (sole)' || chk 0 'b. slice scope-history.md exists (sole)'
[ -d "$slice/grad" ]             && chk 1 'b. slice grad/ dir exists'        || chk 0 'b. slice grad/ dir exists'
grep -Eq '^active slice:[[:space:]]*s-smoke' "$pstate" && chk 1 'b. proj state.md "active slice:" -> s-smoke' || chk 0 'b. proj state.md "active slice:" -> s-smoke'

# === c. kickoff task ===============================================================
run ratmac-kickoff kickoff --tier task --name t-smoke --ts '2026-06-03-00:00:02' >/dev/null 2>&1 || true
tdir="$slice/grad/t-smoke"
for leaf in issue.md task.md state.md log.md; do
  [ -f "$tdir/$leaf" ] && chk 1 "c. grad/t-smoke/$leaf exists" || chk 0 "c. grad/t-smoke/$leaf exists"
done
grep -q '\[\[t-smoke\]\]' "$slice/state.md" && chk 1 'c. slice ## tasks table has [[t-smoke]] row' || chk 0 'c. slice ## tasks table has [[t-smoke]] row'

# === d. checkpoint + add-affects (RQ13 dedupe) =====================================
tstate="$tdir/state.md"
run ratmac-checkpoint checkpoint --task t-smoke --note 'did a thing' --add-affects 'src/a.cpp,src/b.cpp' --ts '2026-06-03-00:00:03' >/dev/null 2>&1 || true
aff="$(ratmac_affects_list "$tstate" affects)"
ha="$(printf '%s\n' "$aff" | grep -Fxq 'src/a.cpp' && echo 1 || echo 0)"
hb="$(printf '%s\n' "$aff" | grep -Fxq 'src/b.cpp' && echo 1 || echo 0)"
[ "$ha" = "1" ] && [ "$hb" = "1" ] && chk 1 'd. task ## affects lists src/a.cpp + src/b.cpp' || chk 0 'd. task ## affects lists src/a.cpp + src/b.cpp'
run ratmac-checkpoint checkpoint --task t-smoke --note 're-add' --add-affects 'src/a.cpp' --ts '2026-06-03-00:00:04' >/dev/null 2>&1 || true
na="$(ratmac_affects_list "$tstate" affects | grep -Fxc 'src/a.cpp' || true)"
[ "$na" = "1" ] && chk 1 'd. re-adding src/a.cpp is NOT duplicated (RQ13 dedupe)' || chk 0 'd. re-adding src/a.cpp is NOT duplicated (RQ13 dedupe)'

# === e. scope + (create goal) ======================================================
run ratmac-scope scope --op + --ref claim-lots --create-goal --reason 'discovered' --ts '2026-06-03-00:00:05' >/dev/null 2>&1 || true
goalFile="$proj/goal/claim-lots.md"
[ -f "$goalFile" ] && chk 1 'e. goal/claim-lots.md created' || chk 0 'e. goal/claim-lots.md created'
[ "$(ratmac_fm_get "$goalFile" current)" = "false" ] && chk 1 'e. goal/claim-lots.md current: false' || chk 0 'e. goal/claim-lots.md current: false'
grep -q 'claim-lots' "$slice/scope.md" && chk 1 'e. scope.md references claim-lots' || chk 0 'e. scope.md references claim-lots'
grep -Eq '^\+[[:space:]]+claim-lots' "$slice/scope-history.md" && chk 1 'e. scope-history.md has "+ claim-lots" line' || chk 0 'e. scope-history.md has "+ claim-lots" line'

# === f. close task =================================================================
# satisfy close done-gate: mark seeded acceptance-criteria checkbox complete in issue.md
sed -i 's/^\([[:space:]]*\)-[[:space:]]*\[ \]/\1- [x]/' "$tdir/issue.md" 2>/dev/null || \
  { sed 's/^\([[:space:]]*\)-[[:space:]]*\[ \]/\1- [x]/' "$tdir/issue.md" > "$tdir/issue.md.tmp" && mv "$tdir/issue.md.tmp" "$tdir/issue.md"; }
run ratmac-close close --task t-smoke --status done --cl 12345 --goal claim-lots --ts '2026-06-03-00:00:06' >/dev/null 2>&1 || true
archived="$slice/archive/t-smoke"
[ -d "$archived" ]   && chk 1 'f. task dir moved to s-smoke/archive/t-smoke' || chk 0 'f. task dir moved to s-smoke/archive/t-smoke'
[ ! -d "$tdir" ]     && chk 1 'f. grad/t-smoke no longer present'            || chk 0 'f. grad/t-smoke no longer present'
[ "$(ratmac_fm_get "$archived/state.md" status)" = "done" ] && chk 1 'f. archived task state.md status: done' || chk 0 'f. archived task state.md status: done'
[ "$(ratmac_fm_get "$goalFile" current)" = "true" ] && chk 1 'f. goal/claim-lots.md current: true' || chk 0 'f. goal/claim-lots.md current: true'
grep -Eq '\|[[:space:]]*\[\[t-smoke\]\].*\|[[:space:]]*done[[:space:]]*\|' "$slice/state.md" && chk 1 'f. slice table row [[t-smoke]] status done' || chk 0 'f. slice table row [[t-smoke]] status done'

# === g. regen idempotence (R10) ====================================================
run ratmac-regen regen --ts '2026-06-03-00:00:07' >/dev/null 2>&1 || true
r2="$(run ratmac-regen regen --ts '2026-06-03-00:00:08' 2>&1 || true)"
printf '%s' "$r2" | grep -qi 'hash-stable' && chk 1 'g. regen run #2 reports hash-stable (R10 idempotence)' || chk 0 'g. regen run #2 reports hash-stable (R10 idempotence)'
goalResid="$proj/goal-residual.md"
scopeResid="$slice/scope-residual.md"
[ -f "$goalResid" ]  && chk 1 'g. proj goal-residual.md exists'  || chk 0 'g. proj goal-residual.md exists'
[ -f "$scopeResid" ] && chk 1 'g. slice scope-residual.md exists' || chk 0 'g. slice scope-residual.md exists'
head -n1 "$goalResid"  2>/dev/null | grep -Eq '^<!--[[:space:]]*GENERATED' && chk 1 'g. goal-residual.md starts with GENERATED sentinel'  || chk 0 'g. goal-residual.md starts with GENERATED sentinel'
head -n1 "$scopeResid" 2>/dev/null | grep -Eq '^<!--[[:space:]]*GENERATED' && chk 1 'g. scope-residual.md starts with GENERATED sentinel' || chk 0 'g. scope-residual.md starts with GENERATED sentinel'
[ -n "$(ratmac_affects_list "$slice/state.md" affects)" ] && chk 1 'g. slice state.md GENERATED affects fence populated' || chk 0 'g. slice state.md GENERATED affects fence populated'
[ -n "$(ratmac_affects_list "$pstate" affects)" ]         && chk 1 'g. proj state.md affects fence populated'           || chk 0 'g. proj state.md affects fence populated'

# === h. lint --strict ==============================================================
run ratmac-lint lint --strict >/dev/null 2>&1
lintExit=$?
[ "$lintExit" -eq 0 ] && chk 1 "h. lint --strict exit code 0 (clean tree)" || chk 0 "h. lint --strict exit code 0 (clean tree) [exit $lintExit]"

# === i. empty-affects regen (latent crash guard) ==================================
# Second project with a slice that has NO tasks => its affects union is empty.
# (.sh reads body via cat so it never had the binding crash; this still guards the
# empty-affects path: regen must exit 0, write an empty GENERATED affects fence into
# both slice + proj state.md, and stay hash-stable on a re-run (R10).)
projE="$sched/p-empty"
sliceE="$projE/s-empty"
run ratmac-kickoff kickoff --tier proj  --name p-empty --mode sole --ts '2026-06-03-00:00:09' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier slice --name s-empty --proj p-empty --ts '2026-06-03-00:00:10' >/dev/null 2>&1 || true
peState="$projE/state.md"
seState="$sliceE/state.md"
[ -f "$peState" ] && chk 1 'i. p-empty proj state.md exists' || chk 0 'i. p-empty proj state.md exists'
[ -f "$seState" ] && chk 1 'i. s-empty slice state.md exists (no tasks => empty affects)' || chk 0 'i. s-empty slice state.md exists (no tasks => empty affects)'
# regen run #1: must exit 0 (no crash on empty affects)
run ratmac-regen regen --proj p-empty --ts '2026-06-03-00:00:11' >/dev/null 2>&1
regenE1=$?
[ "$regenE1" -eq 0 ] && chk 1 "i. regen run #1 on empty-affects proj exits 0 (no crash)" || chk 0 "i. regen run #1 on empty-affects proj exits 0 (no crash) [exit $regenE1]"
# both state.md files carry a GENERATED affects fence (empty body is fine)
has_fence(){ [ -f "$1" ] && grep -Eq '<!--[[:space:]]*GENERATED[[:space:]]*-->' "$1" && grep -Eq '<!--[[:space:]]*/GENERATED[[:space:]]*-->' "$1"; }
has_fence "$seState" && chk 1 'i. s-empty state.md has GENERATED.../GENERATED affects fence (empty body)' || chk 0 'i. s-empty state.md has GENERATED.../GENERATED affects fence (empty body)'
has_fence "$peState" && chk 1 'i. p-empty state.md has GENERATED.../GENERATED affects fence (empty body)' || chk 0 'i. p-empty state.md has GENERATED.../GENERATED affects fence (empty body)'
# affects union must in fact be empty (proves we exercised the empty path)
[ -z "$(ratmac_affects_list "$seState" affects)" ] && chk 1 'i. s-empty affects fence is empty (empty-affects path exercised)' || chk 0 'i. s-empty affects fence is empty (empty-affects path exercised)'
# regen run #2 with a distinct --ts must report hash-stable (R10 holds on empty input)
rE2="$(run ratmac-regen regen --proj p-empty --ts '2026-06-03-00:00:12' 2>&1 || true)"
printf '%s' "$rE2" | grep -qi 'hash-stable' && chk 1 'i. regen run #2 on empty-affects proj reports hash-stable (R10)' || chk 0 'i. regen run #2 on empty-affects proj reports hash-stable (R10)'

# helper: tick every unchecked '- [ ]' acceptance-criteria box in an issue.md (close done-gate)
tick_ac() {  # arg1: issue.md path
  sed -i 's/^\([[:space:]]*\)-[[:space:]]*\[ \]/\1- [x]/' "$1" 2>/dev/null || \
    { sed 's/^\([[:space:]]*\)-[[:space:]]*\[ \]/\1- [x]/' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
}

# === j. close ALONE rebuilds residuals (no following standalone regen) =============
# close spawns ratmac-regen internally (R18). Prove the spawn actually fires by checking close's
# OWN 'Regen result' contract field is not 'not run' AND that the residuals + the slice/proj
# ## affects fences are populated IMMEDIATELY after close — without any extra regen call.
projJ="$sched/p-closealone"; sliceJ="$projJ/s-ca"
run ratmac-kickoff kickoff --tier proj  --name p-closealone --mode sole --ts '2026-06-03-00:01:00' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier slice --name s-ca --proj p-closealone --ts '2026-06-03-00:01:01' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier task  --name t-ca --proj p-closealone --ts '2026-06-03-00:01:02' >/dev/null 2>&1 || true
run ratmac-checkpoint checkpoint --task t-ca --proj p-closealone --note ca --add-affects 'src/ca.cpp' --ts '2026-06-03-00:01:03' >/dev/null 2>&1 || true
tick_ac "$sliceJ/grad/t-ca/issue.md"
run_cap ratmac-close close --task t-ca --proj p-closealone --status done --cl 1 --ts '2026-06-03-00:01:04'
jRegen="$(contract_field "$RUN_OUT" 'Regen result')"
{ [ -n "$jRegen" ] && [ "$jRegen" != "not run" ]; } && chk 1 "j. close's own 'Regen result' is not 'not run' (regen spawned) [$jRegen]" || chk 0 "j. close's own 'Regen result' is not 'not run' (regen spawned) [$jRegen]"
ratmac_affects_list "$sliceJ/state.md" affects | grep -Fxq 'src/ca.cpp' && chk 1 'j. slice ## affects fence populated right after close (no extra regen)' || chk 0 'j. slice ## affects fence populated right after close (no extra regen)'
ratmac_affects_list "$projJ/state.md" affects | grep -Fxq 'src/ca.cpp' && chk 1 'j. proj ## affects fence populated right after close (no extra regen)' || chk 0 'j. proj ## affects fence populated right after close (no extra regen)'
[ -f "$projJ/goal-residual.md" ]  && chk 1 'j. proj goal-residual.md exists after close alone'  || chk 0 'j. proj goal-residual.md exists after close alone'
[ -f "$sliceJ/scope-residual.md" ] && chk 1 'j. slice scope-residual.md exists after close alone' || chk 0 'j. slice scope-residual.md exists after close alone'

# === k. cross-engine byte parity (sh-authored tree, regen'd by BOTH engines) =======
# Author ONE tree with the POSIX engine in scheduler root A, COPY it verbatim to root B (same
# project name p-xeng — the name is embedded in residuals, so both copies MUST share it). regen
# A with sh and B with the OTHER (pwsh) engine, same --ts. The GENERATED ## affects fences
# (slice+proj state.md) and the whole-file residuals MUST be byte-identical across engines (R4
# same-side-effects, R10/S20). diff must be empty — clean lint alone is NOT enough.
kRootA="$tmp/xeng-a"; kRootB="$tmp/xeng-b"
mkdir -p "$kRootA"
run ratmac-kickoff kickoff --tier proj  --name p-xeng --mode sole --root "$kRootA" --ts '2026-06-03-00:02:00' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier slice --name s-pp --root "$kRootA" --proj p-xeng --ts '2026-06-03-00:02:01' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier task  --name t-pp --root "$kRootA" --proj p-xeng --ts '2026-06-03-00:02:02' >/dev/null 2>&1 || true
run ratmac-scope scope --op + --ref ship-it --create-goal --reason r --root "$kRootA" --proj p-xeng --ts '2026-06-03-00:02:03' >/dev/null 2>&1 || true
run ratmac-checkpoint checkpoint --task t-pp --root "$kRootA" --proj p-xeng --note n --add-affects 'src/zeta.cpp,src/alpha.cpp' --ts '2026-06-03-00:02:04' >/dev/null 2>&1 || true
cp -r "$kRootA" "$kRootB"
projKa="$kRootA/p-xeng"; projKb="$kRootB/p-xeng"
# Delete the residuals authoring (scope's regen) already created, so the two engines must CREATE
# them FRESH — this exercises each engine's residual WRITE path cross-engine (CRLF-vs-LF parity),
# not just the idempotent-skip path which would mask a line-ending divergence.
rm -f "$projKa/goal-residual.md" "$projKa/s-pp/scope-residual.md" "$projKb/goal-residual.md" "$projKb/s-pp/scope-residual.md"
run ratmac-regen regen --root "$kRootA" --proj p-xeng --ts '2026-06-03-00:02:09' >/dev/null 2>&1 || true
# regen tree B with the OTHER (pwsh) engine; cygpath -m so pwsh accepts the root path
run_pwsh ratmac-regen regen -Root "$(cygpath -m "$kRootB")" -Proj p-xeng -Ts '2026-06-03-00:02:09' >/dev/null 2>&1 || true
kDiffs=""
for rel in state.md s-pp/state.md goal-residual.md s-pp/scope-residual.md; do
  if ! diff -q "$projKa/$rel" "$projKb/$rel" >/dev/null 2>&1; then kDiffs="$kDiffs $rel"; fi
done
[ -z "$kDiffs" ] && chk 1 'k. sh-vs-pwsh regen byte-identical for GENERATED regions + residuals (diff empty)' || chk 0 "k. sh-vs-pwsh regen byte-identical for GENERATED regions + residuals (diff empty) [differ:$kDiffs]"
# the OTHER engine's lint --strict on the sh-authored+sh-regen'd tree is also clean (parity)
run_pwsh ratmac-lint lint -Root "$(cygpath -m "$kRootA")" -Proj p-xeng -Strict >/dev/null 2>&1 || true
[ "$PWSH_RC" -eq 0 ] && chk 1 "k. pwsh lint -Strict on sh-authored tree exits 0" || chk 0 "k. pwsh lint -Strict on sh-authored tree exits 0 [exit $PWSH_RC]"

# === l. degenerate input: EMPTY + 1-LINE state.md, route/lint/close don't crash =====
# A grad task with a 0-byte state.md and another with a single-line state.md must NOT crash. route
# is read-only (exit 0), lint reports S5 errors deterministically (exit 1, not a stack trace), and
# close on the empty task BLOCKs on empty affects (exit 2). Both engines must exit IDENTICALLY —
# the pwsh suite pins the same exit codes, so matching here proves cross-engine agreement (#3).
projL="$sched/p-degen"; sliceL="$projL/s-dg"
run ratmac-kickoff kickoff --tier proj  --name p-degen --mode sole --ts '2026-06-03-00:03:00' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier slice --name s-dg --proj p-degen --ts '2026-06-03-00:03:01' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier task  --name t-empty   --proj p-degen --ts '2026-06-03-00:03:02' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier task  --name t-oneline --proj p-degen --ts '2026-06-03-00:03:03' >/dev/null 2>&1 || true
: > "$sliceL/grad/t-empty/state.md"                      # EMPTY (0 bytes)
printf 'no fm\n' > "$sliceL/grad/t-oneline/state.md"     # 1-LINE
run_cap ratmac-route route --proj p-degen
{ [ "$RUN_RC" -eq 0 ] && no_stack "$RUN_OUT"; } && chk 1 "l. route on degenerate tree exits 0, no stack trace" || chk 0 "l. route on degenerate tree exits 0, no stack trace [exit $RUN_RC]"
run_cap ratmac-lint lint --proj p-degen
{ [ "$RUN_RC" -eq 1 ] && no_stack "$RUN_OUT"; } && chk 1 "l. lint on degenerate tree exits 1 (S5 errors), no stack trace" || chk 0 "l. lint on degenerate tree exits 1 (S5 errors), no stack trace [exit $RUN_RC]"
run_cap ratmac-close close --task t-empty --proj p-degen --status done --ts '2026-06-03-00:03:04'
{ [ "$RUN_RC" -eq 2 ] && printf '%s' "$RUN_OUT" | grep -q 'BLOCKED' && no_stack "$RUN_OUT"; } && chk 1 "l. close on empty-state task BLOCKs clean (exit 2), no stack trace" || chk 0 "l. close on empty-state task BLOCKs clean (exit 2), no stack trace [exit $RUN_RC]"

# === m. archive collision: pre-existing archive/<x> => BLOCKED exit 2, no nesting ===
# Pre-create the destination archive/<slice> and archive/<task>, then drive transit/close. Both
# must STOP with "BLOCKED archive collision" exit 2 BEFORE the mv, and must NOT create a nested
# archive/<x>/<x> (the mv footgun this guard exists to prevent).
projM="$sched/p-collide"; sliceM="$projM/s-co"
run ratmac-kickoff kickoff --tier proj  --name p-collide --mode sole --ts '2026-06-03-00:04:00' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier slice --name s-co --proj p-collide --ts '2026-06-03-00:04:01' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier task  --name t-co --proj p-collide --ts '2026-06-03-00:04:02' >/dev/null 2>&1 || true
mkdir -p "$sliceM/archive/t-co"   # pre-existing task archive dest
run ratmac-checkpoint checkpoint --task t-co --proj p-collide --note c --add-affects 'src/co.cpp' --ts '2026-06-03-00:04:03' >/dev/null 2>&1 || true
tick_ac "$sliceM/grad/t-co/issue.md"
run_cap ratmac-close close --task t-co --proj p-collide --status done --cl 2 --ts '2026-06-03-00:04:04'
{ [ "$RUN_RC" -eq 2 ] && printf '%s' "$RUN_OUT" | grep -q 'BLOCKED archive collision'; } && chk 1 "m. close BLOCKs (exit 2) on pre-existing archive/t-co" || chk 0 "m. close BLOCKs (exit 2) on pre-existing archive/t-co [exit $RUN_RC]"
[ ! -d "$sliceM/archive/t-co/t-co" ] && chk 1 'm. close did NOT nest archive/t-co/t-co' || chk 0 'm. close did NOT nest archive/t-co/t-co'
[ -d "$sliceM/grad/t-co" ] && chk 1 'm. close left grad/t-co in place (no half-move)' || chk 0 'm. close left grad/t-co in place (no half-move)'
mkdir -p "$projM/archive/s-co"   # pre-existing slice archive dest
run_cap ratmac-transit transit --tier slice --new-slice s-next --summary x --force --proj p-collide --ts '2026-06-03-00:04:05'
{ [ "$RUN_RC" -eq 2 ] && printf '%s' "$RUN_OUT" | grep -q 'BLOCKED archive collision'; } && chk 1 "m. transit BLOCKs (exit 2) on pre-existing archive/s-co" || chk 0 "m. transit BLOCKs (exit 2) on pre-existing archive/s-co [exit $RUN_RC]"
[ ! -d "$projM/archive/s-co/s-co" ] && chk 1 'm. transit did NOT nest archive/s-co/s-co' || chk 0 'm. transit did NOT nest archive/s-co/s-co'
[ -d "$sliceM" ] && chk 1 'm. transit left s-co in place (no half-move)' || chk 0 'm. transit left s-co in place (no half-move)'

# === n. proj rollup retains archived slice (closing the ONLY slice => non-empty) ====
# A sole proj with a single slice + one done task carrying affects. transit the slice with
# --no-successor (closes the only slice). The proj ## affects rollup is regen'd BEFORE the mv
# (lifecycle 3b), so the archived slice's contributed paths must STILL appear in the proj fence
# afterward — closing the last slice must NOT empty the proj rollup.
projN="$sched/p-rollup"; sliceN="$projN/s-ru"
run ratmac-kickoff kickoff --tier proj  --name p-rollup --mode sole --ts '2026-06-03-00:05:00' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier slice --name s-ru --proj p-rollup --ts '2026-06-03-00:05:01' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier task  --name t-ru --proj p-rollup --ts '2026-06-03-00:05:02' >/dev/null 2>&1 || true
run ratmac-checkpoint checkpoint --task t-ru --proj p-rollup --note n --add-affects 'src/only.cpp' --ts '2026-06-03-00:05:03' >/dev/null 2>&1 || true
tick_ac "$sliceN/grad/t-ru/issue.md"
run ratmac-close close --task t-ru --proj p-rollup --status done --cl 3 --ts '2026-06-03-00:05:04' >/dev/null 2>&1 || true
run ratmac-transit transit --tier slice --no-successor --summary done --proj p-rollup --ts '2026-06-03-00:05:05' >/dev/null 2>&1 || true
[ -d "$projN/archive/s-ru" ] && chk 1 'n. s-ru archived under proj' || chk 0 'n. s-ru archived under proj'
ratmac_affects_list "$projN/state.md" affects | grep -Fxq 'src/only.cpp' && chk 1 'n. proj ## affects still lists archived slice path after closing the only slice (non-empty)' || chk 0 'n. proj ## affects still lists archived slice path after closing the only slice (non-empty)'

# === o. --force + empty ## affects on status:done => BLOCKED exit 2 =================
# The non-empty ## affects gate is data-integrity (S18): a done task with no affects record is
# permanent loss once archived, so --force MUST NOT bypass it. Close a done task with empty
# affects AND --force; it must still BLOCK exit 2 and the task must stay in grad/.
projO="$sched/p-forcegate"; sliceO="$projO/s-fg"
run ratmac-kickoff kickoff --tier proj  --name p-forcegate --mode sole --ts '2026-06-03-00:06:00' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier slice --name s-fg --proj p-forcegate --ts '2026-06-03-00:06:01' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier task  --name t-fg --proj p-forcegate --ts '2026-06-03-00:06:02' >/dev/null 2>&1 || true
run_cap ratmac-close close --task t-fg --proj p-forcegate --status done --force --cl 4 --ts '2026-06-03-00:06:03'
{ [ "$RUN_RC" -eq 2 ] && printf '%s' "$RUN_OUT" | grep -q 'BLOCKED need affects'; } && chk 1 "o. --force does NOT bypass empty-affects done-gate (BLOCKED exit 2)" || chk 0 "o. --force does NOT bypass empty-affects done-gate (BLOCKED exit 2) [exit $RUN_RC]"
[ -d "$sliceO/grad/t-fg" ] && chk 1 'o. t-fg left in grad/ (not archived) after blocked --force close' || chk 0 'o. t-fg left in grad/ (not archived) after blocked --force close'

# === p. mutate via the engine CLI for --kind ticket AND --kind plan =================
# POSIX shadow of the pwsh suite's `pwsh -File mutate.ps1` test: drive mutate.sh for both kinds
# (scalar params only — comma/space args survive bash word-splitting cleanly). Both must exit 0,
# leave their side-effect (## ticket updates entry / replan log line), and emit a contract block.
projP="$sched/p-mutate"; sliceP="$projP/s-mu"
run ratmac-kickoff kickoff --tier proj  --name p-mutate --mode sole --ts '2026-06-03-00:07:00' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier slice --name s-mu --proj p-mutate --ts '2026-06-03-00:07:01' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier task  --name t-mu --proj p-mutate --ts '2026-06-03-00:07:02' >/dev/null 2>&1 || true
run_cap ratmac-mutate mutate --task t-mu --kind ticket --reason 'revised scope' --proj p-mutate --ts '2026-06-03-00:07:03'
[ "$RUN_RC" -eq 0 ] && chk 1 "p. mutate --kind ticket exits 0" || chk 0 "p. mutate --kind ticket exits 0 [exit $RUN_RC]"
printf '%s' "$RUN_OUT" | grep -q '^```contract' && chk 1 'p. mutate ticket emits a contract block' || chk 0 'p. mutate ticket emits a contract block'
{ grep -qE '^##[[:space:]]+ticket updates[[:space:]]*$' "$sliceP/grad/t-mu/issue.md" && grep -qE '^-[[:space:]]+\S.*revised scope' "$sliceP/grad/t-mu/issue.md"; } && chk 1 'p. mutate ticket wrote a non-empty ## ticket updates line' || chk 0 'p. mutate ticket wrote a non-empty ## ticket updates line'
run_cap ratmac-mutate mutate --task t-mu --kind plan --reason 'replan approach' --proj p-mutate --ts '2026-06-03-00:07:04'
[ "$RUN_RC" -eq 0 ] && chk 1 "p. mutate --kind plan exits 0" || chk 0 "p. mutate --kind plan exits 0 [exit $RUN_RC]"
printf '%s' "$RUN_OUT" | grep -q '^```contract' && chk 1 'p. mutate plan emits a contract block' || chk 0 'p. mutate plan emits a contract block'
grep -qE '^[^[:space:]]+[[:space:]]+replan( |$)' "$sliceP/grad/t-mu/log.md" && chk 1 'p. mutate plan appended a non-empty replan log line' || chk 0 'p. mutate plan appended a non-empty replan log line'

# === q. lint filesystem read-only: zero new/removed OS-temp entries (R11) ===========
# R11 says lint NEVER writes — at the filesystem level, incl. /tmp. To prove lint.sh leaves no
# scratch file / PID leak, point its temp dir (TMPDIR) at a FRESH PRIVATE empty dir that no other
# process touches, run lint, then assert that private dir's immediate children are byte-for-byte
# unchanged. We must NOT snapshot the shared OS temp dir ($TMPDIR/$TMP) directly: on a real machine
# that dir is churned by unrelated concurrent processes (the harness, node, etc.) and even holds
# this suite's own mktemp -d tree, so its delta is non-deterministic and has nothing to do with
# lint — that was the source of this assertion's flakiness. Isolating TMPDIR scopes the measurement
# to exactly what lint itself writes (matching the pwsh suite, whose child shell does not churn the
# parent's temp dir during the window). Lint resolves the smoke tree via --proj/env, so it has no
# excuse to touch its temp dir at all.
qTmp="$(mktemp -d)"
qBefore="$(ls -A "$qTmp" 2>/dev/null | LC_ALL=C sort)"
TMPDIR="$qTmp" TMP="$qTmp" TEMP="$qTmp" run ratmac-lint lint --proj p-test --strict >/dev/null 2>&1 || true
qAfter="$(ls -A "$qTmp" 2>/dev/null | LC_ALL=C sort)"
rm -rf "$qTmp"
[ "$qBefore" = "$qAfter" ] && chk 1 'q. lint.sh added/removed ZERO OS-temp entries (R11 filesystem read-only)' || chk 0 "q. lint.sh added/removed ZERO OS-temp entries (R11 filesystem read-only)"

# === r. declared Skill chain actually ran (observe each sibling's side-effect) ======
# Every skill emits a 'Skill chain' contract field naming the siblings it spawns. Assert each
# named sibling actually executed by observing its side-effect / verdict field — a declared chain
# that silently no-ops is a contract lie (R7/R18). Use a DEDICATED scheduler root with a single
# project so transit's internally-spawned lint resolves to a real pass/warn verdict, not an
# ambiguous multi-project BLOCK.
rRoot="$tmp/chain"; mkdir -p "$rRoot"
projR="$rRoot/p-chain"; sliceR="$projR/s-ch"
run_cap ratmac-kickoff kickoff --tier proj --name p-chain --mode sole --root "$rRoot" --ts '2026-06-03-00:08:00'
{ [ "$(contract_field "$RUN_OUT" 'Skill chain')" = "ratmac-kickoff" ] && [ -f "$projR/state.md" ]; } && chk 1 'r. kickoff Skill chain=ratmac-kickoff and its scaffold side-effect present' || chk 0 'r. kickoff Skill chain=ratmac-kickoff and its scaffold side-effect present'
run ratmac-kickoff kickoff --tier slice --name s-ch --root "$rRoot" --proj p-chain --ts '2026-06-03-00:08:01' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier task  --name t-ch --root "$rRoot" --proj p-chain --ts '2026-06-03-00:08:02' >/dev/null 2>&1 || true
run ratmac-checkpoint checkpoint --task t-ch --root "$rRoot" --proj p-chain --note n --add-affects 'src/ch.cpp' --ts '2026-06-03-00:08:03' >/dev/null 2>&1 || true
tick_ac "$sliceR/grad/t-ch/issue.md"
run_cap ratmac-close close --task t-ch --root "$rRoot" --proj p-chain --status done --cl 5 --ts '2026-06-03-00:08:04'
printf '%s' "$(contract_field "$RUN_OUT" 'Skill chain')" | grep -q 'ratmac-close -> ratmac-regen' && chk 1 'r. close declares chain ratmac-close -> ratmac-regen' || chk 0 'r. close declares chain ratmac-close -> ratmac-regen'
rClRegen="$(contract_field "$RUN_OUT" 'Regen result')"
{ [ -n "$rClRegen" ] && [ "$rClRegen" != "not run" ] && ratmac_affects_list "$sliceR/state.md" affects | grep -Fxq 'src/ch.cpp'; } && chk 1 "r. close's regen sibling actually ran (verdict + slice fence side-effect) [$rClRegen]" || chk 0 "r. close's regen sibling actually ran (verdict + slice fence side-effect) [$rClRegen]"
run_cap ratmac-transit transit --tier slice --no-successor --summary done --root "$rRoot" --proj p-chain --ts '2026-06-03-00:08:05'
printf '%s' "$(contract_field "$RUN_OUT" 'Skill chain')" | grep -q 'ratmac-transit -> ratmac-regen -> ratmac-lint' && chk 1 'r. transit declares chain ratmac-transit -> ratmac-regen -> ratmac-lint' || chk 0 'r. transit declares chain ratmac-transit -> ratmac-regen -> ratmac-lint'
rTrLint="$(contract_field "$RUN_OUT" 'Lint result')"
{ [ -n "$rTrLint" ] && [ "$rTrLint" != "ratmac-lint not run" ] && ! printf '%s' "$rTrLint" | grep -q 'BLOCKED'; } && chk 1 "r. transit's lint sibling actually ran (Lint result carries a real verdict) [$rTrLint]" || chk 0 "r. transit's lint sibling actually ran (Lint result carries a real verdict) [$rTrLint]"
rTrRegen="$(contract_field "$RUN_OUT" 'Regen result')"
printf '%s' "$rTrRegen" | grep -q 'rebuilt' && chk 1 "r. transit's regen sibling actually ran (Regen result verdict) [$rTrRegen]" || chk 0 "r. transit's regen sibling actually ran (Regen result verdict) [$rTrRegen]"

# === s. cross-engine kickoff-Emit byte parity (scaffold path, not just regen) =======
# Defect 1/6/11: the kickoff Emit path (and the slice/task scaffold) used to write CRLF on pwsh
# (Set-Content) while kickoff.sh wrote LF, so the scaffolded state/issue/task/log/scope files
# diverged byte-for-byte across engines (and pwsh added a doubled trailing newline). Test k only
# regen's an sh-authored tree, so it never exercises the kickoff WRITE path cross-engine. Here we
# build an IDENTICALLY-SEEDED tree with each engine (POSIX under root A, the pwsh engine under root
# B, same names + pinned --ts) and assert every kickoff-scaffolded file is byte-identical — locking
# the LF/UTF-8-no-BOM fix (R4 same-side-effects, R10 byte-idempotence) so it cannot regress.
sRootA="$tmp/kemit-a"; sRootB="$tmp/kemit-b"
mkdir -p "$sRootA" "$sRootB"
# POSIX engine authors under root A
run ratmac-kickoff kickoff --tier proj  --name p-em --mode sole --root "$sRootA" --ts '2026-06-03-00:09:00' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier slice --name s-em --root "$sRootA" --proj p-em --ts '2026-06-03-00:09:01' >/dev/null 2>&1 || true
run ratmac-kickoff kickoff --tier task  --name t-em --root "$sRootA" --proj p-em --ts '2026-06-03-00:09:02' >/dev/null 2>&1 || true
# pwsh engine authors the SAME tree under root B (cygpath -m so pwsh accepts the root path)
run_pwsh ratmac-kickoff kickoff -Tier proj  -Name p-em -Mode sole -Root "$(cygpath -m "$sRootB")" -Ts '2026-06-03-00:09:00' >/dev/null 2>&1 || true
run_pwsh ratmac-kickoff kickoff -Tier slice -Name s-em -Root "$(cygpath -m "$sRootB")" -Proj p-em -Ts '2026-06-03-00:09:01' >/dev/null 2>&1 || true
run_pwsh ratmac-kickoff kickoff -Tier task  -Name t-em -Root "$(cygpath -m "$sRootB")" -Proj p-em -Ts '2026-06-03-00:09:02' >/dev/null 2>&1 || true
projSa="$sRootA/p-em"; projSb="$sRootB/p-em"
sDiffs=""
for rel in state.md log.md s-em/state.md s-em/log.md s-em/scope.md s-em/scope-history.md \
           s-em/grad/t-em/issue.md s-em/grad/t-em/task.md s-em/grad/t-em/state.md s-em/grad/t-em/log.md; do
  if ! cmp -s "$projSa/$rel" "$projSb/$rel"; then sDiffs="$sDiffs $rel"; fi
done
[ -z "$sDiffs" ] && chk 1 's. POSIX-vs-pwsh kickoff scaffold byte-identical (LF/no-BOM, no CRLF)' || chk 0 "s. POSIX-vs-pwsh kickoff scaffold byte-identical (LF/no-BOM, no CRLF) [differ:$sDiffs]"
# no CR bytes anywhere in the POSIX-authored scaffold (defects 1/6/11)
sNoCr=1
for rel in state.md s-em/grad/t-em/state.md; do
  if [ -f "$projSa/$rel" ] && [ "$(tr -cd '\r' < "$projSa/$rel" | wc -c)" -ne 0 ]; then sNoCr=0; fi
done
[ "$sNoCr" -eq 1 ] && chk 1 's. POSIX kickoff scaffold has ZERO CR bytes (no CRLF / no doubled trailing newline)' || chk 0 's. POSIX kickoff scaffold has ZERO CR bytes'

# --- report ------------------------------------------------------------------------
echo
if [ "$fail" -eq 0 ]; then echo "SMOKE OK — all assertions passed"; else echo "SMOKE FAILED — $fail assertion(s)"; fi

if [ "$KEEP" = "1" ]; then echo "kept: $tmp"; else rm -rf "$tmp"; fi
unset RATMAC_SCHEDULER_ROOT
[ "$fail" -eq 0 ] && exit 0 || exit 1
