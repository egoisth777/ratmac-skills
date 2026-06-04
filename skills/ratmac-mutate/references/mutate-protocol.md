# ratmac-mutate protocol

How `ratmac-mutate` revises an in-flight task **in place** — and why it never forks a rework sibling.
Source: `skills/ratmac-mutate/scripts/mutate.ps1`; spec
`brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md` (ratmac-mutate); data model
`brain/buf/sparks/pdrft-brain-v3/s-scheduler/{invariants,lifecycle}.md` (S15, S16, S18, S19).

## the one-task-per-issue rule (S15 / S16)

`issue:` is a **tag, not a level**: one active task per `issue:` tag. When a code review, fresh
information, or an upstream ticket change forces a different plan or approach, the lifecycle is
**revise in place — the same `grad/t-<name>/` dir continues.** You do **not** create `t-<name>-rework/`.

There are two distinct mutation shapes, selected by `-Kind`:

- **plan / approach mutation** (S15, lifecycle "plan / approach mutation"): the *plan* changed. Revise
  `task.md`.
- **ticket mutation** (S16, lifecycle "ticket mutation", maintainer/dual): the *upstream ticket* changed
  (new AC, scope grew, requirements revised). Append a `## ticket updates` block to `issue.md`, preserving
  the original problem statement at the top.

Both append exactly one append-only line to the task `log.md` (S19): `<ts> replan <reason>` for
plan/approach, `<ts> ticket-update <reason>` for ticket. `state.md` is a snapshot; `log.md` is the stream —
the live cursor update (status / scratch / affects) is a separate `ratmac-checkpoint` step, not this skill.

## step 0 — resolve context and read state first (R9)

1. `Get-RatmacStamp $Ts` — pin the timestamp (caller may pass `-Ts` for deterministic stamps).
2. `Get-RatmacProj -Root -Proj` → `@{Root; Proj; Path}`.
3. `Get-RatmacActiveSlice -ProjPath` → active slice abs path, or `BLOCKED no active slice` (exit 2).
4. `Resolve-RatmacTask -SlicePath -Task` → `grad/t-<name>/` dir, or `BLOCKED task '<task>' not found in grad/`
   (exit 2). `Resolve-RatmacTask` normalizes a bare name to `t-<name>`.
5. Bind the four task files: `task.md`, `issue.md`, `state.md`, `log.md`. The `state.md` frontmatter is
   read (R9) for the S15 guard below.

## branch A — `-Kind plan` | `approach`

1. **S15 manual-edit guard** (skipped under `-Force`): if both `task.md` and `state.md` exist and both
   carry `time-modified`, and `task.md`'s `time-modified` is **strictly newer** than `state.md`'s, the
   plan was very likely already revised by hand since the last checkpoint. STOP with
   `HUMAN_DECISION_REQUIRED task.md is newer than state.md — likely already revised manually (S15). Pass -Force to override.`
   (exit 3, R12 — never clobber a write branch on ambiguity). `-Force` overrides and proceeds.
2. **apply the revision:**
   - if `-Diff <path>` is given: it is the **replacement `task.md` body**. Missing path →
     `BLOCKED -Diff path '<path>' not found` (exit 2). Otherwise read it raw and overwrite `task.md`, then
     `Set-RatmacFrontmatterValue task.md time-modified <stamp>` (S6 bump).
   - if `-Diff` is absent: do not rewrite the body — just `Set-RatmacFrontmatterValue task.md time-modified
     <stamp>` so the agent can edit the `task.md` body separately. (The frontmatter bump is the
     machine-verifiable signal that the plan was revised.)
3. `task.md` → touched list.
4. `Add-RatmacLog log.md -Verb replan -Args <reason> -Ts <stamp>` (S19); `log.md` → touched list. The log
   helper creates `log.md` with frontmatter if it does not yet exist, else appends and bumps its
   `time-modified`.
5. Print receipt: `mutate <kind>: t-<name> — <reason>`.

> `approach` and `plan` are the same branch: both are an in-place `task.md` revision logged as `replan`.
> The distinction is purely semantic for the human reading the log/reason.

## branch B — `-Kind ticket`

1. Choose the update text: the raw contents of `-Diff` if it is a readable file, else `-Reason`.
2. Read `issue.md` into lines; `Find-RatmacSection -Name 'ticket updates'`.
3. Build the entry `- <stamp> — <update-text>`.
   - section exists → insert the entry at the section's end (append within the block).
   - section absent → append a blank line, `## ticket updates`, then the entry. The original problem
     statement at the top of `issue.md` is untouched (S16: preserve it).
4. Write `issue.md`; `Set-RatmacFrontmatterValue issue.md time-modified <stamp>` (S6). `issue.md` → touched.
5. `Add-RatmacLog log.md -Verb ticket-update -Args <reason> -Ts <stamp>` (S19); `log.md` → touched.
6. Print receipt: `mutate ticket: t-<name> — <reason>`.

## invariants honored

- **R5 — scheduler-only writes.** Only `grad/t-<name>/{task.md,issue.md,log.md}` are written; never
  `store/`, spaces, or code.
- **R9 — read state first.** `state.md` frontmatter is read before the plan/approach branch decides
  whether to STOP.
- **R7 — uniform contract.** The run always ends by emitting `Write-RatmacContract` with `Run mode`,
  `Active proj`, `Active slice`, `Active task`, `Skill chain` (`ratmac-mutate`), `Files touched`, and a
  `Next safe action` of `update task state.md via ratmac-checkpoint; ratmac-lint`.
- **R12 — auto STOPS, never guesses.** The S15 newer-than-state guard surfaces `HUMAN_DECISION_REQUIRED`
  rather than overwriting a hand-revised `task.md`.
- **R18 — no self-spawn.** ratmac-mutate does not chain another skill's script; it reports the next safe
  action and lets the caller (or `ratmac-auto`) drive `ratmac-checkpoint` / `ratmac-lint` / `ratmac-regen`.
- **S18 / S19 separation.** `## affects` (S18) and live status live in `state.md` and are *not* touched
  here — that is `ratmac-checkpoint`. This skill only revises the plan (`task.md`) or problem
  (`issue.md`) and records the op in the append-only `log.md` (S19).

## what to run next

- `ratmac-checkpoint -Task t-<name> -Note "<new direction>"` — record the new plan direction in the task's
  live cursor (`## status` / `## scratch`) and, if status flipped, the slice table. (lifecycle: "update
  task `state.md` `## status` to reflect new direction".)
- `ratmac-lint` — verify S6 (time-modified bump), S15/S16 (one task per issue, no rework fork), and that no
  `[[t-...]]` links dangle.
- `ratmac-regen` — only if the revised plan changes what a residual rollup covers (sole/dual scope/goal
  residuals; maintainer/dual issues-residual). Byte-idempotent on stable input (R10), so safe as a no-op
  drift check.

## related

- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md`, `.../invariants.md`
- data model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/lifecycle.md`
  ("plan / approach mutation", "ticket mutation"), `.../invariants.md` (S15, S16, S18, S19)
