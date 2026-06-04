# close protocol

The step-by-step protocol `scripts/close.ps1` (and its `close.sh` shadow) implements. This is the lifecycle "task done / abandoned" transition (`s-scheduler/lifecycle.md`, steps 1-10), realized over the shared `_common.ps1` engine. Every write lands under the scheduler tree only (R5); the task `state.md` is read before it is mutated (R9); regen is spawned as a sibling, never self (R18); the run ends with the uniform contract (R7).

## 0. resolve context

1. `stamp = Get-RatmacStamp -Ts` — deterministic if `-Ts` is pinned, else `Get-Date`.
2. `Get-RatmacProj -Root -Proj` → `@{ Root; Proj; Path }` (explicit root → env `RATMAC_SCHEDULER_ROOT` → cwd ancestor walk; then the active project).
3. `Get-RatmacActiveSlice -ProjPath` → the active `s-*` dir. **STOP** `BLOCKED no active slice under <proj>` (exit 2) if none.
4. `Resolve-RatmacTask -SlicePath -Task` → `grad/t-<name>` (bare name or `t-` prefix accepted). **STOP** `BLOCKED task '<ref>' not found in <slice> grad/` (exit 2) if absent.
5. Bind file handles: task `state.md`, `issue.md`, `log.md`; read proj `mode` via `Get-RatmacMode`.

## 1. done-only gates (skipped entirely when `-Force`, and for `abandoned`)

These guard a `done` close so a task cannot be sealed without a recorded deliverable and resolved criteria:

1. **Non-empty `## affects`** — `Get-RatmacAffectsList -Path <task state.md>`. If the list is empty → **STOP** `BLOCKED need affects: ... empty ## affects list (status=done). Add affects via ratmac-checkpoint, or pass -Force.` (exit 2). (lifecycle step 1: the frozen `## affects` is what the task delivered, S18.)
2. **Acceptance criteria complete** — if `issue.md` exists, count lines matching `^\s*-\s*\[\s\]` (unchecked `- [ ]` items under `## acceptance criteria`). If any remain → **STOP** `HUMAN_DECISION_REQUIRED AC incomplete: <N> unchecked '- [ ]' item(s) in <t>/issue.md. Resolve them, or pass -Force to close anyway.` (exit 3). This is the R12 ambiguity stop: the script will not decide on the operator's behalf whether incomplete criteria are acceptable.

`abandoned` closes skip both gates — an abandoned task is expected to have unfinished criteria and may have an empty affects list.

## 2. set terminal status (lifecycle step 2)

`Set-RatmacFrontmatterValue -Path <task state.md> -Key status -Value <done|abandoned> -Ts stamp`. This rewrites the `status:` line in place and bumps `time-modified` (S6).

## 3. write the outcome into `## scratch` (lifecycle step 2)

If `-Outcome` is given: locate the `## scratch` section with `Find-RatmacSection` (creating it if absent), clear its existing body, and insert the outcome text as the section body, then bump `time-modified`. This replaces the scratch body rather than appending — the outcome is the task's final word. The task `state.md` path is recorded in `Files touched`.

## 4. task log line (lifecycle step 3)

`Add-RatmacLog -LogPath <task log.md> -Verb status:<status> -Args <...> -Ts stamp` (append-only stream, S19):
- `done` → args `cl:<id>` (the `-Cl` value, or `—` if omitted).
- `abandoned` → args `reason:<text>` (the `-Outcome` value, or `—`).

## 5. slice log line (lifecycle step 4)

`Add-RatmacLog -LogPath <slice log.md> -Verb close-task -Args "<t-name> status:<status>" -Ts stamp`.

## 6. goal flip — `[sole|dual]` only (lifecycle step 5)

If `-Goal` is supplied **and** the proj `mode` is `sole` or `dual`:
1. Reduce `-Goal` to its leaf name (strip path + `.md`) → `goal/<topic>.md` under the proj.
2. If that file exists → `Set-RatmacFrontmatterValue -Key current -Value true -Ts stamp`, add it to `Files touched`, mark the flip for the receipt.
3. If it does not exist → print a non-fatal note (`goal item '<name>' not found ... skipping current flip`) and continue. In `maintainer` mode `-Goal` is silently ignored (maintainer mode has no goal/scope).

## 7. archive move (lifecycle step 9)

1. Ensure `s-<slice>/archive/` exists.
2. Compute `dest = archive/<t-name>`. If `dest` already exists → **STOP** `BLOCKED archive collision: <dest> already exists; cannot move <t-name>` (exit 2). The move never clobbers an existing archived task (R12).
3. `Move-Item grad/t-<name> -> archive/t-<name>`. After the move, the task `state.md` handle is re-pointed into `archive/` (for record-reading only, not re-read).

## 8. slice `## tasks` table row (lifecycle step 10)

Read the moved task's frontmatter (`Read-RatmacFrontmatter`) for its `issue` and `sprint` tags, then `Set-RatmacTaskRow -SliceStatePath <slice state.md> -Task <t-name> -Issue <issue> -Sprint <sprint> -Status <status> -Ts stamp`. This upserts the row `| [[t-name]] | <issue> | <sprint> | <status> |` (header rows are created if the `## tasks` section lacks them). The slice `state.md` is recorded in `Files touched`.

## 9. spawn regen (lifecycle steps 6/7/8)

Locate the sibling `ratmac-regen/scripts/regen.ps1` (`../ratmac-regen/scripts/regen.ps1` relative to this skill's `scripts/`). If present, invoke it via `& pwsh -NoProfile -File <regen.ps1>`, forwarding `-Root`, `-Proj`, and `-Ts` so the chain stamps deterministically, piping its output to `Out-Null`. Regen rebuilds the GENERATED-fenced rollups and residuals that the close changed (R6/S20 — only fenced regions are touched, R10 — byte-idempotent on stable input):
- `goal-residual.md` from `goal/<topic>.md` `current:` flags `[sole|dual]`;
- slice `scope-residual.md` `[sole|dual]`;
- slice `issues-residual.md` `[maintainer|dual]`;
- fenced `## affects` rollup in slice `state.md` (union of in-archive task `## affects`), and proj `state.md` if changed.

`Regen result` becomes `regen spawned` (or `not run` if the script is absent). Close never reruns its own logic — it only ever spawns a sibling (R18).

## 10. receipt + contract (R7)

Print `close: <t-name> status:<status> -> archived under <slice>/archive/`, an optional goal-flip note, then `Write-RatmacContract` with the field order: Run mode, Active proj, Active slice, Active task, Classification (`close-task:<status>`), Skill chain (`ratmac-close -> ratmac-regen`), Files touched (deduped), Regen result, Next safe action (`ratmac-lint to verify post-archive`). Close does NOT spawn lint — run `ratmac-lint` yourself afterward.

## invariants exercised

- **R5** — only scheduler-tree files are written (task/slice/goal under the proj).
- **R7** — uniform contract block emitted last; STOP markers print before it.
- **R9** — task `state.md` (and its `## affects` / `issue.md` AC) read before any mutation.
- **R12** — empty-affects and unchecked-AC ambiguities STOP rather than guess; archive collision refuses to clobber.
- **R18** — regen is a spawned sibling; close never re-invokes close.
- **S6/S18/S19/S20** — `time-modified` bumped on edits; `## affects` is the frozen deliverable list; logs are append-only streams; regenerated content stays inside GENERATED fences.

## refs

- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md` (ratmac-close entry).
- model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/lifecycle.md` ("task done / abandoned"), `file-roles.md`, `invariants.md`, `layout.md`.
