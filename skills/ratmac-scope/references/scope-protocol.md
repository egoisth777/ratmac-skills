# ratmac-scope protocol

The step-by-step protocol `scripts/scope.ps1` (and its `scope.sh` shadow) implements when it moves a
goal-topic ref in or out of a slice's scope. Derived from the script itself, the contract spec
(`brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md`, ratmac-scope entry) and the
scheduler lifecycle (`.../s-scheduler/lifecycle.md`, *scope mutation* section).

## what a scope mutation is

A slice's **scope** is the set of `[[goal-topic]]` wikilinks in `s-<slice>/scope.md` — the goal items
the slice has committed to deliver. Scope changes mid-slice when an item turns bigger than planned, gets
deferred, or a new item is discovered while working. The three durable artifacts are:

1. **`scope.md`** — the live ref set. The wikilinks here are what `ratmac-regen` scans to build the
   derived views, so adding/removing a `[[<topic>]]` bullet *is* the scope edit.
2. **`scope-history.md`** — an append-only ledger (S14). One line per change: `+/- <topic> <reason>
   <YYYY-MM-DD>`. Never rewritten; it is the audit trail of how scope drifted.
3. **slice `log.md`** — the event stream (S19). One line per action: `<ts> scope+ <topic>` /
   `<ts> scope- <topic>`.

The goal item `p-<proj>/goal/<topic>.md` is the SSoT for *what the topic is* (S12). `scope.md` only
references it; the topic's `current:` flag (delivered-yet?) lives on the goal item, not in scope.

## preconditions (read before write, R9)

The script resolves context with the shared engine and STOPs before any mutation (R12) if a
precondition fails — so an ambiguous scope mutation never half-applies (R5: scheduler-tree writes only).

1. **stamp / date** — `Get-RatmacStamp $Ts` (honours `-Ts` for deterministic runs); `$date` is the
   `YYYY-MM-DD` slice used in the history line.
2. **proj** — `Get-RatmacProj -Root -Proj` → `@{ Root; Proj; Path }`.
3. **mode** — `Get-RatmacMode -ProjPath`. If `maintainer` → **STOP** `BLOCKED maintainer mode has no
   scope ...` (exit 2). Scope exists only in `sole|dual`.
4. **slice** — explicit `-Slice` (with an `s-` prefix added if missing) must resolve to an existing dir,
   else **STOP** `BLOCKED slice '<s-name>' not found ...`. With no `-Slice`, `Get-RatmacActiveSlice
   -ProjPath` must return a slice, else **STOP** `BLOCKED no active slice ...`.
5. **scope.md** — `s-<slice>/scope.md` must exist, else **STOP** `BLOCKED scope.md missing in <slice>
   ...` (the slice was not kicked off under a sole|dual proj).

## ref normalization

The goal ref is normalized to a bare leaf topic: backslashes → forward slashes, take the last
path segment, strip a trailing `.md`. So `-Ref goal/foo.md`, `-Ref foo`, and `-Ref a/b/foo` all resolve
to topic `foo`, pointing at `p-<proj>/goal/foo.md`.

## branch: `-Op +` on a missing goal item (scaffold or stop)

If `-Op +` and `goal/<topic>.md` does not exist:

- **without `-CreateGoal`** → **STOP** `HUMAN_DECISION_REQUIRED goal item missing: goal/<topic>.md does
  not exist. Pass -CreateGoal to scaffold it, or create the goal item first.` (exit 3). The skill never
  guesses whether you meant to invent a new goal item (R12).
- **with `-CreateGoal`** → scaffold the goal item from `ratmac-kickoff/templates/goal-topic.md.tpl`
  via `Expand-RatmacTemplate` with `STAMP`, `NAME=<topic>`, and `PROBLEM` (= `-Reason` if given, else
  `TODO: describe goal <topic>`). The new goal item is written with `current: false` — nothing has
  delivered it yet (S12) — its path added to `Files touched`, and the run continues to the scope edit.

## branch: `-Op -` on a ref not in scope (stop)

