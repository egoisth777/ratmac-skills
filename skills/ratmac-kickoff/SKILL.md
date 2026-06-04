---
name: ratmac-kickoff
description: >-
  Use when STARTING a new scheduler tier — trigger phrases: "kickoff a project/slice/task",
  "start a new task for <ticket>", "scaffold the s-<slice> slice", "spin up p-<proj>", "new task under
  the active slice", or right after ratmac-route told you the next-action mode is new-task / slice-transit.
  Scaffolds one proj | slice | task tier and its required files (S2/S3 layout) under the scheduler/ tree
  ONLY (R5): proj writes state.md + log.md (and a goal/ dir in sole|dual mode); slice writes
  state.md + log.md + grad/ (and scope.md + scope-history.md in sole|dual mode) and repoints the proj's
  active-slice; task writes the four-file set issue.md/task.md/state.md/log.md plus a slice task-table row
  and slice log line. It STOPS rather than guess (R12): HUMAN_DECISION_REQUIRED when proj kickoff lacks
  -Mode, BLOCKED when the tier already exists (use -Force), when no active slice exists for a task, or
  when maintainer mode is missing the required -Issue tag (S15). Use after $ratmac-init and $ratmac-route;
  it reads the parent state before writing (R9). It does NOT spawn a sibling skill — run $ratmac-lint
  yourself afterward to verify the new tier.
---

# ratmac-kickoff

Scaffold a new scheduler tier — a **proj**, a **slice**, or a **task** — with exactly the files the layout
requires (S2 three-tier hierarchy, S3 four-file task set), writing only under the `scheduler/` tree (R5).
It reads the parent tier's `state.md` before touching it (R9), keeps every generated region inside its
`<!-- GENERATED -->` fence (S20/R6), and ends with the uniform ratmac output contract (R7). On anything
ambiguous it stops with a `BLOCKED`/`HUMAN_DECISION_REQUIRED` marker printed before the contract (R12)
instead of guessing a write branch.

## when to use

- "**kickoff a project** `lotus` in maintainer mode" — lay down `p-lotus/` with `state.md` + `log.md`.
- "**start a new slice** `s-vert`" — scaffold the slice under the active proj and repoint the proj's
  active-slice pointer.
- "**new task** for ticket `EAV-1234`" / "**kickoff** `t-fix-ao-door-intensity` under the active slice" —
  drop the four-file task set, add a slice task-table row, append the slice log line.
- Right after `ratmac-route` suggested next-action mode `new-task` or `slice-transit`.
- You have a tier name and want a correctly-shaped, frontmatter-clean stub set you fill in later.

Do NOT use for: editing an existing task's cursor (use `ratmac-checkpoint`), revising a plan/ticket in
place (use `ratmac-mutate`), closing/archiving (use `ratmac-close`), or anything outside `scheduler/` (R5).

## invocation

pwsh (primary, R4):

```
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-kickoff/scripts/kickoff.ps1 `
  -Tier proj  -Name <kebab> -Mode maintainer|sole|dual [-Role "<text>"] [-Root <sched>] [-Ts <stamp>] [-Force]

pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-kickoff/scripts/kickoff.ps1 `
  -Tier slice -Name <kebab> [-Proj <p-name>] [-Root <sched>] [-Ts <stamp>] [-Force]

pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-kickoff/scripts/kickoff.ps1 `
  -Tier task  -Name <kebab> [-Issue <id>] [-Sprint <id>] [-BlockedBy t-x] [-Problem "<text>"] `
  [-Proj <p-name>] [-Root <sched>] [-Ts <stamp>] [-Force]
```

posix (shadow, verb parity per R4):

```
bash E:/packs/skills/ratmac-skills/skills/ratmac-kickoff/scripts/kickoff.sh \
  --tier proj  --name <kebab> --mode maintainer|sole|dual [--role "<text>"] [--root <sched>] [--ts <stamp>] [--force]

bash E:/packs/skills/ratmac-skills/skills/ratmac-kickoff/scripts/kickoff.sh \
  --tier slice --name <kebab> [--proj <p-name>] [--root <sched>] [--ts <stamp>] [--force]

bash E:/packs/skills/ratmac-skills/skills/ratmac-kickoff/scripts/kickoff.sh \
  --tier task  --name <kebab> [--issue <id>] [--sprint <id>] [--blocked-by t-x] [--problem "<text>"] \
  [--proj <p-name>] [--root <sched>] [--ts <stamp>] [--force]
```

Scheduler root resolves (both engines): explicit `-Root`/`--root` → env `RATMAC_SCHEDULER_ROOT` → cwd
ancestor walk for an `arca/scheduler` mount, a `scheduler` dir, or any dir already holding `p-*` children.

## inputs

