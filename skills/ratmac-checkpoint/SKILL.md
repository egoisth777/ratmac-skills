---
name: ratmac-checkpoint
description: >-
  Use at any meaningful pause during task work to snapshot progress into the scheduler — trigger phrases:
  "checkpoint this task", "snapshot my progress", "record where I am on t-X", "note this blocker", "I touched
  these files, log them", "mark the task blocked/active", "pause and save state". It rewrites the task
  state.md `## status` line to your note, appends a dated `- <ts> <note>` bullet to the task state.md
  `## scratch` section (creating it if absent), bumps `time-modified` (S6), optionally adds paths to the
  hand-edited `## affects` list (S18, deduped), appends a `<ts> checkpoint <note>` line to the task log.md (S19), and — only
  when `-Status` flips active↔blocked — also updates the task frontmatter, the slice state.md task-table row,
  and the slice log.md. It writes ONLY under the scheduler tree (R5), reads the task state.md before touching it
  (R9), and never moves or archives a task (that is ratmac-close). Use after $ratmac-init and $ratmac-route;
  it triggers no sibling skill itself — run $ratmac-lint afterward to verify, and $ratmac-close when the AC is met.
---

# ratmac-checkpoint

Snapshot pause for an active task. Records "where am I right now" without changing the plan or archiving
anything: it replaces the task `state.md` `## status` body with your note's first line, appends a dated
`- <ts> <note>` bullet to the task `state.md` `## scratch` section (creating the section if it is absent),
bumps `time-modified`, optionally grows the hand-edited `## affects` list, and appends a `checkpoint` line
to the task `log.md`. A
`-Status` change (active↔blocked) is the only thing that ripples upward — to the task frontmatter, the slice
task table, and the slice log. Writes live entirely under `scheduler/` (R5) and the task `state.md` is read
before it is written (R9).

## when to use

- End of a work session, a step boundary, or hitting a blocker — "checkpoint t-fix-ao-door-intensity".
- "Snapshot my progress" / "record where I am" / "note this and move on".
- "I touched `Foo.cpp` and `Bar.h`, add them to affects" — grow the `## affects` file list (S18).
- "Mark this task blocked" / "I'm unblocked, set it active again" — a `-Status` flip that updates the slice
  table + log as well.
- Right after `ratmac-route` reports the next-action mode is `continue-task`.

Do NOT use to revise the plan/approach (use `ratmac-mutate`), to close or abandon a task (use
`ratmac-close` — it freezes affects and `mv`s the dir), or to touch anything outside the scheduler tree (R5).

## invocation

pwsh (primary, R4):

```
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-checkpoint/scripts/checkpoint.ps1 `
  -Task <ref> -Note "<text>" `
  [-AddAffects <path1>,<path2>] [-Status active|blocked] `
  [-Root <scheduler|p-dir>] [-Proj <p-name>] [-Ts <stamp>]
```

posix (shadow, R4 — verb parity):

```
bash E:/packs/skills/ratmac-skills/skills/ratmac-checkpoint/scripts/checkpoint.sh \
  --task <ref> --note "<text>" \
  [--add-affects <path1>,<path2>] [--status active|blocked] \
  [--root <scheduler|p-dir>] [--proj <p-name>] [--ts <stamp>]
