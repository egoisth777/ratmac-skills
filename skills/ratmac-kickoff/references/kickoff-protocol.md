# kickoff protocol

The step-by-step procedure `scripts/kickoff.ps1` (and its `.sh` shadow) implements. Derived from the script
itself, the ratmac contract spec (`s-ratmac-skills/skill-contracts.md` → ratmac-kickoff), and the upstream
scheduler model (`s-scheduler/lifecycle.md` → "kickoff", `invariants.md` → S1-S20).

Binding invariants: R5 (write only under `scheduler/`), R7 (end with the uniform contract via
`Write-RatmacContract`), R9 (read parent `state.md` before writing), R12 (STOP on ambiguity, never guess a
write branch), S2 (three tiers, no extra levels), S3 (four files per task), S5/S6 (mandatory frontmatter,
bump `time-modified`), S7 (stable `p-`/`s-`/`t-` prefixes), S11 (mode at proj level), S12/S14 (goal SSoT +
scope refs in sole|dual), S15 (one task per issue; issue tag required in maintainer mode), S17 (sprint
tag), S18 (`## affects` hand-edited list), S19 (`log.md` append-only stream), S20 (`<!-- GENERATED -->`
fences).

## 0. preamble (every tier)

1. Header: `[CmdletBinding()] param(...)`, then `. "$PSScriptRoot/_common.ps1"` to load the shared engine.
2. `$stamp = Get-RatmacStamp $Ts` — caller may pin a deterministic stamp via `-Ts`; else `Get-Date`
   (RQ3). The same stamp threads through every file written this run.
3. `$tplDir = Get-RatmacTemplateDir` — `../templates` relative to `scripts/`.
4. Helpers used throughout:
   - `Tpl(name, vars)` = `Expand-RatmacTemplate` on `templates/<name>` with `{{KEY}}` → value substitution.
   - `Emit(path, content)` — refuses to overwrite an existing file unless `-Force` (returns `$false`,
     no-op); else `New-RatmacParentDir`, normalizes CRLF→LF + strips the trailing newline, and writes via
     `Set-RatmacFileLines` (canonical LF / UTF-8-no-BOM; NOT `Set-Content`, which emits CRLF on Windows and
     would diverge byte-for-byte from `kickoff.sh`, R4/R10), then records the path (slash-normalized) in
     `$touched`.
5. Branch on `-Tier` ∈ `{proj, slice, task}`.

## 1. proj tier

1. **STOP — mode required (R12, S11).** If `-Mode` is absent: print
   `HUMAN_DECISION_REQUIRED proj kickoff needs -Mode (maintainer|sole|dual)`, emit a contract with
   `Human decisions required: pick -Mode`, `exit 3`. Mode is never inferred — it selects the mandatory file
   set, so guessing it would silently mis-scaffold.
2. Resolve scheduler root: `$sched = Get-RatmacRoot -Root $Root` (explicit → env `RATMAC_SCHEDULER_ROOT` →
   cwd ancestor walk).
3. Normalize name: prefix `p-` if not already present (S7). `$pdir = <sched>/p-<name>`.
4. **STOP — already exists.** If `$pdir` exists and not `-Force`: print
   `BLOCKED project '<name>' already exists at <pdir> (use -Force)`, emit contract with `Blocked items`,
   `exit 2` (S8 — never delete; archive is the only removal path).
5. `$roleText` = `-Role` if given, else `TODO: describe <name> direction`.
6. Write `p-<name>/state.md` from `proj-state.md.tpl` — frontmatter `time-created`/`time-modified`/
   `mode: <Mode>`/`status: active` (S5, S11); body `## status` (role), an empty `<!-- GENERATED --> …
   <!-- /GENERATED -->` `## affects` fence (S20), and `## scratch` carrying `active slice: —`.
7. Write `p-<name>/log.md` from `proj-log.md.tpl` (S19 stream; first line is the create stamp).
8. **[sole|dual] (S12).** If `$Mode ∈ {sole, dual}`: `mkdir p-<name>/goal/` — the deliverables SSoT. (No
   goal dir in maintainer mode.)
9. Print `kickoff proj: <name> (mode <Mode>)` and the contract: `Run mode: single`, `Active proj`,
   `Files touched`, `Skill chain: ratmac-kickoff`, `Next safe action: ratmac-kickoff -Tier
   slice ...; then ratmac-lint`.

