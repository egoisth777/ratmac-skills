# ratmac-checkpoint protocol

The exact step sequence `scripts/checkpoint.ps1` (and its `checkpoint.sh` shadow) implements when you
snapshot a task pause. It is the scheduler "work checkpoint" of `s-scheduler/lifecycle.md` realized as a
single idempotent-ish write pass. Everything happens under `scheduler/` (R5); the task `state.md` is read
before it is written (R9); no GENERATED region is touched (so nothing here violates R6/S20), and the script
chains to no sibling skill (R18 — a leaf write).

## 0. resolve context (shared engine, before any write)

1. `stamp = Get-RatmacStamp $Ts` — pin the timestamp (RQ3: `-Ts` override else `Get-Date`).
2. `p = Get-RatmacProj -Root $Root -Proj $Proj` — resolve `{ Root; Proj; Path }`. May `BLOCKED:` from the
   engine if the root or active project cannot be uniquely resolved.
3. `slice = Get-RatmacActiveSlice -ProjPath $p.Path` — abs path of the single/active `s-*`, or `$null`.
   - `$null` → **STOP** `BLOCKED no active slice under <proj>` (exit 2), contract `Blocked items: no active
     slice`. (See §6.)
4. `tdir = Resolve-RatmacTask -SlicePath $slice -Task $Task` — normalizes the ref (adds `t-` if missing),
   resolves `<slice>/grad/<t-name>`. Returns `$null` if absent.
   - `$null` → **STOP** `BLOCKED task '<task>' not found in <slice> grad/ (archived tasks use ratmac-mutate or
     revive)` (exit 2). Checkpoint never reaches into `archive/` — reviving an archived task is a deliberate
     `ratmac-mutate`/direct-edit decision, not a checkpoint side effect.
5. Bind `tstate = <tdir>/state.md`, `tlog = <tdir>/log.md`. Init `touched=@()`, `generated=@()`.

## 1. rewrite the `## status` body (snapshot, not stream)

The checkpoint note is a snapshot, so it overwrites — it does not append — the task `state.md` `## status`
section. (S18/lifecycle: `state.md` is the cursor snapshot; the append-only history is `log.md`.)

1. `noteFirst = ($Note -split "\n")[0]` — only the first line of the note becomes the status body.
2. Load `tstate` into an `ArrayList`; `Find-RatmacSection -Name 'status'` to get `{Start; End}`.
3. If the section exists: delete every line strictly between the heading and the next `##` heading, then
   `Insert` `noteFirst` immediately under the heading. Write back UTF-8. (If `## status` is absent, the
   section is left untouched — the note still lands in `log.md` in §4.)

> Note: the upstream `skill-contracts.md` sketch also mentioned a `## scratch` line; the implemented script
> does NOT write `## scratch`. The status body is the single snapshot surface; the durable event line is the
> `log.md` append. Keep timestamps out of `state.md` (S19) — they belong in `log.md`.

## 2. bump `time-modified` (S6)

`Set-RatmacFrontmatterValue -Path $tstate -Key 'time-modified' -Value $stamp -Ts $stamp`. Stale stamps cause
stale agent reads (S6); every checkpoint bumps it. Record `tstate` (forward-slash normalized) in `touched`.

## 3. add to `## affects` (S18, deduped) — only with `-AddAffects`

If `-AddAffects` was supplied:

1. `Add-RatmacAffects -StatePath $tstate -Paths $AddAffects -Ts $stamp`:
   - finds (or appends) the `## affects` section,
   - collects existing `- <path>` bullets,
   - for each new path: normalizes slashes, skips empties, dedupes against existing (RQ13), inserts `- <path>`
     for the rest,
   - bumps `time-modified` again with the same stamp.
2. Build `affMsg = "affects +<Added.Count> (dup <Dup.Count>)"` for the receipt and the log arg.

`## affects` is a hand-edited bullet list (NOT frontmatter, S18). Checkpoint only *grows* it; it is frozen by
`ratmac-close` on `status: done` and rolled up (fenced, S20) into slice/proj `state.md` by `ratmac-regen` —
neither of which checkpoint performs.