| param | pwsh / posix | tier | required | meaning |
|---|---|---|---|---|
| Tier | `-Tier` / `--tier` | all | yes | one of `proj` `slice` `task`; selects the scaffold branch. |
| Name | `-Name` / `--name` | all | yes | kebab tier name; auto-prefixed `p-`/`s-`/`t-` if not already (S7). |
| Mode | `-Mode` / `--mode` | proj | yes (proj) | `maintainer` `sole` `dual`; written to `p-<name>/state.md` frontmatter (S11). Absent on proj kickoff → HUMAN_DECISION_REQUIRED. |
| Role | `-Role` / `--role` | proj | no | one-line proj direction seeded into the proj `## status`. Defaults to `TODO: describe <name> direction`. |
| Issue | `-Issue` / `--issue` | task | mode-cond. | ticket id tag on task `state.md` (S15); **required in maintainer mode**, optional elsewhere. |
| Sprint | `-Sprint` / `--sprint` | task | no | sprint id tag on task `state.md` (S17), free-form (e.g. `2026-w22`). |
| BlockedBy | `-BlockedBy` / `--blocked-by` | task | no | upstream task ref (`t-x`) written to `blocked-by:` frontmatter. |
| Problem | `-Problem` / `--problem` | task | no | problem statement seeded into `issue.md`. Defaults to `TODO: state the problem`. |
| Proj | `-Proj` / `--proj` | slice, task | no | pin the project when more than one `p-*` exists; else single proj / status:active proj is used. |
| Root | `-Root` / `--root` | all | no | scheduler root holding `p-*` subtrees; else env / cwd walk. |
| Ts | `-Ts` / `--ts` | all | no | timestamp override for `time-created`/`time-modified`/log lines (deterministic runs). |
| Force | `-Force` / `--force` | all | no | overwrite an existing tier / pre-existing files at the target path. |

## outputs

A one-line `kickoff <tier>: <name> ...` receipt, then the uniform ratmac output contract (R7) as a fenced
`contract` block. Field order is fixed: Run mode, Active proj, Active slice, Active task, Classification,
Skill chain, Files touched, Files generated, Lint result, Regen result, Open questions, Human decisions
required, Blocked items, Next safe action, Residual risk.

```contract
Run mode: single
Active proj: p-<name>
Active slice: s-<name>
Active task: t-<name>
Skill chain: ratmac-kickoff
Files touched: scheduler/p-<name>/s-<name>/grad/t-<name>/{issue,task,state,log}.md, .../s-<name>/state.md, .../s-<name>/log.md
Next safe action: fill issue.md/task.md; ratmac-checkpoint as work proceeds; ratmac-lint
```

Per-tier touched set:
- **proj** — `p-<name>/state.md`, `p-<name>/log.md` (+ `p-<name>/goal/` dir in sole|dual).
- **slice** — `s-<name>/state.md`, `s-<name>/log.md`, `s-<name>/grad/` dir, the proj `state.md` (active-slice
  pointer) and proj `log.md` (+ `scope.md` + `scope-history.md` in sole|dual).
- **task** — `grad/t-<name>/{issue,task,state,log}.md`, the slice `state.md` task-table row, slice `log.md`.

## stop rules

A STOP marker is printed BEFORE the contract; the contract still renders with the relevant field set.

- **proj without `-Mode`** → `HUMAN_DECISION_REQUIRED proj kickoff needs -Mode (maintainer|sole|dual)`,
  exit 3. Mode is a load-bearing layout switch (S11), never guessed (R12).
- **tier already exists** (proj dir, slice dir, or `grad/t-<name>` dir present) → `BLOCKED <tier> '<name>'
  already exists at <path> (use -Force)`, exit 2.
- **task with no active slice** → `BLOCKED no active slice under <proj>; kickoff a slice first`, exit 2.
- **task in maintainer mode without `-Issue`** → `BLOCKED maintainer mode requires -Issue <ticket-id> (S15)`,
  exit 2.
- root / proj unresolvable (engine `Get-RatmacRoot` / `Get-RatmacProj`) → engine throws `BLOCKED: ...`.

## composes

- **after:** `ratmac-init` (loads S1-S20 + the output contract), then `ratmac-route` (orients you and
  suggests `new-task` / `slice-transit` before you commit to a write).
- **triggers:** none. kickoff does NOT spawn a sibling skill — the emitted skill chain is just
  `ratmac-kickoff`. Run `ratmac-lint` yourself afterward as a recommended manual verify of the freshly
  scaffolded tier (S5 frontmatter, S7 prefixes, S20 fence integrity, dangling `[[t-...]]` links). It also
  does NOT call `ratmac-regen` (kickoff seeds empty `<!-- GENERATED -->` fences; the rollup is rebuilt by
  later `ratmac-checkpoint`/`ratmac-close`/`ratmac-regen` runs once tasks accrue `## affects`).
- **next:** for a fresh proj → kickoff a slice; for a fresh slice → kickoff a task; for a fresh task → fill
  `issue.md`/`task.md` then drive it with `ratmac-checkpoint`.

## refs

- `references/kickoff-protocol.md` — the step-by-step protocol the script implements: root/proj/slice
  resolution, the per-tier file set, parent-state mutations (active-slice pointer, task-table row, log
  lines), mode-conditional files, and the stop branches.
- `assets/claude-code-command.md` — paste-to-invoke command seed.
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/` — `skill-contracts.md` (ratmac-kickoff entry),
  `invariants.md`, `model.md`, `orchestration.md`, `layout.md`, `open-questions.md`; and
  `brain/buf/sparks/pdrft-brain-v3/s-scheduler/` — `invariants.md` (S1-S20), `lifecycle.md` (kickoff steps),
  `layout.md`, `file-roles.md`.
