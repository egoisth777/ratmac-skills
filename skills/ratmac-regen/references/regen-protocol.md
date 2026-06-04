---
time-created: 2026-06-03-00:30:00
time-modified: 2026-06-03-00:30:00
---

# regen protocol

How `ratmac-regen` rebuilds the GENERATED scheduler content from its source-of-truth,
and why the rebuild is also a fence-drift detector. This is the reference behind
`scripts/regen.ps1` and its POSIX shadow `scripts/regen.sh`.

## what is generated

The scheduler tree has two kinds of generated content, both machine-owned (S13, S20):

1. **Whole-file residuals** — `goal-residual.md`, per-slice `scope-residual.md`, and
   per-slice `issues-residual.md`. Each begins with a `<!-- GENERATED — do not edit -->`
   sentinel on line 1, followed by frontmatter and a `# <title>` heading; the *whole file*
   is regenerated (S13). These are read-only views derived from the live sources.
2. **Fenced `## affects` rollups** — inside slice `state.md` and proj `state.md`. The
   rollup lives between `<!-- GENERATED -->` … `<!-- /GENERATED -->` markers under the
   `## affects` heading (S20). Only the lines between those markers are rewritten; prose,
   headers, and everything outside the fence stay byte-for-byte intact (R6).

The source of truth is never the generated content itself — it is the goal `current:`
flags, the slice `scope.md` refs, the open task `issue:` tags, and the hand-edited task
`## affects` lists (S18). regen recomputes the derived content from those sources.

## resolve context

1. **Resolve roots + project.** `Get-RatmacProj -Root -Proj` → `@{Root;Proj;Path}` via
   explicit `-Root`, then env `RATMAC_SCHEDULER_ROOT`, then a cwd ancestor walk (R5 — only
   ever under a scheduler tree). The project is the `-Proj` arg, else the single `p-*`
   child, else the `status: active` one; otherwise the engine STOPS with `BLOCKED`.
2. **Read mode.** `Get-RatmacMode -ProjPath` reads `mode:` from the proj `state.md`
   (`maintainer | sole | dual`). Mode gates which residuals are rebuilt (R9 — read state
   before writing).
3. **Resolve the stamp.** `Get-RatmacStamp -Ts` — the `-Ts` override else `Get-Date`. The
   same stamp is used for every `time-modified` bump in this run so output is deterministic
   (R10).

## the builds

### goal-residual (sole | dual)

Walk `<proj>/goal/*.md` in sorted basename order. For each goal item whose `current:`
frontmatter is not `true`, emit `- [[/<proj>/goal/<stem>|<stem>]]`. Write the union (the
"goal − current" pending list) to `<proj>/goal-residual.md` via the whole-file residual
writer. In `maintainer` mode there is no `goal/`, so this step is skipped (S12).

### per-slice residuals + the slice `## affects` rollup

For each non-archive `s-*` slice under the project:

- **`## affects` rollup (every mode, S18/S20).** Collect the `## affects` bullet list from
  every archived task `state.md` (frozen lists) **and** every in-flight `grad/t-*`
  `state.md` (live view) via `Get-RatmacAffectsList`. De-duplicate, sort, and splice the
  result as `- <item>` bullets into the slice `state.md` `<!-- GENERATED -->` `## affects`
  fence with `Set-RatmacFence` (creates the fence under a `## affects` heading if absent).
  Stash this sorted union for the proj-level rollup.
- **`scope-residual` (sole | dual).** Read each `[[…]]` wikilink target's last path segment
  from the slice `scope.md`. For each ref, look up `<proj>/goal/<ref>.md`: if it exists and
  its `current:` is not `true`, emit `- [[/<proj>/goal/<ref>|<ref>]]`; if the goal file is
  missing, emit `- <ref> (goal item missing)`. Write to `<slice>/scope-residual.md` (the
  "scope − current" residual).
- **`issues-residual` (maintainer | dual).** For each `grad/t-*` task whose `state.md` has
  an `issue:` tag and `status:` ≠ `done`, emit `- <issue> — [[t-name]] (<status>)`. Write
  to `<slice>/issues-residual.md` (the open assigned-issues list).

