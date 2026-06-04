# ratmac-transit protocol

The step-by-step protocol `transit.ps1` (and its `transit.sh` shadow) implements when a slice ends
or a project retires. It is the terminal lifecycle step: freeze the tier, summarize it, flip
`status: done`, and `mv` it into the parent's `archive/`. Derived from the scheduler lifecycle
(slice transition steps 1–9, proj retirement steps 1–3) and the ratmac-transit skill contract.

It writes ONLY under the scheduler tree (R5), reads the relevant `state.md` first (R9), and every
STOP fires **before** any write or regen so an ambiguous tier never half-transits (R12).

## 0. resolve context

Both engines dot-source `_common` and resolve:

1. `$stamp = Get-RatmacStamp $Ts` — caller-pinned stamp or now (`yyyy-MM-dd-HH:mm:ss`, R17).
2. `$p = Get-RatmacProj -Root $Root -Proj $Proj` → `@{ Root; Proj; Path }` (the active proj dir).
3. the sibling skill dir for spawning: `ratmac-regen/scripts/regen.ps1` and
   `ratmac-lint/scripts/lint.ps1` resolved relative to `$PSScriptRoot` (R18 — spawn a sibling, never
   self).

Then it branches on `-Tier`.

## A. slice tier (`-Tier slice`)

### A.1 resolve the active slice

`Get-RatmacActiveSlice -ProjPath <pdir>` → the single non-archive `s-*` dir, or the one flagged
`status: active`. `$sname` is its leaf name.

- **STOP (BLOCKED, exit 2):** no active slice → `BLOCKED no active slice under <p-name>`.

### A.2 STOP gates (R12 — decided before any write)

1. **live tasks in `grad/`.** Enumerate `t-*` dirs under `<slice>/grad/`. If any remain and `-Force`
   is not set → `HUMAN_DECISION_REQUIRED active tasks present: <list>` (exit 3). Lifecycle step 1
   requires all live tasks archived or migrated to the new slice first — run `ratmac-close` per task,
   then retry, or pass `-Force` to archive over them.
2. **no successor declared.** If neither `-NewSlice` nor `-NoSuccessor` is given →
   `HUMAN_DECISION_REQUIRED no successor slice` (exit 3). The caller must say where the line goes:
   `-NewSlice <s-name>` for the successor, or `-NoSuccessor` to end the line.

Both STOPs print the marker line, then a contract block, then exit. No file has been touched yet.

### A.3 final regen (pre-freeze) — lifecycle step 2

Spawn `regen.ps1 -Root $Root -Proj <p-name> -Ts $stamp` so the slice's fenced `## affects` rollup
(union of its archived + in-flight task `## affects`, S18) is current before the dir freezes. Only
GENERATED regions are touched (R6); regen is byte-idempotent on stable input (R10).

### A.4 write `summary.md` — lifecycle step 3 (Q5 one-pager)

`<slice>/summary.md` captures the outcome: what shipped, what carried forward, key decisions.

- if `-Summary` is a path to an existing file → copy it verbatim.
- else → wrap the literal `-Summary` text in `time-created` / `time-modified` frontmatter under a
  `# summary — <s-name>` heading.

### A.5 `status: done` on the slice — lifecycle step 4

`Set-RatmacFrontmatterValue` sets `status: done` in `<slice>/state.md` and bumps `time-modified`.

### A.6 archive the slice dir — lifecycle step 6

Ensure `<pdir>/archive/` exists, then `Move-Item <slice> → <pdir>/archive/<s-name>`. The frozen
slice now lives under the proj's `archive/`.

### A.7 proj bookkeeping — lifecycle steps 5, 7, 8

