# ratmac-auto protocol

The step-by-step state machine `ratmac-auto` runs: `INIT → CLASSIFY → EVIDENCE → ROUTE → EXECUTE → VERIFY → REPORT`, with a `STOP` exit reachable from ROUTE/EXECUTE. It is the conservative orchestrator for the ratmac-skills family — it classifies a free-text intent against the A–L branch table and **only auto-runs the two safe ops** (regen and lint). Every WRITE branch terminates in `HUMAN_DECISION_REQUIRED` naming the exact `ratmac-*` skill + argument line, because R12 forbids it from guessing a scheduler write. Derived from `scripts/auto.ps1` (+ its POSIX shadow `scripts/auto.sh`) and the `s-ratmac-skills/skill-contracts.md` + `s-ratmac-skills/orchestration.md` + `s-scheduler/lifecycle.md` spec.

## 0. invariants exercised

- **R4** — pwsh primary (`auto.ps1`) with a POSIX shadow (`auto.sh`) at verb parity.
- **R5** — auto itself writes nothing under the scheduler tree; the only bytes that may change are written by the regen it spawns, and only inside generated regions. It never touches store/, spaces/, or code.
- **R6 / R10** — the regen it triggers on branch F rewrites only `<!-- GENERATED -->` regions and is byte-idempotent on stable input.
- **R7** — every exit ends with the uniform output contract via `Write-RatmacContract` / `ratmac_contract`.
- **R9** — reads the active project `state.md` (mode) and the active task `state.md` (status) before classifying.
- **R11** — the lint it triggers in VERIFY never writes (even `-Strict`).
- **R12** — on any ambiguity it STOPS with `HUMAN_DECISION_REQUIRED`; it never guesses a write branch.
- **R18** — auto MAY spawn another skill's script (route, regen, lint) but never itself.

## 1. INIT

Echo the header (`== ratmac-auto ==`), the `-Intent` and `-Until` values, and a one-line note that the R-invariants are loaded (`R4/R5/R6/R7/R9/R10/R11/R12/R18`; the `ratmac-init` contract is in effect). `ratmac-init` is the stateless loader that auto composes on — no file is read or written in this phase.

## 2. CLASSIFY — spawn `ratmac-route` (read-only)

Spawn the sibling skill `ratmac-route/scripts/route.ps1`, forwarding `-Root` / `-Proj` / `-Ts` when supplied:

```
& pwsh -NoProfile -File <…/ratmac-route/scripts/route.ps1> [-Root …] [-Proj …] [-Ts …] 2>&1 | Out-String
```

The captured text is echoed under `-- CLASSIFY (ratmac-route) --`, then parsed back field-by-field:

| route field | parsed into | used for |
|---|---|---|
| `Active project` | `$proj` | contract + EVIDENCE proj resolution |
| `Mode` | `$mode` | the mode hard-stop (§4) |
| `Active slice` | `$slice` | `$hasSlice` flag, contract |
| `Active tasks` | `$rawTasks` → `$taskList` → `$activeTaskNames` → `$singleActive` | EVIDENCE + write-branch arg wiring |
| `Suggested next-action mode` | `$suggest` | `Open questions` in the contract |

`Active tasks` arrives as `[t-foo (active); t-bar (blocked)]`; auto strips the brackets, splits on `;`, takes the first whitespace token of each entry as the task name. `$singleActive` is set only when exactly one active task name was found (the unambiguous "continue this task" case).

**Route BLOCKED propagation.** If route's output carries a `BLOCKED ` line (or a non-empty `Blocked items:`) and no `Active project:` line could be parsed, auto prints `BLOCKED ratmac-route could not resolve the scheduler context …`, emits a contract with `Classification: BLOCKED`, `Skill chain: ratmac-route`, `Blocked items: route failed to resolve project/slice`, and **exits 2**. (Fix `-Root`/`-Proj` or repair the missing `state.md`.)

## 3. EVIDENCE — read the active task `state.md` (R9)

Only when exactly one active task is in flight (`$singleActive` set) **and** a slice resolved. Auto re-resolves via the engine and reads the task's `state.md` frontmatter:

```
$p     = Get-RatmacProj -Root $Root -Proj $Proj
$sp    = Get-RatmacActiveSlice -ProjPath $p.Path
$tdir  = Resolve-RatmacTask -SlicePath $sp -Task $singleActive   # grad/<t-name>
$tfm   = Read-RatmacFrontmatter "<tdir>/state.md"
$taskStatus = $tfm['status']
$evidence   = "task=<name> status=<status> state=<scheduler-rel path>"
```

The `$evidence` string is echoed under `-- EVIDENCE --` and later surfaced in the contract. A missing `state.md`, an unresolvable `grad/<t-name>`, or a read error are all reported as informational notes — they are **not** a stop here (the status guard in §5 handles ambiguity). When there is no single active task, auto prints `(no single active task to inspect; tasks=[…])` and `$taskStatus` stays empty.

