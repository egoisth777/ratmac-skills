---
name: ratmac-transit
description: >-
  Use when a slice is ending or a project is retiring and you need to freeze, summarize, and
  archive a whole tier — trigger phrases: "transit the slice", "close out this slice", "ship the
  milestone and move to the next slice", "retire the project", "archive p-lotus", "the vertical
  slice is done — what's next", "roll over to s-mp-alpha". It runs the lifecycle slice-transition /
  proj-retirement protocol (lifecycle steps 1–9 / proj 1–3): a final `ratmac-regen` of the tier's
  `## affects` rollup, writes `summary.md` (literal text or a supplied file, Q5 one-pager), sets
  `status: done`, and `mv`s the tier dir into the parent's `archive/`. For a slice it also points the
  proj `state.md` at the successor and logs `close-slice` / `active-slice`; for a proj it logs
  `retired` and moves the dir under `scheduler/archive/`. It writes ONLY under the scheduler tree
  (R5), reads the relevant `state.md` first (R9), and every STOP fires BEFORE any write so an
  ambiguous tier never half-transits (R12). Use after $ratmac-init, $ratmac-route, and $ratmac-close
  (live tasks must be closed/migrated first); it calls $ratmac-regen for the final rollup and
  $ratmac-lint to verify the archived tree.
---

# ratmac-transit

Slice/proj transition: the terminal lifecycle step. It freezes a tier (regen the final `## affects`
rollup), records a `summary.md` one-pager, flips `status: done`, and moves the tier dir into its
parent's `archive/`. For a slice it hands the proj its successor pointer (or ends the line); for a
proj it retires the whole project under `scheduler/archive/`. It writes only under the scheduler
tree (R5) and never auto-creates the successor slice — that is `ratmac-kickoff`'s job.

## when to use

- "transit the slice" / "close out s-vert" / "the milestone shipped, archive the slice".
- "roll over to the next slice" / "move to s-mp-alpha" (pass the successor with `-NewSlice`).
- "this slice is the last one — end the line" (pass `-NoSuccessor`).
- "retire the project" / "archive p-lotus" / "the project is done" (`-Tier proj`).
- After every live task in the slice has been closed or migrated (run `ratmac-close` first).

Do **not** use this to close a single task (that is `ratmac-close`), to start the next slice (that is
`ratmac-kickoff`), or to revise a plan in place (that is `ratmac-mutate`). Transit only ends a tier.

## invocation

pwsh (primary, R4):

```
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-transit/scripts/transit.ps1 `
  -Tier slice -Summary "what shipped / what carried forward / key decisions" `
  [-NewSlice s-mp-alpha] [-NoSuccessor] [-Root <scheduler>] [-Proj <p-name>] [-Ts <stamp>] [-Force]
```

posix (shadow):

```
bash E:/packs/skills/ratmac-skills/skills/ratmac-transit/scripts/transit.sh \
  --tier slice --summary "what shipped / what carried forward / key decisions" \
  [--new-slice s-mp-alpha] [--no-successor] [--root <scheduler>] [--proj <p-name>] [--ts <stamp>] [--force]
```

Roots resolve via the shared engine (`_common.ps1` / `_common.sh`): explicit `-Root`/`--root` →
env `RATMAC_SCHEDULER_ROOT` → cwd-ancestor walk for an `arca/scheduler` mount, a `scheduler` dir,
or any dir already holding `p-<name>` children. The active proj is the single `p-*` child, the one
flagged `status: active`, or whatever `-Proj` names.

## inputs

| param | flag (pwsh / posix) | required | default | meaning |
|---|---|---|---|---|
| Tier | `-Tier` / `--tier` | yes | — | `slice` or `proj` — which tier to transit |
| Summary | `-Summary` / `--summary` | yes | — | one-pager: literal text (wrapped with frontmatter into `summary.md`) OR a path to an existing file (copied verbatim) |
| NewSlice | `-NewSlice` / `--new-slice` | no (slice) | — | successor slice short-name; sets the proj `active slice:` pointer (the `s-` prefix is added if omitted). NOT auto-created |
| NoSuccessor | `-NoSuccessor` / `--no-successor` | no (slice) | off | end the slice line — no successor expected |
| Root | `-Root` / `--root` | no | env / cwd walk | scheduler root holding `p-<name>` subtrees |
| Proj | `-Proj` / `--proj` | no | active proj | project short-name when more than one exists |
| Ts | `-Ts` / `--ts` | no | `Get-Date` | timestamp override (pins deterministic stamps for `time-modified`, logs, chained regen) |
| Force | `-Force` / `--force` | no | off | (slice only) archive the slice even with live tasks still in `grad/` |