If `-Op -` and `scope.md` does not already contain a `[[<topic>]]` ref (matched tolerantly so a
`[[path/<topic>]]` or `[[<topic>|alias]]` form still counts) → **STOP** `BLOCKED scope contract:
'<topic>' is not in <slice>/scope.md (nothing to remove)` (exit 2). Removal must be exact: you cannot
drop something that was never in scope.

## the scope.md edit

Scan `scope.md` for an existing `[[<topic>]]` ref (same tolerant match):

- **`-Op +`** — if absent, append `- [[<topic>]]` as the last non-blank body line (trailing blank lines
  are preserved below the new bullet). If already present, it is a no-op add — the receipt prints
  `note: '<topic>' already in scope (no-op add)`.
- **`-Op -`** — remove the matched ref line.

If the file content changed, write `scope.md` and bump its `time-modified` frontmatter
(`Set-RatmacFrontmatterValue`, S6); add `scope.md` to `Files touched`.

## the scope-history.md ledger line (S14, append-only)

Build `histLine = "<Op> <topic> <reason> <YYYY-MM-DD>"` (reason = `-Reason` else `—`):

- if `scope-history.md` is missing → create it with frontmatter (`time-created`/`time-modified` =
  stamp), a `# scope-history — <slice>` heading, and the first line.
- else → `Add-Content` the line and bump `time-modified`.

This file is **never** rewritten — only appended — so it is the durable record of every expand/contract.
`scope-history.md` is always added to `Files touched`.

## the slice log line (S19)

`Add-RatmacLog -LogPath <slice>/log.md -Verb "scope<Op>" -Args <topic> -Ts <stamp>` →
`<ts> scope+ <topic>` or `<ts> scope- <topic>`. Creates the log with frontmatter if absent, else
appends and bumps `time-modified`. The log path is added to `Files touched`.

## post: trigger ratmac-regen (R18)

Scope's derived views are owned by `ratmac-regen`, not this skill. After the writes, spawn
`ratmac-regen/scripts/regen.ps1` as a subprocess (R18 — a skill may spawn a sibling, never itself),
passing through `-Root`, `-Proj`, and `-Ts` when given so regen runs against the same proj with the
same stamp. Regen rebuilds (touching only `<!-- GENERATED -->` regions / residual files, R6/S20, and
byte-idempotently, R10):

- `s-<slice>/scope-residual.md` — scope refs ∩ goal `current:` flags.
- `p-<proj>/goal-residual.md` — the goal rollup by `current:` state.

`Regen result` reports `regen spawned` (or `not run` if the regen script is absent). These residuals are
this skill's *generated* outputs by proxy — it never writes them directly.

## contract + receipt

Print the one-line receipt, then `Write-RatmacContract` (R7) with: `Run mode: single`, `Active proj`,
`Active slice`, `Classification: scope-mutation:<+|->`, `Skill chain: ratmac-scope -> ratmac-regen`,
`Files touched` (unique union of the paths above), `Regen result`, and
`Next safe action: ratmac-lint to verify scope/residual consistency`.

## stop-rule summary

| condition | marker | exit |
|---|---|---|
| proj mode is `maintainer` | `BLOCKED maintainer mode has no scope ...` | 2 |
| explicit `-Slice` not found | `BLOCKED slice '<s-name>' not found ...` | 2 |
| no active slice resolvable | `BLOCKED no active slice under <proj>` | 2 |
| `scope.md` missing in slice | `BLOCKED scope.md missing in <slice> ...` | 2 |
| `-Op +`, goal item missing, no `-CreateGoal` | `HUMAN_DECISION_REQUIRED goal item missing ...` | 3 |
| `-Op -`, ref not in scope | `BLOCKED scope contract: '<topic>' is not in ...` | 2 |

Every STOP fires **before** the first write and prints its marker line before the contract block.

## composition

After `ratmac-init` + `ratmac-route`. On success, chains `ratmac-regen` (R18). `ratmac-lint` is the next
safe action to confirm scope/residual consistency (lint is read-only, R11). The `-CreateGoal` path reuses
`ratmac-kickoff`'s goal-topic template; `ratmac-close` is the complementary skill that flips a goal item's
`current: true` once a task delivers it.
