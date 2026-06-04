---
name: ratmac-route
description: Use FIRST at the start of any scheduler session, or whenever you are unsure "where am I in scheduler land?" — trigger on "what project/slice am I in", "show active tasks", "recent scheduler log", "where should this go", "route me", or before deciding to kickoff/checkpoint/mutate/close anything. Read-only discovery that resolves the active project + mode, finds the active slice, lists the active tasks in its grad/ (with their status and blocked-by), tails the last 5 log entries, and suggests the next-action mode (continue-task | new-task | scope-mutation | slice-transit). It writes nothing and touches nothing (R5/R9-safe), so it is always safe to run. Use after $ratmac-init to orient before any write; it gates which write-skill you reach for next and does NOT call $ratmac-regen or $ratmac-lint (read-only).
---

# ratmac-route

Read-only discovery for the scheduler tree. Answers "where am I in scheduler land?" by reading the live `state.md` files (no generated index — the filesystem `p-*/s-*/grad/t-*` layout IS the index), resolving the active project/slice/task triplet, surfacing recent activity from the append-only log, and recommending which write-skill to reach for next. It never mutates state.

## when to use

- Session boot: first orientation step before any scheduler write. `ratmac-auto` invokes it first.
- "What project / slice am I in?" / "what's the active proj?" / "which mode is this proj?"
- "Show active tasks" / "what's in flight?" / "anything blocked?" — list the live tasks under the active slice's `grad/`.
- "Recent scheduler log" / "what did I just do?" — tail the last 5 events from the slice (or proj) `log.md`.
- "Where should this go?" / "route me" / "what mode should I be in?" — you want a next-action suggestion before committing to a write.
- Before choosing between `ratmac-kickoff`, `ratmac-checkpoint`, `ratmac-mutate`, `ratmac-scope`, `ratmac-close`, or `ratmac-transit` and you need the lay of the land.

## invocation

pwsh (primary, R4):
```
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-route/scripts/route.ps1 [-Root <path>] [-Proj <p-name>] [-Ts <stamp>]
```

posix (shadow, R4):
```
bash E:/packs/skills/ratmac-skills/skills/ratmac-route/scripts/route.sh [--root <path>] [--proj <p-name>] [--ts <stamp>]
```

Roots resolve in this order (both engines, via the shared `_common` engine): explicit `-Root`/`--root` (a scheduler dir holding `p-*` children, or a `p-<name>` dir directly) → env `RATMAC_SCHEDULER_ROOT` → ancestor walk of the cwd preferring an `arca/scheduler` mount, then a `scheduler` dir, then any dir already holding `p-*` children. The active project is then the `-Proj` arg, else the single `p-*` child, else the one whose `state.md` is `status: active`.

## inputs

| param | flag (pwsh / posix) | required | default | meaning |
|---|---|---|---|---|
| Root | `-Root` / `--root` | no | resolved via env / cwd walk | scheduler root holding `p-*` projects, or a `p-<name>` dir directly |
| Proj | `-Proj` / `--proj` | no | single `p-*`, else the `status: active` one | which project to orient inside |
| Ts | `-Ts` / `--ts` | no | `Get-Date` / `date` | timestamp override (accepted for engine parity; read-only run does not stamp files) |

## outputs

Human-readable discovery block, then the ratmac output contract (R7). Read-only, so `Files touched` is `— (read-only)` and `Lint result` is `not-run`.

```
Active project: <p-name>
Mode: <maintainer | sole | dual | ?>
Active slice: <s-name | —>
Active tasks: [<t-name (status[, blocked-by: t-x])>; ...]
Recent log entries:
  <up to 5 newest lines from slice/log.md, else proj/log.md>

Suggested next-action mode: <continue-task | new-task | scope-mutation | slice-transit>
```

```contract
Run mode: single
Active proj: <p-name>
Active slice: <s-name>
Active task: <active tasks, or —>
Files touched: — (read-only)
Lint result: not-run
Next safe action: pick a mode (<suggest>); invoke the matching ratmac-* skill
```

## stop rules

- No resolvable project (root unresolvable, or cannot disambiguate which `p-*` is active) → the engine throws its `BLOCKED:` message, route prints it, emits a contract with `Blocked items: no resolvable project`, and exits `2`. No discovery is attempted.
- Active project resolved but its `state.md` is missing → print `BLOCKED proj state.md missing at <path>`, emit a contract with `Blocked items: <path>`, exit `2`.
- Otherwise never stops — it is read-only and reports whatever it finds. A missing active slice yields `Active slice: —` and `new-slice`-flavored suggestions; an empty `grad/`, missing `log.md`, or malformed task `state.md` (status shows `?`) all yield empty/placeholder results, not a stop. R12 (`HUMAN_DECISION_REQUIRED`) never fires here — route only *suggests*, it never picks a write branch.

## composes

- after: `ratmac-init` (load the S1–S20 invariants + the R7 output contract), then `ratmac-route` for orientation.
- triggers: none. ratmac-route is read-only and does NOT call `ratmac-regen` or `ratmac-lint`. It only suggests the next mode; the chosen write-skill is what later triggers regen/lint:
  - `continue-task` → `ratmac-checkpoint` (and `ratmac-mutate` for plan/ticket revisions).
  - `new-task` → `ratmac-kickoff -Tier task` (run `ratmac-lint` afterward to verify).
  - `scope-mutation` → `ratmac-scope` (sole/dual; triggers `ratmac-regen` for the residuals).
  - `slice-transit` → `ratmac-transit` (calls `ratmac-regen` + `ratmac-lint`); `ratmac-close` for finishing the in-flight task first.

## refs

- `references/route-protocol.md` — the step-by-step protocol route.ps1 implements: root/proj resolution, active-slice + active-task discovery, log tail, and the `continue-task | new-task | scope-mutation | slice-transit` suggestion.
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/` — see `skill-contracts.md` (ratmac-route entry), `invariants.md` (R5/R7/R9/R12), `orchestration.md`, `layout.md`, `model.md`, `open-questions.md`.
- upstream data model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/` — `lifecycle.md` (task/slice/proj states), `file-roles.md` (state.md = cursor, log.md = stream), `layout.md`, `invariants.md` (S1–S20).
