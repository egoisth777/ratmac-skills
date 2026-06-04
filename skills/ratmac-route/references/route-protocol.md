# ratmac-route protocol

How `ratmac-route` discovers "where am I in scheduler land?" — the read-only orientation step that runs before any write. It never mutates state (R5: writes only happen under `scheduler/`, and route writes nothing at all; R9: it reads `state.md` first, but only reads). It reads the filesystem, summarizes the active triplet, and recommends the next mode. Derived from `scripts/route.ps1` and the `s-ratmac-skills/skill-contracts.md` + `s-scheduler/lifecycle.md` spec.

## 1. resolve the scheduler root + active project

Both engines (`route.ps1`, `route.sh`) resolve context via the shared `_common` engine (`Get-RatmacProj` → `Get-RatmacRoot`), in this precedence:

1. **scheduler root** — explicit `-Root` / `--root` (a dir holding `p-*` children, OR a `p-<name>` dir directly — the workspace mount may point a `p-<project>` dir straight in), else env `RATMAC_SCHEDULER_ROOT`, else an ancestor walk of the cwd that prefers an `arca/scheduler` mount, then a `scheduler` dir, then any dir already holding `p-*` children.
2. **active project** — if the resolved root is itself a `p-<name>` dir, that is the project. Otherwise: explicit `-Proj` → the single `p-*` child → the one whose `state.md` frontmatter is `status: active`.

If the root cannot be resolved, or the project cannot be disambiguated, `Get-RatmacProj` throws its `BLOCKED:` message → **STOP** (see §6).

```
$p = Get-RatmacProj -Root $Root -Proj $Proj   # @{ Root; Proj; Path }
```

## 2. read the project state.md (R9) — mode

Route reads the active project's `state.md` before reporting anything (R9: read the relevant `state.md` first). If `<p>/state.md` is missing → **STOP** `BLOCKED proj state.md missing at <path>` (§6). Otherwise it parses the frontmatter and extracts `mode` (`maintainer | sole | dual`); a missing mode renders as `?`. The mode is reported but does NOT change route's behavior — it is read-only and never branches on mode (R12 never fires here).

```
$pfm  = Read-RatmacFrontmatter "<p>/state.md"
$mode = $pfm['mode']        # maintainer | sole | dual | (null → '?')
```

## 3. resolve the active slice

`Get-RatmacActiveSlice -ProjPath <p>` returns the active slice dir or `$null`:

- the single non-`archive` `s-*` child, else
- the `s-*` whose `state.md` frontmatter is `status: active`, else
- `$null` (reported as `Active slice: —`).

A `$null` active slice is **not** a stop — it just means there is no current slice, which steers the suggestion toward `new-slice` (§5).

## 4. list active tasks + tail the log

**Active tasks** — only when a slice resolved. Route enumerates `s-<slice>/grad/t-*` directories (the `grad/` dir holds in-flight tasks; closed tasks live in `archive/` per `lifecycle.md`). For each task dir it reads `t-<name>/state.md`:

- `status` from frontmatter (`active | blocked`; `?` if `state.md` missing or unparsable),
- `blocked-by` from frontmatter (joined with `,` when present).

Each is rendered as `t-<name> (status[, blocked-by: t-x])`. A missing `grad/` or zero task dirs yields an empty list — not a stop.

**Recent log entries** — the last 5 dated lines (matching `^\d{4}-\d{2}-\d{2}`) of the slice `log.md` when a slice resolved, else the proj `log.md`. `log.md` is the append-only event stream (S19 / `file-roles.md`): kickoff, checkpoint, replan, scope+/-, close-task, etc. A missing `log.md` yields no lines.

## 5. classify intent → suggest next-action mode

Discovery ends by proposing one mode. Route only *suggests* — it does not branch or write (R12: it never auto-picks a write branch). The mapping in `route.ps1`:

| condition | suggested mode | next skill |
|---|---|---|
| no active slice | `new-slice` | `ratmac-kickoff -Tier slice -Name <kebab>` |
| slice present, zero active tasks | `new-task` | `ratmac-kickoff -Tier task -Name <kebab> [-Issue <id>] [-Sprint <id>]` |
| slice present, ≥1 active task | `continue-task \| new-task \| scope-mutation \| slice-transit` | pick per intent (below) |

When tasks are in flight, the agent (or `ratmac-auto`) chooses among the four by what the user is doing:

| mode | when it fits | next skill |
|---|---|---|
| `continue-task` | resume work on an in-flight task: log a pause, flip status, revise plan/ticket | `ratmac-checkpoint -Task <ref> -Note <text>` (plan/ticket change → `ratmac-mutate`) |
| `new-task` | a fresh unit of work inside the current slice | `ratmac-kickoff -Tier task -Name <kebab>` |
| `scope-mutation` | sole/dual: slice scope expands/contracts mid-slice | `ratmac-scope -Slice <ref> -Op +\|- -Ref <topic> -Reason <short>` (maintainer mode has no scope → that skill STOPs) |
| `slice-transit` | the slice's milestone shipped / is superseded | finish the live task with `ratmac-close`, then `ratmac-transit -Tier slice` |

## 6. stop rules

- **no resolvable project** — `Get-RatmacProj` throws (`BLOCKED: ...`); route prints the exception message, emits a contract with `Blocked items: no resolvable project`, exit `2`. No discovery.
- **proj state.md missing** — `BLOCKED proj state.md missing at <path>`; contract `Blocked items: <path>`, exit `2`.
- **no other stops.** Route is read-only: a `$null` active slice, an empty `grad/`, a missing `log.md`, or a malformed task `state.md` (status `?`) are all reported as normal results. `HUMAN_DECISION_REQUIRED` (R12) never fires — route suggests, never decides a write.

STOP markers are printed BEFORE the contract block (`BLOCKED <reason>` → exit 2), per the ratmac convention.

## 7. output contract (R7)

Read-only, so the contract reflects no mutation. `Write-RatmacContract` emits the locked field order; route fills only the relevant fields:

```contract
Run mode: single
Active proj: <p-name>
Active slice: <s-name>
Active task: <active tasks joined by '; ', or —>
Files touched: — (read-only)
Lint result: not-run
Next safe action: pick a mode (<suggest>); invoke the matching ratmac-* skill
```

`Lint result: not-run` and the absence of `Files generated` / `Regen result` are intentional — ratmac-route does NOT trigger `ratmac-regen` or `ratmac-lint`. Those are triggered later by whichever write-skill the suggested mode points at (kickoff → lint; scope/close/transit → regen + lint).

## refs

- engine: `skills/ratmac-route/scripts/route.ps1` + the shared `skills/ratmac-kickoff/scripts/_common.ps1` (`Get-RatmacProj`, `Get-RatmacActiveSlice`, `Read-RatmacFrontmatter`, `Write-RatmacContract`).
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md` (ratmac-route entry), `invariants.md` (R5/R7/R9/R12).
- upstream data model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/lifecycle.md` (task/slice/proj states; kickoff → checkpoint → close → transit), `file-roles.md` (`state.md` = cursor, `log.md` = stream; `grad/` vs `archive/`).
