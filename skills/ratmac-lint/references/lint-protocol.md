# ratmac-lint protocol

How `ratmac-lint` audits a scheduler `p-<name>` project tree without changing it. It is strictly
read-only (R11: lint NEVER writes, even with `-Strict`) and reports a violations table. R9 still
applies — it reads `state.md` first — but only reads. Derived from `scripts/lint.ps1` and the
`s-ratmac-skills/skill-contracts.md` + `s-scheduler/lifecycle.md` spec.

## 0. collector, not mutator

The script accumulates every defect into one `$violations` list via a local `V $sev $rule $path
$msg $fix` helper (paths are slash-normalized). Nothing is emitted mid-walk; the table and contract
print once at the end. `-Rules S5,S20` scopes the run — a `$want` predicate gates each rule so only
the named subset fires (`S5,S7,S13,S15,S18,S20,dangling,layout`); no `-Rules` means all rules.

## 1. resolve the proj tree + mode (read-only)

Context resolves via the shared `_common` engine in this precedence:

1. **scheduler root** — explicit `-Root` (a dir holding `p-*` children, OR a `p-<name>` dir directly
   — the workspace mount may point a `p-<project>` dir straight in), else env
   `RATMAC_SCHEDULER_ROOT`, else an ancestor walk of the cwd preferring an `arca/scheduler` mount,
   then a `scheduler` dir, then any dir already holding `p-*` children.
2. **active project** — if the resolved root is itself a `p-<name>` dir, that is the project.
   Otherwise: explicit `-Proj` → the single `p-*` child → the one whose `state.md` is `status: active`.

```
$p    = Get-RatmacProj -Root $Root -Proj $Proj   # @{ Root; Proj; Path }
$pdir = $p.Path
$mode = Get-RatmacMode -ProjPath $pdir            # maintainer | sole | dual | (null)
```

If `Get-RatmacProj` throws (root unresolvable or proj ambiguous), the script prints `BLOCKED
<message>` BEFORE the contract, emits a contract with `Files touched: — (read-only, R11)` and
`Blocked items: no resolvable project`, and exits `2`. This is the **only** hard halt (see §8).

The mode drives which `-Strict` required-files apply and whether the S15 issue-tag check runs:
`$soleDual = mode ∈ {sole,dual}`; `$maintDual = mode ∈ {maintainer,dual}`.

## 2. shared audit helpers

These are collector-only (they call `V`, emit nothing to stdout). Each is skipped when its file is
absent (`Test-Path` guard), so a missing optional file does not crash the walk.

- **`Audit-Frontmatter $path` (S5)** — for an existing `.md`, read frontmatter via
  `Read-RatmacFrontmatter` and require both `time-created` and `time-modified` to be present and
  non-blank. Each missing key → `error S5 "missing <key> frontmatter"`.
- **`Audit-Fence $path` (S20)** — scan lines; a `<!-- /GENERATED -->` increments closes and
  decrements depth (depth < 0 ⇒ close-before-open ⇒ `$bad`), a `<!-- GENERATED` (any tail)
  increments opens and depth. If opens ≠ closes OR `$bad` → `error S20 "unbalanced GENERATED fence
  (<n> open / <m> close)"`, fix-hint: restore the matched pair, rerun `ratmac-regen`.
- **`Audit-DanglingTaskLinks $path $slicePath` (dangling)** — regex every `[[t-...]]` in the raw
  file; the target task must live in `<slice>/grad/<t-…>` or `<slice>/archive/<t-…>`. Neither →
  `warn dangling "dangling link [[t-…]] — task in neither grad/ nor archive/"`. Skipped when no
  slice context.
- **`Audit-Required $path $reason` (layout, -Strict only)** — when `-Strict` and the `layout` rule
  is in scope, a missing required file → `error layout "required file missing (<reason>)"`. A no-op
  unless `-Strict`.
- **`Audit-Residual $path` (S13)** — frontmatter audit, then require line 1 to match
  `^<!-- GENERATED`. Missing sentinel → `warn S13 'residual missing "<!-- GENERATED" sentinel on
  line 1'` (residuals are whole-file generated, S13/S20-residual; rerun `ratmac-regen`).

## 3. proj tier

On `<p>/state.md`:

- if present: `Audit-Frontmatter` (S5), then require `status` (`active|done|abandoned`) and `mode`
  (`maintainer|sole|dual`) non-blank in frontmatter — each missing → `error S5`. Then `Audit-Fence`.
- if absent: `error S5 "proj state.md missing"`, fix-hint scaffold via `ratmac-kickoff -Tier proj`.

**S7 prefix** — the proj dir leaf must match `p-*`; otherwise `error S7 "proj dir '<name>' lacks p-
prefix"` (renaming breaks `[[…]]` links — fix manually).

**-Strict required files** (mode-conditional, `layout.md`):
- always: `<p>/log.md`.
- sole|dual: `<p>/goal` dir and `<p>/goal-residual.md`.

**proj residuals (S13)** — every `<p>/*-residual.md` runs `Audit-Residual` (frontmatter + line-1
sentinel).

## 4. slice tier

Enumerate `<p>/s-*` directories excluding the literal `archive` dir. For each slice `<s>`:

- **S7** — assert the leaf matches `s-*` (defensive; the filter already restricts to `s-*`).
- **`<s>/state.md`** — if present: `Audit-Frontmatter` (S5); require `status` non-blank (S5);
  `Audit-Fence` (S20); `Audit-DanglingTaskLinks` against `<s>`. If absent: `error S5 "slice
  state.md missing"`.