### proj `## affects` rollup (Tier all | proj)

Take the union of every slice's stashed `## affects` rollup, de-duplicate, sort, and
splice into the proj `state.md` `## affects` fence with `Set-RatmacFence`. `Tier slice`
skips this step (per-slice work still runs); `Tier proj` / `Tier all` include it.

## the whole-file residual writer (idempotence detail)

The residual writer (`Write-Residual` / `write_residual`) assembles the new file as
sentinel + frontmatter (`time-created` / `time-modified`) + `# <title>` + body. To stay
byte-idempotent on stable input (R10) it compares the *old vs new content with the
`time-(created|modified):` lines stripped out* — so a re-run with the same source and a new
stamp does **not** rewrite the file. On a real change it preserves the original
`time-created` (if the file already existed) and writes only the new `time-modified`. No
write, no stamp bump when nothing changed.

## the fence writer (idempotence detail)

`Set-RatmacFence` captures the lines currently inside the `<!-- GENERATED -->` …
`<!-- /GENERATED -->` markers, compares them to the recomputed body, and returns "no
change" if they are byte-equal — so the file is left untouched and `time-modified` is not
bumped (R10/S20). Only on a real diff does it remove the old region, insert the new bullets,
write the file, and stamp `time-modified`. If no fence exists yet, it appends one under the
named section first.

## idempotence as a drift detector (R10)

regen is byte-stable: running it twice on unchanged source produces identical bytes and
reports `hash-stable (no drift)` with zero regions written. That contract lets regen double
as a check:

- **0 rebuilt / hash-stable** — every residual and every fenced rollup already matched its
  source. The derived content is consistent; nothing drifted.
- **N rebuilt** — N generated regions did not match their source and were corrected. A goal
  `current:` flag flipped, a scope ref changed, a task's `## affects` list grew or froze, or
  a task `issue:`/`status:` changed without the derived content being refreshed (or someone
  hand-edited inside a region, which regen overwrites — source of truth wins).

Because the only writes are inside generated regions (R6/S20, or whole residual files
headed by the S13 sentinel) and the output is a pure function of the live source (R10), a
clean second pass is proof the derived content is back in sync.

## stop rules

- **Bad `--tier` / unknown flag (posix).** The shadow validates `--tier` ∈ `all|proj|slice`
  and rejects unknown args with `BLOCKED: ...` before the contract, exit `2`. The pwsh
  `[ValidateSet('all','proj','slice')]` rejects a bad `-Tier` at param binding.
- **Project unresolvable.** Roots/active-project resolution throws / prints
  `BLOCKED: cannot resolve project`, emits a contract with `Blocked items`, exit `2`.
- regen never STOPS for ambiguity (R12) — it only recomputes derived content from source;
  it never picks a write branch, and it never spawns itself (R18). Hand-edits inside a
  region are not a stop — they are drift and get overwritten.

## invariants exercised

- **R5** — writes only under the `scheduler/` tree (never store/, spaces/, code).
- **R6 / S20** — only `<!-- GENERATED -->` fence regions (or whole residual files headed by
  the `<!-- GENERATED — do not edit -->` sentinel, S13) are rewritten.
- **R7** — ends with the uniform output contract via `Write-RatmacContract` / `ratmac_contract`.
- **R9** — reads the relevant `state.md` (mode, status, affects) before writing.
- **R10 / S13** — byte-idempotent on stable input; doubles as the drift detector.
- **R12** — never STOPS on ambiguity; recomputes, never guesses a write branch.
- **R18** — auto-chained by close / scope / transit; never spawns itself.
- **S18** — slice/proj rollups are the union of task `## affects` lists.

## related

- `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md` (ratmac-regen entry)
- `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/invariants.md` (R5/R6/R7/R9/R10/R12/R18)
- `brain/buf/sparks/pdrft-brain-v3/s-scheduler/invariants.md` (S13/S18/S19/S20)
- `brain/buf/sparks/pdrft-brain-v3/s-scheduler/lifecycle.md` (the regen steps inside
  task-close / scope-mutation / slice-transition)
