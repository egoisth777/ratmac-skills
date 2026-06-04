---
name: ratmac-close
description: Use when a scheduler task is genuinely done or abandoned and needs to be sealed and filed away — trigger phrases: "close this task", "mark t-... done", "archive the task", "task is finished / abandoned", "wrap up t-...", "ship and file this one". It freezes the task's `## affects` deliverable list, sets `status: done|abandoned` in the task `state.md` frontmatter, writes an outcome note into `## scratch`, appends close lines to the task and slice `log.md`, optionally flips a `[sole|dual]` goal item to `current: true`, moves the task dir out of `grad/` into `s-<slice>/archive/`, and updates the slice `## tasks` table row — then spawns ratmac-regen to rebuild the affected rollups/residuals (lifecycle "task done / abandoned", steps 1-10). It writes only under the scheduler tree (R5), reads the task `state.md` before mutating it (R9), and STOPS rather than guess: a `done` close with an empty `## affects` is `BLOCKED need affects`, and unchecked `- [ ]` acceptance-criteria in `issue.md` raise `HUMAN_DECISION_REQUIRED` unless you pass `-Force`. Use after $ratmac-init and $ratmac-route; it auto-chains $ratmac-regen and you should run $ratmac-lint after to verify the post-archive state.
---

# ratmac-close

Seal a finished or abandoned task and file it. `ratmac-close` is the lifecycle "task done / abandoned" transition (steps 1-10): it freezes the task's `## affects`, stamps the terminal `status:`, records the outcome and log lines, optionally flips a goal item, moves the task dir from `grad/` into the slice's `archive/`, and upserts the slice `## tasks` row — then spawns `ratmac-regen` so the slice/proj rollups and residuals reflect the now-archived task. It only ever writes under the scheduler tree (R5), reads the task `state.md` first (R9), and never spawns itself (R18) — regen is a sibling.

## when to use

- "close this task" / "mark t-fix-ao-door done" / "this one is shipped, file it".
- A task is genuinely abandoned (not replanned — replan in place with `ratmac-mutate`); "abandon t-...", "drop this task".
- After a checkpoint left a non-empty `## affects` and the acceptance criteria in `issue.md` are all checked, and you want the task moved to `archive/` with the slice table updated.
- When you want the close to cascade: it auto-runs `ratmac-regen` so the slice `## affects` rollup, proj rollup, `goal-residual.md`, `scope-residual.md`, and `issues-residual.md` are rebuilt without a manual step.

Do NOT use it to revive or rework: a replan stays in the same dir via `ratmac-mutate`; `ratmac-close` is terminal and moves the dir to `archive/`.

## invocation

pwsh (primary, R4):

```
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-close/scripts/close.ps1 -Task <ref> -Status done|abandoned [-Cl <id>] [-Outcome <text>] [-Goal <topic>] [-Root <path>] [-Proj <p-name>] [-Ts <stamp>] [-Force]
```

posix (shadow, verb parity):

```
bash E:/packs/skills/ratmac-skills/skills/ratmac-close/scripts/close.sh --task <ref> --status done|abandoned [--cl <id>] [--outcome <text>] [--goal <topic>] [--root <path>] [--proj <p-name>] [--ts <stamp>] [--force]
```

Root/proj/slice resolve via the shared engine (`_common.ps1` / `_common.sh`): explicit `-Root` → env `RATMAC_SCHEDULER_ROOT` → cwd ancestor walk for an `arca/scheduler` mount, a `scheduler` dir, or a dir holding `p-*` children; then the active project (`-Proj`, else the single `p-*`, else the `status: active` one) and its single/active `s-*` slice. The task is resolved to `grad/t-<name>` under that slice.

## inputs

