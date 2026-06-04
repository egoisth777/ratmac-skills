---
name: ratmac-auto
description: >-
  Use as the single entry point when you want the ratmac scheduler skills to drive themselves — trigger phrases:
  "ratmac auto", "drive the scheduler for me", "auto-route this scheduler intent", "orchestrate the task ops",
  "what should I do with this task/slice", "run the ratmac pipeline end to end". Runs the orchestration loop
  INIT->CLASSIFY->EVIDENCE->ROUTE->EXECUTE->VERIFY->REPORT, classifies your free-text intent against the ROUTE
  branch table (A–L), and only AUTO-RUNS the two safe ops — regen (F) and lint (G); every WRITE branch
  (kickoff/checkpoint/mutate/scope/close/transit) STOPS with HUMAN_DECISION_REQUIRED naming the exact ratmac-* skill
  and argument line, because R12 forbids it from guessing a scheduler write. Use after $ratmac-init and $ratmac-route;
  it spawns $ratmac-route (CLASSIFY), $ratmac-regen (branch F), and $ratmac-lint (VERIFY), and for any write it hands
  you the explicit skill to invoke ($ratmac-kickoff / $ratmac-checkpoint / $ratmac-mutate / $ratmac-scope / $ratmac-close / $ratmac-transit).
---

# ratmac-auto

Orchestrator for the ratmac-skills family — the scheduler-automation twin of `arca-auto`. It is the one skill you invoke
when you don't want to pick a scheduler skill yourself: it classifies the situation against the route table and dispatches.
Critically, it **never guesses which scheduler file to write** (R12). The autonomous surface is bounded to the two safe,
non-destructive ops — `ratmac-regen` (rebuild GENERATED regions, R6/R10) and `ratmac-lint` (read-only audit, R11). Every
WRITE branch terminates in `HUMAN_DECISION_REQUIRED` with the exact downstream skill + argument line for you to confirm.

## when to use

- "ratmac auto" / "drive the scheduler for me" / "run the ratmac pipeline".
- You hand over a free-text `-Intent` and want the loop to classify + dispatch the safe branches.
- Pre-checkpoint / pre-handoff hygiene: "regen the rollups", "lint the scheduler", "check for drift / dangling links".
- You're unsure whether the next step is a kickoff, checkpoint, mutate, scope, close, or transit — let auto classify and
  tell you. It STOPS and names the explicit write skill (with args wired to the resolved active task) when a write is needed.
- NOT for: a scheduler write you already know you want — invoke that skill directly ($ratmac-kickoff / $ratmac-checkpoint /
  $ratmac-mutate / $ratmac-scope / $ratmac-close / $ratmac-transit). NOT for scope-changing redesigns (it escalates those).

## invocation

pwsh (primary, R4):

```
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-auto/scripts/auto.ps1 `
  -Intent "regen the rollups then lint the scheduler" `
  -Until user-intervention `
  [-Root <scheduler>] [-Proj <p-name>] [-Ts <stamp>]
```

posix (shadow, verb parity):

```
bash E:/packs/skills/ratmac-skills/skills/ratmac-auto/scripts/auto.sh \
  --intent "checkpoint progress on the active task" \
  --until user-intervention \
  [--root <scheduler>] [--proj <p-name>] [--ts <stamp>]
