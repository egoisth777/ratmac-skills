---
name: ratmac-regen
description: >-
  Use when you need to rebuild the GENERATED scheduler content from its
  source-of-truth — trigger phrases: "regen the scheduler", "rebuild the
  residuals", "refresh the affects rollup", "regenerate goal/scope/issues
  residual", "check for fence drift", or right after hand-editing a goal
  `current:` flag, a scope ref, a task `## affects` list, or a task `issue:`
  tag. It rewrites ONLY generated content (R6/S20): the whole-file residuals
  headed by `<!-- GENERATED — do not edit -->` (`goal-residual.md`,
  `scope-residual.md`, `issues-residual.md`, S13) and the fenced
  `<!-- GENERATED -->` `## affects` rollups in slice + proj `state.md` (S20).
  It is byte-idempotent on stable input (R10), so a "0 rebuilt / hash-stable"
  result doubles as a clean fence-drift check while a non-empty count tells you
  a source flag moved out from under a rollup. Use after $ratmac-init and
  $ratmac-route; auto-chained by $ratmac-close, $ratmac-scope, and
  $ratmac-transit after they mutate the source. Call $ratmac-lint after to
  verify fence integrity and S6 stamps.
---

# ratmac-regen

Rebuild the GENERATED scheduler content from its live source-of-truth (S13, S20).
The whole-file residuals are recomputed from goal `current:` flags, scope refs, and
open task `issue:` tags; the fenced `## affects` rollups in slice and proj `state.md`
are recomputed from the union of each task's hand-edited `## affects` list (S18).
Everything outside a generated region is left byte-for-byte intact (R6). Identical
source yields identical bytes (R10), so regen is also a drift detector: a non-empty
rebuild count means an on-disk generated region no longer matched its source.

## when to use

- "regen the scheduler" / "rebuild the residuals" / "refresh the affects rollup".
- After hand-editing a goal item's `current:` flag, a slice `scope.md` ref, a task
  `## affects` list, or a task `issue:` tag, and you want the derived content resynced.
- As a drift check: run it and expect `hash-stable (no drift)`; any rebuilt region
  means a generated region had drifted from its source.
- Auto-chained: invoked by `ratmac-close`, `ratmac-scope`, and `ratmac-transit` after
  they flip a goal flag, edit scope, freeze a task's affects, or close a tier.

## invocation

pwsh (primary, R4):

```
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-regen/scripts/regen.ps1 [-Root <path>] [-Proj <p-name>] [-Tier all|proj|slice] [-Ts <stamp>]
```

posix (shadow, R4):

```
bash E:/packs/skills/ratmac-skills/skills/ratmac-regen/scripts/regen.sh [--root <path>] [--proj <p-name>] [--tier all|proj|slice] [--ts <stamp>]
```

Roots resolve via the shared `_common` engine: explicit `-Root`/`--root` (a scheduler
dir holding `p-*` children, or a `p-<name>` dir directly) → env `RATMAC_SCHEDULER_ROOT`
→ ancestor walk of the cwd preferring an `arca/scheduler` mount, then a `scheduler` dir,
then any dir holding `p-*` children. The active project is the `-Proj` arg, else the
single `p-*` child, else the one whose `state.md` is `status: active`. Mode
(`maintainer | sole | dual`) is read from the proj `state.md` and gates which residuals
are rebuilt.

## inputs

| param | flag (pwsh / posix) | required | default | meaning |
|---|---|---|---|---|
| Root | `-Root` / `--root` | no | resolved via env / cwd walk | scheduler root holding `p-*` projects, or a `p-<name>` dir directly |
| Proj | `-Proj` / `--proj` | no | single `p-*`, else the `status: active` one | which project to regen inside |
| Tier | `-Tier` / `--tier` | no | `all` | which rollup tier to rebuild: `all` (residuals + slice + proj `## affects`), `slice` (residuals + slice rollups, skip proj rollup), `proj` (also rebuild the proj `## affects` union). Per-slice residuals + slice rollups always run; `Tier` only gates the proj-level union. |
| Ts | `-Ts` / `--ts` | no | `Get-Date` / `date` (`yyyy-MM-dd-HH:mm:ss`) | timestamp override stamped into `time-modified` on any file that actually changes (and preserved as `time-created` on first residual write); pass it to pin deterministic, idempotent output. |

## outputs

Prints `regen: <N> generated region(s) rebuilt`, then the uniform ratmac output
contract (R7):

```contract
Run mode: single
Active proj: <p-name>
Files generated: /<p-name>/goal-residual.md, /<p-name>/s-<slice>/state.md, /<p-name>/state.md, ...
Regen result: hash-stable (no drift) | <N> regions rebuilt
Next safe action: ratmac-lint to verify
```

`Files generated` lists every region that actually changed (forward-slashed abs paths);
on a clean pass it is empty and `Regen result` is `hash-stable (no drift)`. The
residuals rebuilt are mode-gated: `goal-residual.md` + per-slice `scope-residual.md` in
`sole|dual`, per-slice `issues-residual.md` in `maintainer|dual`; the fenced `## affects`
rollups run in every mode.

## stop rules

- **Bad `-Tier` value (posix) / unknown arg.** The POSIX shadow validates `--tier` ∈
  `all|proj|slice` and rejects unknown flags, printing `BLOCKED: ...` before the contract
  and exiting `2`. The pwsh `[ValidateSet]` rejects bad `-Tier` at param binding.
- **Project unresolvable.** If roots cannot be located or the active `p-*` cannot be
  disambiguated, the engine throws / the shadow prints `BLOCKED: cannot resolve project`,
  emits a contract with `Blocked items`, and exits `2`.
- Otherwise regen does not stop — it silently rewrites generated regions and reports the
  count. A hand-edit found inside a fence is treated as drift and overwritten (the source
  of truth wins); back up manual notes outside the markers first. R12
  (`HUMAN_DECISION_REQUIRED`) never fires here — regen never picks a write branch, it only
  recomputes derived content from source.

## composes

- after: `ratmac-init` (loads the S1–S20 invariants + the R7 output contract), then
  `ratmac-route` to orient the session.
- triggers: run `ratmac-lint` afterward to confirm fence integrity (S20), residual
  sentinels (S13), and `time-modified` bumps (S6). regen itself is auto-chained (R18) by
  `ratmac-close` (slice + proj rollups, residuals), `ratmac-scope` (`scope-residual` +
  `goal-residual`), and `ratmac-transit` (final tier rollup). regen never spawns itself.

## refs

- [references/regen-protocol.md](references/regen-protocol.md) — the step-by-step protocol
  `regen.ps1` implements: what is generated, the residual + fenced-rollup builds, mode
  gating, and idempotence as a drift detector (S13/S20/R10).
- [assets/claude-code-command.md](assets/claude-code-command.md) — paste-to-invoke command seed.
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/` — see `skill-contracts.md`
  (ratmac-regen entry), `invariants.md` (R5/R6/R7/R10/R12/R18), `model.md`, `layout.md`,
  `orchestration.md`, `open-questions.md`.
- upstream data model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/` — `invariants.md`
  (S13/S18/S19/S20), `lifecycle.md` (the regen steps inside close/scope/transit),
  `layout.md`, `file-roles.md`.