`-NewSlice` and `-NoSuccessor` are slice-tier only; `-Force` only relaxes the live-task STOP on a
slice. On the proj tier neither successor flag nor `-Force` applies.

## outputs

A human-readable transit report, then the uniform ratmac output contract (R7). For a slice the
report is `transit slice: <s-name> archived under <p-name>` plus a `next:` line (the kickoff hint
for `-NewSlice`, or "slice line ended" for `-NoSuccessor`); for a proj it is
`transit proj: <p-name> retired → <archive path>`.

```contract
Run mode: single
Active proj: p-lotus
Active slice: s-vert (archived)
Classification: slice-transit
Skill chain: ratmac-transit -> ratmac-regen -> ratmac-lint
Files touched: <summary.md, state.md, log.md, archive/<s-name>, proj state.md>
Regen result: proj rollup rebuilt (final)
Lint result: <first line of ratmac-lint output>
Next safe action: ratmac-kickoff -Tier slice -Name <s-new> (NOT auto-created)
```

For `-Tier proj` the contract reads `Active proj: <p-name> (retired)`, `Classification: proj-retire`,
and `Next safe action: none — project archived`.

## stop rules

Printed as a `BLOCKED <reason>` (exit 2) or `HUMAN_DECISION_REQUIRED <reason>` (exit 3) line
**before** the contract block — and always before any write or regen, so an ambiguous tier never
half-transits (R12):

- **no active slice** (`-Tier slice`) — no non-archive `s-*` under the proj → `BLOCKED no active slice under <p-name>`; exit 2.
- **live tasks present** (`-Tier slice`) — one or more `t-*` dirs still in `grad/` → `HUMAN_DECISION_REQUIRED active tasks present: <list>`; exit 3. Close/migrate them with `ratmac-close`, or pass `-Force` to archive anyway.
- **no successor declared** (`-Tier slice`) — neither `-NewSlice` nor `-NoSuccessor` given → `HUMAN_DECISION_REQUIRED no successor slice`; exit 3. Pass `-NewSlice <s-name>` for the successor, or `-NoSuccessor` to end the line.

The proj tier has no STOPs in this script — a proj retirement assumes its slices are already archived.

## composes

- **after:** `ratmac-init` (loads R1–R18 + the output contract), `ratmac-route` (orient — confirm
  the active slice/proj and that no live tasks remain), and `ratmac-close` (every live task must be
  closed or migrated before a slice transits; the live-task STOP enforces this unless `-Force`).
- **triggers on run:** `ratmac-regen` twice — once up front so the final `## affects` rollup reflects
  the slice before it freezes, and once after the move to settle the proj rollup — then `ratmac-lint`
  to verify the archived tree (R18: spawns sibling scripts, never itself). Skill chain:
  `ratmac-transit -> ratmac-regen -> ratmac-lint`.
- **next:** for `-NewSlice`, `ratmac-kickoff -Tier slice -Name <s-new>` (transit only sets the
  pointer; kickoff scaffolds the successor).

## refs

- `references/transit-protocol.md` — the step-by-step protocol the script implements: the slice-tier
  STOP gates, regen / summary / `status: done` / archive sequence, the proj-pointer bookkeeping, and
  the proj-retirement variant.
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md` (ratmac-transit entry),
  `.../invariants.md` (R5, R6, R7, R9, R10, R11, R12, R18), `.../model.md`, `.../orchestration.md`,
  `.../layout.md`.
- spec: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/lifecycle.md` (slice transition steps 1–9,
  proj retirement steps 1–3, Q5 summary one-pager), `.../invariants.md` (S13, S18, S19, S20),
  `.../layout.md`, `.../file-roles.md`.
