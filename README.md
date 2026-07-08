# ratmac-skills

`ratmac-skills` is a built, working family of Claude Code skills that **automate the
`scheduler/` task tracker** — the execution-state half of the brain store: the
project / slice / task triplet (`p-<proj>/s-<slice>/{grad,archive}/t-<task>/`) with its
`state.md` cursors, append-only `log.md`, scope/goal residuals, and fenced `## affects`
rollups. It is the sibling of the `arca-skills` family, which automates the `store/` +
`spaces/` knowledge model. The partition is clean and load-bearing: **arca owns `store/` +
`spaces/` (its A1 boundary); ratmac touches `scheduler/` ONLY (R5).** ratmac exists because
hand-driving the tracker kept breaking the **fenced-region boundary** (a manual edit
landing inside a `<!-- GENERATED -->` rollup, or a `time-modified` left unbumped on a
concurrent edit), and arca is forbidden from `scheduler/` by its own boundary. ratmac is
the family that owns, enforces, and self-heals the scheduler invariants.

## skills

The family has 11 skills. Load `ratmac-init` first; orient with `ratmac-route`; let
`ratmac-auto` drive the loop when you do not want to pick the write-skill by hand.

Delta (2026-07-03): a 12th skill, `ratmac-ratio`, is in DESIGN under the scheduler
issue tier (`issue/i-ratmac-ratio/`, tracked by `state.toml`). The R-invariants below —
including R3 ("11 skills, frozen set") — re-lock at ratio publish. Gen-2 skill names its
contract references (`ratmac-creavit`, `ratmac-ianitor`, `ratmac-automata`, …) are
pdrft-brain-v3 pending and not part of the committed family.

| skill | role | writes? |
|---|---|---|
| `ratmac-init` | Stateless loader — prints the locked R1-R18 invariants + the uniform output contract. Composed-on by every other ratmac skill. | no (pure reference) |
| `ratmac-route` | Read-only session boot — reads `p-<active>/state.md`, lists active slice + tasks, surfaces recent log lines, classifies the next-action mode. | no |
| `ratmac-kickoff` | Scaffolds a proj / slice / task tier with all required files per the scheduler layout, plus the parent-tier `state.md` row and `log.md` line. | yes (new tier) |
| `ratmac-checkpoint` | Snapshot pause — bumps task `state.md`, appends a `log.md` line, dedupe-adds paths to `## affects` (RQ13), optionally flips status on the slice table. | yes (state + log) |
| `ratmac-mutate` | In-place plan / approach / ticket revision (S15, S16) — rewrites `task.md` or appends a ticket block to `issue.md`, logs the replan. | yes (task/issue + log) |
| `ratmac-scope` | Sole/dual scope expand/contract — edits `scope.md`, appends `scope-history.md`, logs the op, then triggers regen. Refuses in `maintainer` mode. | yes (scope + history) |
| `ratmac-close` | Task done/abandoned — freezes `## affects`, sets `status:`, flips the goal `current:` flag, moves the dir to `archive/`, updates the slice table, triggers regen. | yes (state + mv) |
| `ratmac-transit` | Slice/proj transition — writes `summary.md`, sets `status: done`, moves the tier to the parent's `archive/`, updates the proj cursor, triggers regen + lint. | yes (summary + mv) |
| `ratmac-regen` | Rebuilds generated content — residuals (`goal-`/`scope-`/`issues-`) and the fenced `## affects` rollups in slice + proj `state.md` (R6). Byte-idempotent on stable input (R10) — doubles as a drift check. | yes (generated regions only) |
| `ratmac-lint` | Read-only audit (R11) — schema, frontmatter, fence integrity, naming, dangling `[[t-…]]` links; `-Strict` adds a layout-compliance pass. Exits non-zero on error-severity, so it can gate a commit. | no (strictly read-only) |
| `ratmac-auto` | Single entry point — runs INIT→CLASSIFY→EVIDENCE→ROUTE→EXECUTE→VERIFY→REPORT, auto-runs only safe read/regen/lint branches, STOPS with `HUMAN_DECISION_REQUIRED` before any ambiguous write. | delegates only |

## install

Skills are installed by symlinking each `ratmac-*` skill directory into `~/.claude/skills`
so edits to this repo update the live skill in place (live update / self-evolution).

```pwsh
pwsh -File install.ps1 [-Mode develop|debug] [-Force]
```

- **`-Mode develop`** (default) — per-skill **directory** symlink (whole-skill swap). Falls
  back to a junction if symlink creation is denied (R15). Best for normal use and for
  letting the family evolve itself.
