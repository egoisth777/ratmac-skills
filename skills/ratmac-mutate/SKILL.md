---
name: ratmac-mutate
description: >-
  Use when an in-flight scheduler task needs an in-place revision rather than a new task — trigger
  phrases: "replan this task", "the CR changed the approach", "revise the plan for t-foo", "the
  ticket grew new AC", "scope of the issue changed, update it", "append a ticket update", or any
  "same issue, different plan" moment. It revises `task.md` (plan/approach) or appends a `## ticket
  updates` block to `issue.md`, then logs a `replan` / `ticket-update` line — NEVER forking a
  `t-<name>-rework/` sibling, because S15 binds one active task per `issue:` tag and S16 says revise
  in place. It writes only under the scheduler tree (R5), reads `state.md` first (R9), and STOPS with
  HUMAN_DECISION_REQUIRED when `task.md` is newer than `state.md` (likely a manual edit, S15) rather
  than clobber your work. Use after $ratmac-init and $ratmac-route; hand off to $ratmac-checkpoint to
  refresh task state, then $ratmac-lint to verify, and $ratmac-regen if a residual rollup is affected.
---

# ratmac-mutate

In-place plan / approach / ticket revision for a live scheduler task (S15, S16). One task per `issue:`
tag: when a code review, new information, or an upstream ticket change forces a different plan, you
**revise the existing task — you never spawn a `t-<name>-rework/` sibling.** Plan/approach changes
rewrite (or bump) `task.md`; ticket changes append a `## ticket updates` block to `issue.md`,
preserving the original problem statement. Every mutation appends one line to the task `log.md`.
Writes land only under `scheduler/` (R5) and the relevant `state.md` is read before any write (R9).

## when to use

- "replan `t-foo`" / "the approach was wrong, revise the plan" / "CR says use a different class"
- "the ticket changed — new AC / scope grew / requirements revised" → `-Kind ticket`
- "append a ticket update note to the issue"
- "swap in this rewritten task.md" (you have a replacement file) → pass it via `-Diff`
- any "same issue, different plan/approach" moment where the instinct to fork a rework task must be
  redirected into an in-place revision (S15)

Do **not** use this to create a task (that is `ratmac-kickoff`), to update live cursor state / status /
affects (that is `ratmac-checkpoint`), or to close/archive a task (that is `ratmac-close`). This skill
only revises the *plan* (`task.md`) or the *problem* (`issue.md`); it does not touch `state.md`.

## invocation

pwsh (primary, R4):

```
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-mutate/scripts/mutate.ps1 `
  -Task t-foo -Kind plan -Reason "dan-cr-wrong-class" [-Diff E:/path/new-task.md] `
  [-Root <scheduler>] [-Proj p-lotus] [-Ts <stamp>] [-Force]
```

posix (shadow, verb parity):

```
bash E:/packs/skills/ratmac-skills/skills/ratmac-mutate/scripts/mutate.sh \
  --task t-foo --kind plan --reason "dan-cr-wrong-class" [--diff <new-task.md>] \
  [--root <scheduler>] [--proj p-lotus] [--ts <stamp>] [--force]
```

Context resolves through the engine: `Get-RatmacProj` (explicit `-Proj`, else the single `p-*`, else
the one whose `state.md` is `status: active`), `Get-RatmacActiveSlice` (single non-archive `s-*`, else
the active one), then `Resolve-RatmacTask` locates `s-<slice>/grad/t-<task>/`.

## inputs

| param | flag (pwsh / posix) | required | meaning |
|---|---|---|---|
| Task | `-Task` / `--task` | yes | task ref; bare name or `t-<name>`, resolved under the active slice's `grad/` |
| Kind | `-Kind` / `--kind` | yes | `plan` \| `approach` \| `ticket` — what is being revised (validated set) |
| Reason | `-Reason` / `--reason` | yes | short reason logged with the mutation (e.g. `dan-cr-wrong-class`) |
| Diff | `-Diff` / `--diff` | no | path to a file: replacement `task.md` body (plan/approach) or appended ticket text. Absent → plan/approach just bumps `time-modified`; ticket uses `-Reason` as the update text |
| Root | `-Root` / `--root` | no | scheduler root holding `p-*`; else env `RATMAC_SCHEDULER_ROOT` / cwd-ancestor walk |
| Proj | `-Proj` / `--proj` | no | project to disambiguate when more than one `p-*` exists |
| Ts | `-Ts` / `--ts` | no | timestamp override for `time-modified` bumps + log lines (else now) |
| Force | `-Force` / `--force` | no | override the S15 stop (task.md newer than state.md) and revise anyway |

## outputs

A one-line human receipt (`mutate <kind>: t-<task> — <reason>`) then the uniform ratmac output
contract (R7). For `plan`/`approach`, `Files touched` is `task.md` + `log.md`; for `ticket`, it is
`issue.md` + `log.md`.

```contract
Run mode: single
Active proj: p-lotus
Active slice: s-vert
Active task: t-foo
Skill chain: ratmac-mutate
Files touched: <grad/t-foo/task.md|issue.md>, <grad/t-foo/log.md>
Next safe action: update task state.md via ratmac-checkpoint; ratmac-lint
```

## stop rules

Printed as a `BLOCKED <reason>` (exit 2) or `HUMAN_DECISION_REQUIRED <reason>` (exit 3) line **before**
the contract block (R12 — auto never guesses a write branch):

- **no active slice** under the project → `BLOCKED no active slice under <p-proj>`; exit 2.
- **task not found** in `grad/` → `BLOCKED task '<task>' not found in grad/`; exit 2.
- **`-Diff` path missing** → `BLOCKED -Diff path '<path>' not found`; exit 2.
- **S15 manual-edit guard** (plan/approach only) — `task.md` `time-modified` is newer than `state.md`
  `time-modified`, so the plan was likely already revised by hand →
  `HUMAN_DECISION_REQUIRED task.md is newer than state.md — likely already revised manually (S15). Pass -Force to override.`;
  exit 3. Re-run with `-Force` to proceed.

## composes

- **after:** `ratmac-init` (loads S1–S20 + the output contract), `ratmac-route` (orient: which proj /
  slice / task is active) before choosing to mutate.
- **hand off / triggers:** `ratmac-mutate` itself only revises plan/problem — it does **not** touch
  `state.md` and does **not** auto-chain. The contract's next safe action is `ratmac-checkpoint`
  (record the new direction in the task's live cursor + status, S16 step) and then `ratmac-lint` to
  verify (S6 time-modified bump, S15/S16 one-task-per-issue, dangling links). If a plan revision changes
  what a residual rollup depends on (sole/dual: scope/goal residuals; maintainer/dual: issues-residual),
  run `ratmac-regen` afterward — regen is byte-idempotent on stable input (R10), so it is safe to run as
  a no-op drift check.

## refs

- [`references/mutate-protocol.md`](references/mutate-protocol.md) — the step-by-step protocol the script
  implements: the plan/approach branch, the ticket branch, the S15 newer-than guard, and the generated /
  log discipline.
- [`assets/claude-code-command.md`](assets/claude-code-command.md) — paste-to-invoke command seed.
- Spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md` (ratmac-mutate entry),
  `.../invariants.md`; data model `brain/buf/sparks/pdrft-brain-v3/s-scheduler/{invariants,lifecycle}.md`
  (S15 one-task-per-issue, S16 issue mutation, S18 affects, S19 log).