1. `Add-RatmacLog <pdir>/log.md` ← `close-slice <s-name>` (lifecycle step 5).
2. if `-NewSlice` (normalize to an `s-` prefix):
   - rewrite the `active slice:` line under the proj `state.md` `## scratch` section (insert it if
     the section or line is absent), and bump `time-modified` (lifecycle step 7 — successor
     pointer). The successor slice is **NOT** auto-created; `ratmac-kickoff` is the next step.
   - `Add-RatmacLog` ← `active-slice <s-new>` (lifecycle step 8).
   - `Next safe action` = `ratmac-kickoff -Tier slice -Name <s-new>`.
   - if `-NoSuccessor` instead → no pointer write; `Next safe action` notes the line ended.

### A.8 final regen + lint (post-archive) — lifecycle step 7 (proj rollup)

Spawn `regen.ps1` again to settle the proj `## affects` rollup now that the slice moved into
`archive/`, then spawn `lint.ps1 -Root $Root` and surface its first non-empty output line as the
`Lint result`. Lint never writes (R11).

### A.9 report

Print `transit slice: <s-name> archived under <p-name>` and the `next:` line, then the contract:
`Classification: slice-transit`, `Skill chain: ratmac-transit -> ratmac-regen -> ratmac-lint`,
`Active slice: <s-name> (archived)`, `Files touched`, `Regen result`, `Lint result`,
`Next safe action`.

## B. proj tier (`-Tier proj`)

Proj retirement (shipped, killed, or merged elsewhere). Assumes the project's slices are already
archived — there are no STOP gates in this branch.

1. **final regen** — spawn `regen.ps1 -Root $Root -Proj <p-name> -Ts $stamp` to settle the proj
   `## affects` rollup (lifecycle proj step 1).
2. **write `summary.md`** at `<pdir>/summary.md` — same copy-file-verbatim vs wrap-literal logic as
   the slice tier, headed `# summary — <p-name>`.
3. **retire log + status** — `Add-RatmacLog <pdir>/log.md` ← `retired` (lifecycle proj step 2), and
   `Set-RatmacFrontmatterValue status: done` on `<pdir>/state.md`.
4. **archive the proj dir** — ensure `<scheduler-root>/archive/` exists, then
   `Move-Item <pdir> → <root>/archive/<p-name>` (lifecycle proj step 3).
5. **lint** — spawn `lint.ps1 -Root $Root`; surface the first output line as `Lint result`.
6. **report** — `transit proj: <p-name> retired → <dest>` and the contract:
   `Classification: proj-retire`, `Active proj: <p-name> (retired)`,
   `Next safe action: none — project archived`.

## invariant trace

- **R5** — every path written (`summary.md`, `state.md`, `log.md`, the `archive/` move) is under the
  scheduler `p-<name>` tree. No store/, spaces/, or code touched.
- **R6 / S20** — the `## affects` rollup is rewritten only inside its GENERATED fence, and only by the
  spawned `ratmac-regen`; transit itself writes `summary.md` (a fresh file) and frontmatter scalars.
- **R7** — both branches end with `Write-RatmacContract`, fields in the locked order.
- **R9** — slice/proj `state.md` is read (frontmatter + sections) before any frontmatter or pointer
  write.
- **R10** — the bracketing regens are byte-idempotent; re-running transit on an already-stable tree
  rebuilds 0 regions.
- **R11** — the final lint is read-only.
- **R12** — the live-task and no-successor STOPs print `HUMAN_DECISION_REQUIRED` and exit before any
  write; the missing-slice STOP prints `BLOCKED`.
- **R18** — transit spawns `ratmac-regen` and `ratmac-lint` as subprocesses; it never spawns itself.

## refs

- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md` (ratmac-transit entry).
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/invariants.md` (R5, R6, R7, R9, R10, R11,
  R12, R18).
- spec: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/lifecycle.md` (slice transition steps 1–9, proj
  retirement steps 1–3, Q5 summary one-pager).
- spec: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/invariants.md` (S13 residual, S18 affects, S19
  log stream, S20 GENERATED fence).
- engine: `scripts/_common.ps1` / `_common.sh` — `Get-RatmacProj`, `Get-RatmacActiveSlice`,
  `Set-RatmacFrontmatterValue`, `Add-RatmacLog`, `Find-RatmacSection`, `Write-RatmacContract`.