```

Scheduler root resolves (both engines) in this order: explicit `-Root`/`--root` → env `RATMAC_SCHEDULER_ROOT` → cwd ancestor
walk for an `arca/scheduler` mount, a `scheduler` dir, or any dir already holding `p-<name>` children. A `-Root` pointing
straight at a `p-<name>` dir is treated as the active project.

## inputs

| param | flag (pwsh / posix) | required | default | meaning |
|---|---|---|---|---|
| Intent | `-Intent` / `--intent` | no | empty | free-text intent; keyword-classified into a ROUTE branch (A–L, F/G safe, STOP-MODE/STOP-SCOPE/STOP) |
| Until | `-Until` / `--until` | no | `user-intervention` | loop terminator (ValidateSet): `next-checkpoint` \| `task-close` \| `slice-transit` \| `user-intervention` |
| Root | `-Root` / `--root` | no | resolved | scheduler root holding `p-<name>` (else env `RATMAC_SCHEDULER_ROOT` / cwd ancestor walk) |
| Proj | `-Proj` / `--proj` | no | resolved | active project `p-<name>`; disambiguates when more than one project exists |
| Ts | `-Ts` / `--ts` | no | now | timestamp override (`Get-RatmacStamp`/`Get-RatmacId`), forwarded to delegated skills for deterministic runs |

Intent classification keywords (from `auto.ps1`): `regen|rollup|rebuild|refresh` → F (safe); `lint|verify|check|audit|drift|dangling`
→ G (safe); `start/new/create … project` → A; `… slice` → B; `start/new/create/kickoff … task` → C;
`checkpoint|pause|snapshot|note|progress|blocked` → D; `ticket|cr feedback|requirement change` → E;
`replan|revise plan|new plan` → F-plan; `approach|pivot|re-approach` → G-approach; `done|complete|finish|land|ship` → H;
`abandon|drop|cancel|give up` → I; `scope|defer|discovered` → J; `transit|close slice|next slice` → K;
`retire|close project|end project` → L. `rewrite|redesign|scrap|re-architect|overhaul` → STOP-SCOPE; anything else → STOP.

## outputs

Always runs `ratmac-route` first (CLASSIFY) and echoes each phase header (`-- CLASSIFY --`, `-- EVIDENCE --`, `-- ROUTE --`,
`-- EXECUTE --`, `-- VERIFY --`, `-- REPORT --`). Branch F runs `ratmac-regen` and reports its result; branch G (and the tail
of every safe run) runs `ratmac-lint` for VERIFY. Every run ends with the uniform ratmac output contract via
`Write-RatmacContract` / `ratmac_contract` (R7). A safe run looks like:

```contract
Run mode: auto
Active proj: p-lotus
Active slice: s-vert
Active task: t-foo (active)
Classification: F
Skill chain: ratmac-route -> ratmac-regen -> ratmac-lint
Files touched: — (auto ran only read/verify ops)
Files generated: — (none / hash-stable)
Lint result: 0 error(s)
Regen result: hash-stable
Open questions: route suggested: continue-task | new-task | scope-mutation | slice-transit
Human decisions required: — (safe branch auto-completed; any write still needs explicit skill invocation)
Blocked items: —
Next safe action: review regen diff; run ratmac-lint again if drift remained
Residual risk: auto wrote nothing; only ratmac-regen (generated regions, R6/R10) may have changed bytes
```

A write branch prints `HUMAN_DECISION_REQUIRED write branch '<X>' …` plus a `run this: <exact ratmac-* command>` line and the
task evidence, then the contract with `Next safe action` = that command, and exits 3 — no scheduler file is written.

## stop rules

ratmac-auto emits a terminal line **before** the contract, then exits without writing, when:

- **BLOCKED (exit 2)** — `ratmac-route` could not resolve the scheduler context (no project/slice, missing `state.md`). Prints
  `BLOCKED ratmac-route could not resolve the scheduler context`; fix `-Root`/`-Proj` or repair the missing `state.md`.
- **STOP-MODE (exit 3)** — proj `mode:` is undefined or not in `maintainer|sole|dual`. Cannot classify safely; set a valid
  `mode:` in `p-<name>/state.md` frontmatter and re-run.
- **STOP-SCOPE (exit 3)** — intent contains scope-changing words (`rewrite|redesign|scrap|re-architect|overhaul`). A redesign
  is out of auto scope — decide direction by hand.
- **STOP (exit 3)** — intent says continue but there is no single active task to resume (RQ14); intent maps to no branch
  (ambiguous — auto will not guess a write, R12); or a write branch targets a task whose `status:` is neither `active` nor
  `blocked` (ambiguous for D/E/F-plan/G-approach/H/I).
- **WRITE branch (exit 3)** — any of A,B,C,D,E,F-plan,G-approach,H,I,J,K,L. Prints `HUMAN_DECISION_REQUIRED write branch …`
  and the exact `ratmac-*` command line; no scheduler write is performed (conservative stance).

Only the read (route), regen (F), and lint (G/VERIFY) branches auto-run. All scheduler writes are NEVER autonomous (R5/R12).

## composes

- **after:** `ratmac-init` (stateless loader of the R-invariants + output-contract template), `ratmac-route` (the CLASSIFY
  step is a literal `ratmac-route` spawn whose `Active project / Mode / Active slice / Active tasks / Suggested next-action mode`
  fields are parsed back).
- **triggers:** `ratmac-regen` (branch F — rebuilds GENERATED residuals/rollups, R6/R10) and `ratmac-lint` (VERIFY, R11, never
  writes). On a write branch it does NOT chain; it hands off the named write skill (`ratmac-kickoff` / `ratmac-checkpoint` /
  `ratmac-mutate` / `ratmac-scope` / `ratmac-close` / `ratmac-transit`), which on success chain regen/lint as each
  declares: transit chains `ratmac-regen` + `ratmac-lint`; close and scope chain `ratmac-regen`; kickoff, checkpoint, and
  mutate chain neither (run `ratmac-lint` yourself afterward). Per R18, auto may spawn another skill's script but never itself.

## refs

- `references/auto-protocol.md` — the INIT→CLASSIFY→EVIDENCE→ROUTE→EXECUTE→VERIFY→REPORT state machine, the full A–L branch
  table, the keyword map, the stop conditions, and the safe-vs-write split exactly as `scripts/auto.ps1` implements them.
- `assets/claude-code-command.md` — paste-to-invoke command seed.
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/` — `orchestration.md` (state machine + ROUTE branch table + stop
  conditions), `skill-contracts.md` (ratmac-auto entry), `invariants.md` (R4/R5/R6/R7/R9/R10/R11/R12/R18), `model.md`, `layout.md`.
- upstream data model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/` — `lifecycle.md` (kickoff/checkpoint/mutate/close/transit
  steps the write branches map onto), `invariants.md`, `layout.md`, `file-roles.md`.