- **`-Mode debug`** — per-**file** symlink (the skill dir is mirrored, each file linked).
  Best for hot single-file edits where you want the dir to be real but files to track
  source. Debug needs file-level symlinks (no junction equivalent — it fails loudly if
  symlinks are unavailable, R15).
- **`-Force`** — relink even if a target already exists (relinks stale links; refuses to
  destroy a *real* dir without `-Force`).

A skill is installed via develop OR debug, never both — switching modes requires
uninstall + install (R13). Symlink creation needs Windows developer mode or an elevated
shell on first run.

```pwsh
# remove the links (source repo untouched):
pwsh -File uninstall.ps1 [-Force]

# end-to-end smoke test on a throwaway scheduler tree (PASSES):
pwsh -File scripts/smoke-test.ps1
```

The smoke test drives the full lifecycle with pinned `-Ts` values — kickoff proj/slice/task
→ checkpoint (with `## affects` dedupe) → scope (with chained goal create) → close (goal
`current:` flip, archive move) → regen idempotence → strict lint — asserting each step and
the R10/R13 seams.

## invariants (R1-R18)

The skills exist to enforce these. Full text:
`skills/ratmac-init/references/invariants.md`.

- **R1 — canonical location.** Source of truth is `E:/packs/skills/ratmac-skills/`, symlinked into `~/.claude/skills/`. One source per machine.
- **R2 — scheduler is upstream authority.** Skills automate the `s-scheduler` data model; its S1-S20 invariants govern and `ratmac-lint` enforces them.
- **R3 — 11 skills, frozen set.** `init, route, kickoff, checkpoint, mutate, scope, close, transit, regen, lint, auto`. A 12th requires bumping this invariant + a spec revision.
- **R4 — pwsh primary, POSIX shadow.** Every script ships `<verb>.ps1` (canonical) + `<verb>.sh` (shadow at verb parity). Windows is priority; cross-platform is best-effort.
- **R5 — scheduler boundary.** Skills mutate only files under `scheduler/p-<proj>/`. No `store/`, no `spaces/`, no source code, no external systems.
- **R6 — generated vs hand-edited boundary.** Generated-content writers touch ONLY `<!-- GENERATED -->`-headed files or `<!-- GENERATED --> … <!-- /GENERATED -->` fenced regions; outside these they STOP and report (S13/S20).
- **R7 — uniform output contract.** Every skill returns the shared `contract` block defined in `ratmac-init/references/output-contract.md` — no ad-hoc formats.
- **R8 — composition declared in description.** Skills declare composes-after / composes-before in their SKILL.md description; the agent dispatches off those descriptions.
- **R9 — read before write.** Every write skill reads the relevant `state.md` first; if its `time-modified` is newer than the in-memory snapshot, STOP and report concurrent-edit risk.
- **R10 — idempotent regen.** `ratmac-regen` is byte-stable on stable input — a re-run produces identical bytes, so it doubles as a drift detector.
- **R11 — lint never writes.** `ratmac-lint` is strictly read-only; `-Strict` raises severity but never auto-fixes.
- **R12 — auto stops on ambiguity.** `ratmac-auto` stops at the first ambiguous classification with `HUMAN_DECISION_REQUIRED` and never guesses a write branch.
- **R13 — install modes are mutually exclusive.** A skill is installed via develop OR debug, never both; switching requires uninstall + install.
- **R14 — versioning by source-repo state.** No version field in SKILL.md; the source-repo git history is canonical, and symlink installs reflect HEAD.
- **R15 — symlinks preferred; junction fallback for develop only.** Debug requires file-level symlinks (no junction equivalent); fail loudly if symlinks are unavailable.
- **R16 — no shell=true / inline shell.** All scripts dispatch from `.ps1`/`.sh` files; no inline-shell invocation, mirroring the brain-ws `.scripts/` shim discipline.
- **R17 — POSIX timestamps + forward-slash paths.** `time-created`, `time-modified`, and log timestamps use ISO `YYYY-MM-DD-HH:MM:SS`; path strings normalize to forward-slash regardless of platform.
- **R18 — self-reference for chaining only.** A skill MAY spawn another skill's script as a subprocess (e.g. close → regen) but MAY NOT recursively spawn itself.

## spec

Source spec for the family: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/` — see
`skill-contracts.md`, `invariants.md`, `model.md`, `orchestration.md`, `layout.md`, and
`open-questions.md`. The upstream data model (S1-S20) it automates lives alongside in
`brain/buf/sparks/pdrft-brain-v3/s-scheduler/` (`invariants.md`, `lifecycle.md`,
`layout.md`, `file-roles.md`).
