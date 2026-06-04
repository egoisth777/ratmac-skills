---
name: ratmac-scope
description: >-
  Use when a sole/dual-mode slice's scope changes mid-flight — an item turned bigger than planned,
  got deferred, or a new goal item surfaced during work. Trigger phrases: "expand the slice scope",
  "add X to scope", "drop/defer Y from scope", "scope this slice up/down", "this item grew, put it in
  scope", "pull that goal out of the current slice". It edits the active slice's `scope.md` (adds or
  removes a `[[<goal-topic>]]` ref), appends an audit line to `scope-history.md` (S14), logs
  `scope+|- <ref>` to the slice `log.md` (S19), then spawns `ratmac-regen` so `scope-residual.md` and
  `goal-residual.md` refresh — all writes confined to the scheduler tree (R5). It STOPS without touching
  anything when the proj is `maintainer` mode (no scope exists), when the slice has no `scope.md`, when a
  `-Op -` ref isn't actually in scope, or (HUMAN_DECISION_REQUIRED) when `-Op +` names a goal item that
  doesn't exist and `-CreateGoal` wasn't passed. Use after $ratmac-init and $ratmac-route; it composes
  forward by triggering $ratmac-regen, and $ratmac-lint is the next safe action to verify
  scope/residual consistency.
---

# ratmac-scope

Expand or contract a **sole/dual** slice's scope mid-slice. A "scope" is the set of `[[goal-topic]]`
refs in `s-<slice>/scope.md` that say which goal items this slice has committed to deliver. This skill
moves one ref in or out of that set, records the change in the append-only `scope-history.md` ledger
(S14), drops a `scope+`/`scope-` line in the slice `log.md` (S19), then triggers `ratmac-regen` to
rebuild the derived `scope-residual.md` + `goal-residual.md` views (R18). It writes only under the
scheduler tree (R5) and every ambiguity STOPS before the first write (R12), so a scope mutation never
half-applies.

Scope lives only in `sole|dual` projects — `maintainer` mode has no `scope.md`, so the skill BLOCKs
there. The goal item itself (`p-<proj>/goal/<topic>.md`) is the SSoT for what the topic is; scope.md
only references it. On a `-Op +` that names a goal item which does not yet exist, the skill stops and
asks you to either create the goal item first or re-run with `-CreateGoal` to scaffold it (with
`current: false`, since nothing has delivered it yet).

## when to use