| param | flag (pwsh / posix) | required | default | meaning |
|---|---|---|---|---|
| Task | `-Task` / `--task` | yes | — | task ref (bare name or `t-<name>`, path tail allowed); resolved to `grad/t-<name>` under the active slice |
| Status | `-Status` / `--status` | yes | — | terminal state; `ValidateSet('done','abandoned')` |
| Cl | `-Cl` / `--cl` | no | `—` | changelist / commit id, recorded in the `done` task-log line as `cl:<id>` |
| Outcome | `-Outcome` / `--outcome` | no | — | outcome note; replaces the body of the task `state.md` `## scratch` section and (on `abandoned`) becomes the log `reason:<text>` |
| Goal | `-Goal` / `--goal` | no | — | `[sole\|dual]` goal topic to flip `current: true` in `goal/<topic>.md`; ignored in maintainer mode; missing goal file is a non-fatal note |
| Root | `-Root` / `--root` | no | env / cwd walk | scheduler root holding `p-*` projects |
| Proj | `-Proj` / `--proj` | no | active proj | project selector when more than one `p-*` exists |
| Ts | `-Ts` / `--ts` | no | now | timestamp override (`yyyy-MM-dd-HH:mm:ss`), passed through to regen so the whole chain stamps deterministically |
| Force | `-Force` / `--force` | no | off | bypass the `done`-only gates (empty `## affects`, unchecked acceptance criteria) |

## outputs

A one-line close receipt (`close: <t-name> status:<...> -> archived under <slice>/archive/`, plus an optional goal-flip note), then the uniform ratmac output contract (R7):

```contract
Run mode: single
Active proj: <p-name>
Active slice: <s-name>
Active task: <t-name>
Classification: close-task:<done|abandoned>
Skill chain: ratmac-close -> ratmac-regen
Files touched: <task state.md, task log.md, slice log.md, [goal/<topic>.md], slice state.md>
Regen result: regen spawned | not run
Next safe action: ratmac-lint to verify post-archive
```

Files touched span the task `state.md` (status + scratch outcome), task `log.md`, slice `log.md`, the slice `state.md` (table row), and optionally `goal/<topic>.md`. The task dir itself is moved `grad/t-<name>` → `archive/t-<name>`; the rollups/residuals rewritten by the spawned regen show up under its own `Files generated`.

## stop rules

STOP markers print BEFORE the contract:

- **No active slice** under the project → `BLOCKED no active slice under <p-name>` (exit 2).
- **Task not found** in the active slice's `grad/` → `BLOCKED task '<ref>' not found in <slice> grad/` (exit 2).
- **`done` with empty `## affects`** (and no `-Force`) → `BLOCKED need affects: ... empty ## affects list (status=done)` (exit 2). Add affects via `ratmac-checkpoint` first, or pass `-Force`.
- **Unchecked acceptance criteria** — any `- [ ]` line in the task `issue.md`, on a `done` close without `-Force` → `HUMAN_DECISION_REQUIRED AC incomplete: <N> unchecked '- [ ]' item(s)` (exit 3). Resolve them or pass `-Force`.
- **Archive collision** — `archive/<t-name>` already exists → `BLOCKED archive collision: ... cannot move` (exit 2); the move is refused rather than clobbering an existing archived task (R12: never guesses a write branch).

## composes

- after: `ratmac-init` (loads the invariants + output-contract template), then `ratmac-route` to confirm the active proj/slice/task before closing.
- triggers: `ratmac-regen` — spawned automatically as a sibling script (R18, never itself) to rebuild the slice/proj `## affects` rollups, `goal-residual.md`, `scope-residual.md`, and `issues-residual.md` (lifecycle steps 6/7/8). The declared chain is `ratmac-close -> ratmac-regen`; run `ratmac-lint` yourself afterward (close does not spawn it).
- after-close: run `ratmac-lint` to verify the archived task, the slice table row, and the regenerated rollups are consistent (lint never writes, R11).

## refs

- [references/close-protocol.md](references/close-protocol.md) — the step-by-step protocol the script implements: done-only gates, status + outcome write, log lines, goal flip, archive move, slice-table upsert, and the regen spawn.
- [assets/claude-code-command.md](assets/claude-code-command.md) — paste-to-invoke command seed.
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md` (ratmac-close entry), plus `invariants.md` (R5/R7/R9/R12/R18), `orchestration.md`, `layout.md`.
- upstream model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/lifecycle.md` ("task done / abandoned", steps 1-10), `file-roles.md`, `invariants.md` (S18-S20), `layout.md`.