## 4. conditional status ripple (active↔blocked) — only with `-Status`

If `-Status` was supplied AND differs from the current `state.md` frontmatter `status:`:

1. `Set-RatmacFrontmatterValue -Key 'status' -Value $Status` on `tstate` (bumps `time-modified`).
2. Re-read frontmatter (`tfm`) to recover the task's `issue` and `sprint` tags.
3. `Set-RatmacTaskRow -SliceStatePath <slice>/state.md -Task <t-name> -Issue $tfm.issue -Sprint $tfm.sprint
   -Status $Status` — upsert the slice `## tasks` table row `| [[t-name]] | <issue> | <sprint> | <status> |`.
   Record `<slice>/state.md` in `touched`.
4. `Add-RatmacLog -LogPath <slice>/log.md -Verb 'task-status' -Args "<t-name> status:<Status>"` (S19).
   Record `<slice>/log.md` in `touched`. Set `statusChanged = $true`.

If `-Status` matches the current value, nothing ripples — no frontmatter rewrite, no slice edits. This is the
only path that touches files outside the task dir.

## 5. append the task `log.md` line (S19)

Always, last:

1. `logArgs = noteFirst`; if `affMsg` is set, append ` | <affMsg>`.
2. `Add-RatmacLog -LogPath $tlog -Verb 'checkpoint' -Args $logArgs -Ts $stamp` — appends
   `<stamp> checkpoint <noteFirst>[ | affects +n (dup m)]`. Creates `log.md` with frontmatter if missing,
   else appends and bumps its `time-modified`. Record `tlog` in `touched`.

`log.md` is the append-only stream; `state.md` is the snapshot. They are structurally distinct artifacts (S3)
and are never conflated.

## 6. stop rules (printed BEFORE the contract)

| condition | marker | exit |
|---|---|---|
| no single/active `s-*` slice under the active proj | `BLOCKED no active slice under <proj>` | 2 |
| task ref not resolvable to `grad/t-<name>` (incl. archived tasks) | `BLOCKED task '<task>' not found in <slice> grad/ ...` | 2 |
| root / active-project unresolvable | `BLOCKED:` (raised by shared engine) | non-zero |

Checkpoint never emits `HUMAN_DECISION_REQUIRED` — it has no ambiguous write branch to guess (R12). The note
overwrites `## status`, affects only grows (deduped), and the status ripple is gated on a concrete value
change. The contract follows the marker in every stop path with the partial fields known at that point.

## 7. output contract (R7)

Emitted by `Write-RatmacContract` in the canonical field order. Checkpoint populates:

```contract
Run mode: single
Active proj: p-<name>
Active slice: s-<name>
Active task: t-<name>
Skill chain: ratmac-checkpoint
Files touched: <task state.md>, <task log.md>[, <slice state.md>, <slice log.md>]
Next safe action: continue work, or ratmac-close when AC met; ratmac-lint to verify
```

No `Files generated`, `Lint result`, or `Regen result` line — checkpoint touches no fenced/residual
generated content and triggers no sibling skill. The slice `state.md`/`log.md` entries in `Files touched`
appear only when §4 ran (a real `-Status` change).

## refs

- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md` (ratmac-checkpoint entry),
  `invariants.md` (R5 scheduler-only, R7 contract, R9 read-state-first, R12 stop-don't-guess, R18 no
  self-spawn).
- upstream model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/lifecycle.md` (the "work checkpoint" section),
  `invariants.md` (S3 four-files, S6 time-modified, S18 `## affects`, S19 `log.md`, S20 fence sentinels),
  `file-roles.md` (state.md snapshot vs log.md stream).
- engine: `scripts/_common.ps1` / `_common.sh` — `Get-RatmacStamp`, `Get-RatmacProj`,
  `Get-RatmacActiveSlice`, `Resolve-RatmacTask`, `Find-RatmacSection`, `Set-RatmacFrontmatterValue`,
  `Add-RatmacAffects`, `Set-RatmacTaskRow`, `Add-RatmacLog`, `Write-RatmacContract`.