## 4. ROUTE — hard stops first, then derive the branch

Echoed under `-- ROUTE --`. Three hard-stop guards run before any branch is chosen:

1. **STOP-MODE (exit 3).** If `$mode` is empty, `?`, or not in `maintainer|sole|dual` → `HUMAN_DECISION_REQUIRED proj mode undefined or invalid …`. Set a valid `mode:` in `p-<name>/state.md` and re-run. (Auto cannot classify safely without a mode.)
2. **STOP-SCOPE (exit 3).** If the intent matches `\b(rewrite|redesign|scrap|re-architect|overhaul)\b` → `HUMAN_DECISION_REQUIRED intent contains scope-changing words …`. A redesign is out of auto scope — a human decides direction.
3. **STOP / continue-with-no-task (exit 3, RQ14).** If the intent matches `\b(continue|resume|carry on|keep going)\b` but `$singleActive` is empty → `HUMAN_DECISION_REQUIRED intent says continue but there is no single active task to resume`. Name the task or kickoff one.

### branch derivation (intent keyword → branch)

The lower-cased intent is matched against the keyword table, first match wins. Only **F** and **G** are safe (auto-run); every other branch is a WRITE that maps to an exact `ratmac-*` command with the resolved active task wired in (falling back to `<t-name>` when there is no single active task):

| branch | intent keywords (regex) | safe? | mapped command |
|---|---|---|---|
| **F** | `regen\|rollup\|rebuild\|refresh` | **yes** | spawns `ratmac-regen` |
| **G** | `lint\|verify\|check\|audit\|drift\|dangling` | **yes** | runs `ratmac-lint` (the VERIFY op) |
| **A** | `(start\|new\|create) … project` or `new proj` | write | `ratmac-kickoff -Tier proj -Name <kebab> -Mode maintainer\|sole\|dual` |
| **B** | `(start\|new\|create) … slice` | write | `ratmac-kickoff -Tier slice -Name <kebab>` |
| **C** | `(start\|new\|create\|kickoff) … task` | write | `ratmac-kickoff -Tier task -Name <kebab> [-Issue <id>] [-Sprint <id>]` |
| **D** | `checkpoint\|pause\|snapshot\|note\|progress\|blocked` | write | `ratmac-checkpoint -Task <t> -Note "<note>" [-AddAffects <p1>,<p2>] [-Status active\|blocked]` |
| **E** | `ticket\|cr feedback\|ticket update\|requirement change` | write | `ratmac-mutate -Task <t> -Kind ticket -Reason "<short>"` |
| **F-plan** | `replan\|revise plan\|new plan` | write | `ratmac-mutate -Task <t> -Kind plan -Reason "<short>" [-Diff <task.md path>]` |
| **G-approach** | `approach\|pivot\|re-approach` | write | `ratmac-mutate -Task <t> -Kind approach -Reason "<short>"` |
| **H** | `done\|complete\|finish\|land(ed)\|ship(ped)` | write | `ratmac-close -Task <t> -Status done -Cl <id> [-Outcome <text>]` |
| **I** | `abandon\|drop\|cancel\|give up` | write | `ratmac-close -Task <t> -Status abandoned -Outcome "<reason>"` |
| **J** | `scope\|defer\|discovered` | write | `ratmac-scope -Slice <s> -Op +\|- -Ref <goal-topic> -Reason "<short>"` |
| **K** | `transit\|close slice\|end slice\|next slice` | write | `ratmac-transit -Tier slice [-NewSlice <name>] -Summary "<text\|path>"` |
| **L** | `retire\|close project\|end project` | write | `ratmac-transit -Tier proj -Summary "<text\|path>"` |

**No branch matched → STOP (exit 3).** `HUMAN_DECISION_REQUIRED intent did not map to a single branch; auto will not guess a write` — the contract carries `Open questions: route suggests: <suggest>` and tells you to pick a branch and run that skill explicitly. This is the R12 backstop.

### status-ambiguity guard

For the write branches that target the active task (`D, E, F-plan, G-approach, H, I`), if `$singleActive` is set and `$taskStatus` is present but is **not** `active` or `blocked`, auto STOPS: `HUMAN_DECISION_REQUIRED task '<name>' status is '<status>' (not active/blocked); ambiguous for branch <X>` (exit 3). Reconcile the task status before running the write skill.

## 5. EXECUTE — auto-run only F (regen); every write STOPS

Echoed under `-- EXECUTE --`. The skill chain starts at `ratmac-route`.