- **-Strict required files**: always `<s>/state.md` and `<s>/log.md`; sole|dual add `scope.md`,
  `scope-history.md`, `scope-residual.md`; maintainer|dual add `issues-residual.md`.
- **slice residuals (S13)** — every `<s>/*-residual.md` → `Audit-Residual`.
- **slice log** — `Audit-Frontmatter <s>/log.md` (S5).

## 5. task tier (grad/ + archive/)

For each of the two buckets `grad` and `archive` under the slice (skipped if the bucket dir is
absent), enumerate task dirs. For each task `<t>`:

- **S7** — assert the leaf matches `t-*`; else `error S7 "task dir '<name>' lacks t- prefix"`.
- **S5 frontmatter** — `Audit-Frontmatter` on each of `issue.md`, `task.md`, `state.md`, `log.md`.
- **`<t>/state.md`** — if present, read frontmatter and:
  - require `status` (`active|blocked|done|abandoned`) non-blank → else `error S5`.
  - **S15/S16** — only when `$maintDual && mode == 'maintainer'`: require a non-blank `issue:` tag
    → else `error S15 "maintainer-mode task missing issue: tag"` (one active task per issue).
  - **S18** — if `status == 'done'`: the file must carry a `## affects` section
    (`Find-RatmacSection`) → else `warn S18 'done task lacks "## affects" section'` (frozen on done).
  - `Audit-Fence` (S20) and `Audit-DanglingTaskLinks` against `<s>`.
  - if `state.md` absent: `error S5 "task state.md missing"`.
- **dangling links in static files** — `Audit-DanglingTaskLinks` on `<t>/issue.md` and
  `<t>/task.md` too (links may reference sibling tasks from the problem/plan text).

## 6. rule → severity → invariant map

| rule | what it checks | severity | invariant |
|---|---|---|---|
| **S5** | `time-created` + `time-modified` on every `.md`; `status` on proj/slice/task `state.md`; `mode` on proj `state.md`; the file exists | error | frontmatter mandatory |
| **S7** | dir-name prefixes: proj `p-`, slice `s-`, task `t-` | error | naming prefixes |
| **S13** | residual files (`*-residual.md`) carry the `<!-- GENERATED` sentinel on line 1 | warn | residual whole-file generated |
| **S15/S16** | maintainer-mode tasks carry an `issue:` tag (one active task per issue) | error | one-task-per-issue |
| **S18** | a `done` task carries a `## affects` section | warn | affects frozen on done |
| **S20** | `<!-- GENERATED -->` / `<!-- /GENERATED -->` markers balance (open==close, never close-first) | error | fence integrity (R6/S20) |
| **dangling** | `[[t-…]]` targets resolve to a dir under the slice's `grad/` or `archive/` | warn | cross-task links |
| **layout** (`-Strict`) | per-mode required files exist (proj/slice tiers, `layout.md` table) | error | spec-compliance audit |

## 7. report + exit-code gate

Count `error` and `warn` rows. Emit the table (`severity | rule | path | message | fix-hint`); a
zero-violation tree prints a single `| pass | — | — | no violations | — |` row. Then emit the R7
contract via `Write-RatmacContract`:

```contract
Run mode: single
Active proj: <p-name>
Files touched: — (read-only, R11)
Lint result: <pass | N warn | N error, M warn>
Residual risk: lenient default (RQ7/a); pass -Strict for the full layout audit
```

(With `-Strict`, `Residual risk` reads `strict: per-mode layout audit run`.)

**Exit code** — `1` if any error-severity violation exists, else `0`. That non-zero-on-error
behavior is what makes `lint.ps1` / `lint.sh` usable as a pre-commit gate (warn-only trees still
exit 0).

## 8. stop rules (R11 / R12)

- **only hard halt** — no resolvable project: `Get-RatmacProj` throws; print `BLOCKED <message>`
  BEFORE the contract, emit a contract (`Files touched: — (read-only, R11)`, `Blocked items: no
  resolvable project`), exit `2`. STOP markers always print before the contract block, per the
  ratmac convention.
- **no other stops** — by R11 lint is a reporter: every schema/invariant/fence defect is a table
  row, never a halt. R12 (`HUMAN_DECISION_REQUIRED`) never fires — lint makes no write decision and
  never auto-fixes (that is `ratmac-regen`). `-Strict` only *adds* the layout audit; it never makes
  lint write.

## refs

- engine: `skills/ratmac-lint/scripts/lint.ps1` + the shared `skills/ratmac-kickoff/scripts/_common.ps1`
  (`Get-RatmacProj`, `Get-RatmacMode`, `Read-RatmacFrontmatter`, `Find-RatmacSection`,
  `Write-RatmacContract`). POSIX shadow: `lint.sh` + `_common.sh` at verb parity (R4).
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/skill-contracts.md` (ratmac-lint entry —
  rules covered, lenient default vs `-Strict`, never-stops), `invariants.md` (R5/R7/R9/R11/R12/R18),
  `layout.md` (the per-mode required-files tree `-Strict` audits against).
- upstream data model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/invariants.md` (S5/S7/S13/S15/
  S16/S18/S20), `lifecycle.md` (done → `## affects` frozen; residual regen), `file-roles.md`
  (`state.md` = cursor, `log.md` = stream, residuals = generated; `grad/` vs `archive/`).