```

Roots resolve via the shared engine: explicit `-Root`/`--root` (a `scheduler/` dir holding `p-*`, or a
`p-<name>` dir directly) → env `RATMAC_SCHEDULER_ROOT` → cwd ancestor walk (prefers an `arca/scheduler`
mount, then a `scheduler` dir, then any dir holding `p-*` children). The active project and active slice are
then resolved by `Get-RatmacProj` / `Get-RatmacActiveSlice`, and the task by `Resolve-RatmacTask` against the
slice's `grad/`.

## inputs

| param | flag (pwsh / posix) | required | default | meaning |
|---|---|---|---|---|
| Task | `-Task` / `--task` | yes | — | task ref; bare name or `t-<name>` (the `t-` prefix is added if absent), resolved under the active slice's `grad/`. |
| Note | `-Note` / `--note` | yes | — | the checkpoint note. Its first line replaces the `## status` body and is the `log.md` arg. |
| AddAffects | `-AddAffects` / `--add-affects` | no | none | one or more paths to add (deduped, S18/RQ13) to the task `## affects` list. |
| Status | `-Status` / `--status` | no | unchanged | `active` or `blocked`; only a real change ripples to frontmatter + slice table + slice log. |
| Root | `-Root` / `--root` | no | env / cwd walk | a `scheduler/` dir holding `p-*`, or a `p-<name>` dir directly. |
| Proj | `-Proj` / `--proj` | no | single / active | project selector when more than one `p-*` exists and none is uniquely active. |
| Ts | `-Ts` / `--ts` | no | `Get-Date` | timestamp override; flows through `Get-RatmacStamp` so callers can pin deterministic stamps. |

## outputs

A short human-readable receipt, then the uniform ratmac output contract (R7) emitted by `Write-RatmacContract`:

```
checkpoint: t-<name> — <note first line>
  affects +<n> (dup <m>)          # only when -AddAffects given
  status -> <blocked|active> (slice table + log updated)   # only when -Status changed
```

```contract
Run mode: single
Active proj: p-<name>
Active slice: s-<name>
Active task: t-<name>
Skill chain: ratmac-checkpoint
Files touched: <task state.md>, <task log.md>[, <slice state.md>, <slice log.md>]
Next safe action: continue work, or ratmac-close when AC met; ratmac-lint to verify
```

`Files touched` always includes the task `state.md` and `log.md`; it additionally lists the slice
`state.md` and `log.md` only on a `-Status` change. The script writes no GENERATED regions, so there is no
`Files generated` / `Regen result` line.

## stop rules

STOP markers print BEFORE the contract; exit 2 = `BLOCKED`, exit 3 = `HUMAN_DECISION_REQUIRED`.

- **no active slice** — the active project exposes no single/active `s-*` slice → `BLOCKED no active slice
  under <proj>`, contract with `Blocked items: no active slice`, exit 2.
- **task not in grad/** — the ref does not resolve to a `grad/t-<name>` dir under the active slice →
  `BLOCKED task '<task>' not found in <slice> grad/ (archived tasks use ratmac-mutate or revive)`, contract
  with `Blocked items: task '<task>' not in grad/`, exit 2. Checkpoint never reaches into `archive/`.

(Root/project resolution failures surface as `BLOCKED:` from the shared engine before the script body runs.)

## composes

- **after:** `ratmac-init` (loads S1–S20 + the output contract), then `ratmac-route` to confirm
  `continue-task` and which task is in flight.
- **triggers:** none. Checkpoint is a leaf write — it does not chain to `ratmac-regen` or `ratmac-lint`,
  because it touches no GENERATED rollups and changes no archive/scope state. (Contrast `ratmac-close` /
  `ratmac-scope` / `ratmac-transit`, which DO auto-chain regen, per R18.)
- **verify / next:** run `ratmac-lint` to check frontmatter + `time-modified` bump (S5/S6) and dangling
  links; run `ratmac-close` when the acceptance criteria are met (it freezes `## affects` and archives the
  task, then chains regen).

## refs

- `references/checkpoint-protocol.md` — the exact step-by-step the script implements (status-body rewrite,
  `time-modified` bump, affects dedupe, log append, conditional status ripple) keyed to S6/S18/S19/S20.
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md` (ratmac-checkpoint entry),
  `invariants.md` (R5/R7/R9/R12/R18), `model.md`, `orchestration.md`, `layout.md`, `open-questions.md`.
- upstream model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/` — `lifecycle.md` (work checkpoint),
  `invariants.md` (S6/S18/S19/S20), `file-roles.md` (state.md = snapshot, log.md = stream).