## 2. slice tier

1. Resolve proj: `$p = Get-RatmacProj -Root $Root -Proj $Proj` → `@{Root;Proj;Path}` (handles both the
   mount-points-at-`p-<name>` shape and the multi-proj-under-root shape; picks single proj, else `-Proj`,
   else the status:active proj, else throws `BLOCKED`).
2. Normalize name: prefix `s-` if absent (S7). `$sdir = <pdir>/s-<name>`.
3. **STOP — already exists.** If `$sdir` exists and not `-Force`: print
   `BLOCKED slice '<name>' already exists at <sdir> (use -Force)`, emit contract (`Active proj`,
   `Blocked items`), `exit 2`.
4. Read proj mode: `$mode = Get-RatmacMode -ProjPath $pdir` (reads `p-<name>/state.md` frontmatter `mode:`,
   honoring R9 — parent state read before any write).
5. Write `s-<name>/state.md` from `slice-state.md.tpl` — frontmatter + `## status`, an empty `## affects`
   GENERATED fence (S20), a `## tasks` table header (`| task | issue | sprint | status |`), and `## scratch`.
6. Write `s-<name>/log.md` from `slice-log.md.tpl` (S19).
7. `mkdir s-<name>/grad/` — the live-task container (tasks live at `grad/t-<name>/`, S2).
8. **[sole|dual] (S12, S14).** If `$mode ∈ {sole, dual}`: write `scope.md` (refs-into-goal, refs only) and
   `scope-history.md` (append-only change log) from their templates.
9. **Repoint the proj active-slice pointer (R9 read-then-write).** Read `p-<name>/state.md`; locate the
   `## scratch` section via `Find-RatmacSection` — if it is absent, append one so the pointer is ALWAYS
   set (both engines, R4); if an `active slice:` line exists rewrite it to `active slice: s-<name>`, else
   insert that line at the top of `## scratch`; write via the canonical LF helper (`Set-RatmacFileLines`,
   NOT `Set-Content`); then `Set-RatmacFrontmatterValue time-modified <stamp>` (S6 bump). Record the proj
   `state.md` in `$touched`.
10. `Add-RatmacLog p-<name>/log.md -Verb active-slice -Args s-<name> -Ts $stamp` (S19); record proj log in
    `$touched`.
11. Print `kickoff slice: s-<name> under <proj>` and the contract (`Active proj`, `Active slice`,
    deduped `Files touched`, `Skill chain: ratmac-kickoff`, `Next safe action:
    ratmac-kickoff -Tier task ...; then ratmac-lint`).

## 3. task tier

1. Resolve proj: `$p = Get-RatmacProj -Root $Root -Proj $Proj`.
2. **STOP — no active slice.** `$slice = Get-RatmacActiveSlice -ProjPath $pdir` (single non-archive `s-*`,
   else the status:active one, else `$null`). If `$null`: print
   `BLOCKED no active slice under <proj>; kickoff a slice first`, emit contract (`Active proj`,
   `Blocked items: no active slice`), `exit 2`.
3. `$sname = Split-Path $slice -Leaf`; `$mode = Get-RatmacMode -ProjPath $pdir`.
4. **STOP — maintainer mode needs an issue (S15).** If `$mode -eq 'maintainer'` and `-Issue` absent: print
   `BLOCKED maintainer mode requires -Issue <ticket-id> (S15)`, emit contract (`Active proj`,
   `Active slice`, `Blocked items: missing -Issue`), `exit 2`. One active task per `issue:` tag — the tag
   is mandatory here so the one-task-per-issue rule is enforceable.