- "expand the slice scope to cover `<topic>`" / "add `<topic>` to scope" — `-Op +`.
- "drop `<topic>` from scope" / "defer `<topic>` to a later slice" — `-Op -` (the goal item stays in
  `p-<proj>/goal/`, just leaves this slice's scope).
- "this item grew bigger than planned, pull it into scope" / "scope this slice up".
- "a new goal item surfaced mid-slice, add it" — `-Op + -CreateGoal` to scaffold `goal/<topic>.md` and
  reference it in one shot.
- right after `ratmac-route` tells you the suggested next-action mode is `scope-mutation`.

Do **not** use this to start a slice or task (that is `ratmac-kickoff`), to close a task that delivered
a goal item and flip `current: true` (that is `ratmac-close`), or in a `maintainer`-mode project (there
is no scope to mutate).

## invocation

pwsh (primary, R4):

```
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-scope/scripts/scope.ps1 `
  -Op + -Ref <goal-topic> [-Reason "<short>"] [-CreateGoal] `
  [-Slice <s-name>] [-Root <scheduler>] [-Proj <p-name>] [-Ts <stamp>]
```

posix (shadow, R4 verb parity):

```
bash E:/packs/skills/ratmac-skills/skills/ratmac-scope/scripts/scope.sh \
  --op + --ref <goal-topic> [--reason "<short>"] [--create-goal] \
  [--slice <s-name>] [--root <scheduler>] [--proj <p-name>] [--ts <stamp>]
```

Roots resolve via the shared engine (`_common.ps1` / `_common.sh`): explicit `-Root`/`--root` →
env `RATMAC_SCHEDULER_ROOT` → cwd ancestor walk for an `arca/scheduler` mount, a `scheduler` dir, or
a dir holding `p-*` children. The proj resolves from `-Proj`, else the single `p-*` child, else the
one whose `state.md` is `status: active`.

## inputs

| param | flag (pwsh / posix) | required | default | meaning |
|---|---|---|---|---|
| Op | `-Op` / `--op` | yes | — | `+` add the ref to scope, `-` remove it (`ValidateSet('+','-')`) |
| Ref | `-Ref` / `--ref` | yes | — | goal topic; bare name (a trailing `.md` or `path/` tail is stripped to the leaf) |
| Reason | `-Reason` / `--reason` | no | `—` (history) / goal `PROBLEM` placeholder | short reason recorded in `scope-history.md`; also seeds a scaffolded goal item's problem |
| CreateGoal | `-CreateGoal` / `--create-goal` | no | off | on `-Op +`, scaffold `goal/<topic>.md` (with `current: false`) when it is missing instead of stopping |
| Slice | `-Slice` / `--slice` | no | active slice | explicit slice ref (`s-` prefix optional); else the active slice under the proj |
| Root | `-Root` / `--root` | no | env / cwd walk | scheduler root holding `p-<name>` subtrees |
| Proj | `-Proj` / `--proj` | no | active / sole | project selector (`p-<name>`) |
| Ts | `-Ts` / `--ts` | no | `Get-Date` | timestamp override; passed through to `ratmac-regen` so callers can pin deterministic stamps |

## outputs

A one-line human receipt (`scope+ <topic> in <slice>` / `scope- <topic> in <slice>`, with a
`(goal item scaffolded, current: false)` suffix when `-CreateGoal` fired, and a `no-op add` note when
the ref was already present), then the uniform ratmac output contract (R7):

```contract
Run mode: single
Active proj: <p-name>
Active slice: <s-name>
Classification: scope-mutation:<+|->
Skill chain: ratmac-scope -> ratmac-regen
Files touched: <slice>/scope.md, <slice>/scope-history.md, <slice>/log.md[, goal/<topic>.md]
Regen result: regen spawned | not run
Next safe action: ratmac-lint to verify scope/residual consistency
```

`scope-residual.md` and `goal-residual.md` are not written by this skill — they are rebuilt by the
spawned `ratmac-regen` and surface there as its generated outputs.

## stop rules

Each STOP prints its marker line **before** the contract, writes nothing, and exits non-zero (R12):

- **maintainer mode** — proj `state.md` `mode: maintainer` → `BLOCKED maintainer mode has no scope
  (scope.md/scope-history.md exist only in sole|dual)`; exit 2.
- **slice not found** — explicit `-Slice` resolves to a missing dir → `BLOCKED slice '<s-name>' not
  found under <proj>`; exit 2.
- **no active slice** — no `-Slice` given and the proj has no resolvable active slice →
  `BLOCKED no active slice under <proj>`; exit 2.
- **scope.md missing** — the slice has no `scope.md` (not sole/dual-scoped) → `BLOCKED scope.md missing
  in <s-name> ...`; exit 2.
- **missing goal item on `-Op +`** — `goal/<topic>.md` absent and `-CreateGoal` not passed →
  `HUMAN_DECISION_REQUIRED goal item missing: goal/<topic>.md does not exist. Pass -CreateGoal to
  scaffold it, or create the goal item first.`; exit 3.
- **`-Op -` ref not in scope** — `<topic>` is not referenced in `scope.md` (nothing to remove) →
  `BLOCKED scope contract: '<topic>' is not in <s-name>/scope.md (nothing to remove)`; exit 2.

## composes

- **after:** `ratmac-init` (loads R-invariants + the output contract), `ratmac-route` (orient — it
  suggests `scope-mutation` as the next-action mode).
- **triggers on success:** `ratmac-regen` (R18) — rebuilds `scope-residual.md` (scope refs ∩ goal
  `current:` flags) and `goal-residual.md`. Skill chain reported as `ratmac-scope -> ratmac-regen`.
  `-Root`/`-Proj`/`-Ts` are passed through so regen runs against the same proj with the same stamp.
- **next safe action:** `ratmac-lint` to verify scope/residual consistency (lint is read-only, R11).
- relates to `ratmac-kickoff` (the `-CreateGoal` path scaffolds a goal item from kickoff's
  `goal-topic.md.tpl`) and `ratmac-close` (which flips a goal item's `current: true` on delivery).

## refs

- `references/scope-protocol.md` — the step-by-step protocol `scope.ps1` implements: mode/slice
  resolution, the goal-ref normalization, the `scope.md` add/remove edit, the S14 `scope-history.md`
  ledger line, the S19 slice log line, and the post-write regen spawn.
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/` — `skill-contracts.md` (ratmac-scope entry),
  `invariants.md` (R5, R7, R9, R12, R18), `model.md`, `orchestration.md`, `layout.md`.
- upstream data model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/lifecycle.md` (scope-mutation
  section), `invariants.md` (S14 scope-history, S19 log-stream), `layout.md`, `file-roles.md`.