- **Branch F (regen, safe).** Spawn `ratmac-regen/scripts/regen.ps1` (forwarding `-Root`/`-Proj`/`-Ts`), echo its output, append `-> ratmac-regen` to the chain, and parse the `Regen result:` line back into `$regenResult` (falling back to a `regen:` line). regen only rewrites GENERATED regions (R6/R10), so it is safe to auto-run.
- **Branch G (lint, safe).** Nothing to execute here — lint is the VERIFY op and runs in §6 for *every* safe run.
- **Any WRITE branch (`default`).** Print `HUMAN_DECISION_REQUIRED write branch '<X>' — auto will not perform a scheduler write.`, then `  run this: <exact command>` and `  evidence: <task=… status=… state=…>` (when EVIDENCE collected one), then the contract with `Human decisions required: confirm + run: <command>`, `Next safe action: <command>`, `Residual risk: no scheduler files were written by auto (conservative stance)`, and **exit 3**. No regen, no lint, no chaining — the named write skill is what later auto-chains regen + lint on its own success.

## 6. VERIFY — spawn `ratmac-lint` (read-only, R11)

Reached only on the safe branches (F and G; a write branch already exited in §5). Spawn `ratmac-lint/scripts/lint.ps1` (forwarding `-Root`/`-Proj`), echo its output under `-- VERIFY (ratmac-lint) --`, append `-> ratmac-lint` to the chain, and parse `$lintResult` from the `Lint result:` line (falling back to an `N error(s)` count, else `ran (see output)`). Lint never writes — it only reports violations.

## 7. REPORT — merge into the uniform auto contract (R7)

Echoed under `-- REPORT --`. `Write-RatmacContract` emits the locked field order. A safe run fills:

```contract
Run mode: auto
Active proj: <p-name>
Active slice: <s-name>
Active task: <tasks inner, or —>
Classification: <F | G>
Skill chain: ratmac-route -> ratmac-regen -> ratmac-lint   (regen only on F)
Files touched: — (auto ran only read/verify ops)
Files generated: — (none / hash-stable)   (or "see regen output" when F rebuilt regions)
Lint result: <N error(s) | ran (see output) | not-run>
Regen result: <hash-stable | … | not-run>
Open questions: route suggested: <suggest>
Human decisions required: — (safe branch auto-completed; any write still needs explicit skill invocation)
Blocked items: —
Next safe action: <F: review regen diff; G: review lint violations; else: invoke the suggested write skill>
Residual risk: auto wrote nothing; only ratmac-regen (generated regions, R6/R10) may have changed bytes
```

`Next safe action` is branch-keyed: F → "review regen diff; run ratmac-lint again if drift remained"; G → "review lint violations; fix flagged files then re-run ratmac-lint"; otherwise → "invoke the suggested ratmac-* write skill explicitly".

## 8. stop conditions (summary)

STOP markers are always printed BEFORE the contract block, per the ratmac convention:

- `BLOCKED <reason>` → **exit 2**: route could not resolve the scheduler context (no project/slice, missing `state.md`).
- `HUMAN_DECISION_REQUIRED <reason>` → **exit 3**: STOP-MODE (invalid `mode:`); STOP-SCOPE (rewrite/redesign/scrap/re-architect/overhaul in the intent); continue-with-no-task (RQ14); no branch matched (ambiguous — R12); write-branch status ambiguity (task status not active/blocked); or any WRITE branch reached EXECUTE (the conservative stance — auto names the command but never runs it).

The orchestration-spec closed-loop states map onto these: a safe branch ends `completed-in-scope`; a route-resolution failure ends `blocked`; every write/ambiguity ends `human-decision-required`. `handoff-emitted` is produced only by `ratmac-transit` itself, which auto never runs.

## refs

- engine: `skills/ratmac-auto/scripts/auto.ps1` (+ shadow `auto.sh`) and the shared `scripts/_common.ps1` (`Get-RatmacProj`, `Get-RatmacActiveSlice`, `Resolve-RatmacTask`, `Get-RatmacMode`, `Read-RatmacFrontmatter`, `Get-RatmacRelPath`, `Write-RatmacContract`, `Get-RatmacStamp`/`Get-RatmacId`).
- siblings spawned: `skills/ratmac-route/scripts/route.ps1` (CLASSIFY), `skills/ratmac-regen/scripts/regen.ps1` (branch F), `skills/ratmac-lint/scripts/lint.ps1` (VERIFY).
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/` — `orchestration.md` (state machine + ROUTE branch table + stop/closed-loop rules), `skill-contracts.md` (ratmac-auto entry), `invariants.md` (R4/R5/R6/R7/R9/R10/R11/R12/R18), `model.md`, `layout.md`, `open-questions.md`.
- upstream data model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/` — `lifecycle.md` (the kickoff/checkpoint/mutate/close/transit steps the write branches map onto), `invariants.md` (S1–S20), `layout.md`, `file-roles.md` (`state.md` = cursor, `log.md` = stream; `grad/` vs `archive/`).