5. Normalize name: prefix `t-` if absent (S7). `$tdir = <slice>/grad/t-<name>`.
6. **STOP — already exists.** If `$tdir` exists and not `-Force`: print
   `BLOCKED task '<name>' already exists at <tdir> (use -Force)`, emit contract, `exit 2`. (Never spawn a
   parallel `t-<name>-rework/` for a CR — that is `ratmac-mutate`'s job, S15/S16.)
7. `$problem` = `-Problem` if given, else `TODO: state the problem`.
8. Write the **four-file task set (S3)** under `grad/t-<name>/`:
   - `issue.md` from `task-issue.md.tpl` — problem statement, `## ticket updates`, `## acceptance criteria`.
   - `task.md` from `task-task.md.tpl` — `## plan`, `## exit criteria`, `## code refs` (the plan; S4 — not
     the cursor).
   - `state.md` from `task-state.md.tpl` — frontmatter `status: active`, `sprint: <Sprint>`,
     `issue: <Issue>`, `blocked-by: [<BlockedBy>]` (S5, S15, S17); body `## status` (`kicked off`), an empty
     hand-edited `## affects` list (S18 — NOT fenced, NOT frontmatter), `## scratch`.
   - `log.md` from `task-log.md.tpl` — first stream line (S19).
9. **Slice task-table row + slice log (R9 read-then-write).**
   `Set-RatmacTaskRow -SliceStatePath <slice>/state.md -Task t-<name> -Issue <Issue> -Sprint <Sprint>
   -Status active -Ts $stamp` — upserts the row `| [[t-name]] | <issue> | <sprint> | active |` into the
   `## tasks` table (creating header rows if missing), then bumps the slice `state.md` `time-modified` (S6).
   Record the slice `state.md` in `$touched`.
10. `Add-RatmacLog <slice>/log.md -Verb kickoff-task -Args t-<name> -Ts $stamp` (S19); record the slice
    `log.md` in `$touched`.
11. Print `kickoff task: t-<name> under <sname>` and the contract (`Active proj`, `Active slice`,
    `Active task`, deduped `Files touched`, `Skill chain: ratmac-kickoff`, `Next safe
    action: fill issue.md/task.md; ratmac-checkpoint as work proceeds; ratmac-lint`).

## generated-content discipline (R6 / S20)

Kickoff seeds the slice/proj `## affects` rollup as an **empty** `<!-- GENERATED --> … <!-- /GENERATED -->`
fence. It does not populate it — that region is owned by the regen path and rebuilt from in-archive task
`## affects` sections by `ratmac-checkpoint` / `ratmac-close` / `ratmac-regen` once tasks accrue work.
Kickoff never writes inside another file's GENERATED fence. The task `## affects` (S18) is a hand-edited,
un-fenced list and starts empty.

## composition (R18)

After a successful scaffold the emitted `Skill chain` is just `ratmac-kickoff` — kickoff does NOT spawn a
sibling skill. Run `ratmac-lint` yourself afterward as a recommended manual verify of the new tier (S5
frontmatter, S7 prefixes, S20 fence integrity, dangling `[[t-...]]` links):

```
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-lint/scripts/lint.ps1 -Root <root>
```

Regen is also NOT chained from kickoff: a freshly scaffolded tier has nothing to roll up, and regen is
byte-idempotent (R10) so running it on empty fences would be a no-op. (Per R18 a skill MAY spawn a
sibling's script but never itself; kickoff currently spawns neither.)

## stop-rule summary

| branch | marker | exit | trigger |
|---|---|---|---|
| proj | `HUMAN_DECISION_REQUIRED proj kickoff needs -Mode (...)` | 3 | `-Mode` absent (S11, R12) |
| proj/slice/task | `BLOCKED <tier> '<name>' already exists at <path> (use -Force)` | 2 | target dir present, no `-Force` (S8) |
| task | `BLOCKED no active slice under <proj>; kickoff a slice first` | 2 | no resolvable active slice |
| task | `BLOCKED maintainer mode requires -Issue <ticket-id> (S15)` | 2 | maintainer mode + no `-Issue` |
| any | `BLOCKED: ...` (engine) | throw | root / proj unresolvable (`Get-RatmacRoot` / `Get-RatmacProj`) |

Every branch — STOP or success — prints exactly one `Write-RatmacContract` block last (R7).

## refs

- script: `scripts/kickoff.ps1`, engine `scripts/_common.ps1` (+ `.sh` shadows, R4).
- templates: `templates/{proj-state,proj-log,slice-state,slice-log,task-issue,task-task,task-state,task-log,
  scope,scope-history,goal-topic}.md.tpl`.
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md` (ratmac-kickoff),
  `brain/buf/sparks/pdrft-brain-v3/s-scheduler/{lifecycle,invariants,layout,file-roles}.md`.
