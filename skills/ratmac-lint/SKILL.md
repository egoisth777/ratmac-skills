---
name: ratmac-lint
description: >-
  Use when you need to catch schema, invariant, and fence defects in a scheduler/ project tree
  WITHOUT changing anything — trigger phrases: "lint the scheduler", "check the ratmac invariants",
  "audit the scheduler tree", "any dangling [[t-...]] links?", "is the GENERATED fence balanced?",
  "did a done task forget its affects?", or as a pre-commit / post-write gate. It is strictly
  read-only (R11: lint NEVER writes, even with -Strict): it walks the resolved proj's proj/slice/task
  tiers and reports a violations table covering S5 (frontmatter + status/mode), S7 (p-/s-/t- naming
  prefixes), S13 (residual GENERATED sentinel), S15/S16 (one-active-task-per-issue tag in maintainer
  mode), S18 (## affects on done tasks), S20 (GENERATED fence balance), plus dangling [[t-...]] links.
  Default is lenient; pass -Strict for the per-mode required-files layout audit and -Rules to scope
  to specific checks. Exits 1 if any error-severity violation, so it can fail a commit hook. Use
  after $ratmac-init and $ratmac-route; it is auto-invoked by $ratmac-transit on success, and is the
  recommended manual verify after $ratmac-kickoff / $ratmac-close / $ratmac-regen; it pairs with
  $ratmac-regen (regen fixes fence/residual drift, lint proves it gone).
---

# ratmac-lint

Read-only defect catcher for a scheduler `p-<name>` project tree (R11 — it never writes, even with
`-Strict`). It walks the proj tier, every non-archive slice, and every task in `grad/` + `archive/`,
then emits a uniform violations table plus the shared R7 output contract. It is the gate counterpart
to `ratmac-regen`: regen *repairs* GENERATED rollups and residual sentinels; lint *proves* the tree
is clean and fails loudly (exit 1) when it is not.

## when to use

- "lint the scheduler" / "check the ratmac invariants" / "audit the scheduler tree"
- "any dangling `[[t-...]]` links?" — a task link whose target sits in neither `grad/` nor `archive/`
- "is the GENERATED fence balanced?" (S20) / "did a done task forget its `## affects`?" (S18)
- "is every state.md missing its `time-modified` / `status` / `mode`?" (S5)
- "do the dir names carry the `p-`/`s-`/`t-` prefixes?" (S7)
- maintainer mode: "does every active task carry an `issue:` tag?" (S15/S16)
- as a **pre-commit or post-write gate** — exit 1 on any error blocks the commit
- right after a hand-edit to a residual / GENERATED region, or after `ratmac-regen`, to confirm zero drift

## invocation

pwsh (primary, R4):

```
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-lint/scripts/lint.ps1 [-Root <path>] [-Proj <p-name>] [-Strict] [-Rules S5,S20] [-Ts <stamp>]
```

posix (shadow, R4):

```
bash E:/packs/skills/ratmac-skills/skills/ratmac-lint/scripts/lint.sh [--root <path>] [--proj <p-name>] [--strict] [--rules S5,S20] [--ts <stamp>]
```

Roots resolve the same way for every ratmac skill (via the shared `_common` engine): explicit
`-Root`/`--root` (a scheduler dir holding `p-*` children, or a `p-<name>` dir directly) → env
`RATMAC_SCHEDULER_ROOT` → ancestor walk of the cwd preferring an `arca/scheduler` mount, then a
`scheduler` dir, then any dir already holding `p-*` children. The proj is then `-Proj`, else the
single `p-*` child, else the one whose `state.md` is `status: active`. No proj resolvable → `BLOCKED`.

## inputs

| param | flag (pwsh / posix) | required | default | meaning |
|---|---|---|---|---|
| Root | `-Root` / `--root` | no | env / cwd walk | scheduler root holding `p-*`, or a `p-<name>` dir directly |
| Proj | `-Proj` / `--proj` | no | single `p-*`, else the `status: active` one | which project tree to audit |
| Strict | `-Strict` / `--strict` | no | off | add the per-mode required-files layout audit (`layout.md` table vs disk); still read-only |
| Rules | `-Rules S5,S20` / `--rules S5,S20` | no | all | scope checks to a comma-separated subset (`S5,S7,S13,S15,S18,S20,dangling,layout`) |
| Ts | `-Ts` / `--ts` | no | now | timestamp override (engine parity; lint touches no files) |

## outputs

A markdown violations table, then the uniform ratmac output contract (R7). Each row is
`severity | rule | path | message | fix-hint`. A clean tree prints a single `pass` row.

```contract
Run mode: single
Active proj: <p-name>
Files touched: — (read-only, R11)
Lint result: 1 error, 2 warn
Residual risk: lenient default (RQ7/a); pass -Strict for the full layout audit
```

`Lint result` is `pass`, `N warn`, or `N error, M warn`. Process exit code is **1 if any
error-severity violation exists**, else 0 — that is what makes it usable as a commit gate.

## stop rules

`ratmac-lint` **never stops to report defects** — by R11 it is a reporter, not a mutator, so every
defect lands in the table rather than halting. There is no `HUMAN_DECISION_REQUIRED` path (R12
does not fire): lint defers all decisions to the human reading the table, and it never auto-fixes
(that is `ratmac-regen`). The only hard halt is upstream of the scan:

- No resolvable project (root unresolvable, or cannot disambiguate which `p-*` is active) →
  `Get-RatmacProj` throws; lint prints `BLOCKED <reason>` BEFORE the contract, emits a contract with
  `Files touched: — (read-only, R11)` and `Blocked items: no resolvable project`, and exits `2`.
  (Set `-Root`/`-Proj`, `RATMAC_SCHEDULER_ROOT`, or run inside a scheduler tree.)

## composes

- **after**: `ratmac-init` (loads S1–S20 + the R7 contract), `ratmac-route` (orients you in the tree)
- **auto-invoked by**: `ratmac-transit` on success (the gate that confirms the transition left the
  tree clean). `ratmac-kickoff` and `ratmac-close` do NOT spawn lint — they recommend it as the next
  step; run it as a **recommended manual verify** after `ratmac-kickoff` / `ratmac-close` / `ratmac-regen`
- **pairs with**: `ratmac-regen` — run regen to rebuild GENERATED `## affects` rollups + residual
  sentinels, then run lint to confirm S20 fence balance and S13 sentinels hold and nothing dangles
- **gate**: drop `lint.ps1` / `lint.sh` into a pre-commit hook; non-zero exit fails the commit
- per R18 a skill may spawn another skill's script but never itself; lint spawns nothing — it is a
  leaf reporter

## refs

- [references/lint-protocol.md](references/lint-protocol.md) — the step-by-step protocol `lint.ps1`
  implements: root/proj resolution, the proj→slice→task walk, each audit (S5/S7/S13/S15/S18/S20/
  dangling), the `-Strict` per-mode layout audit, the table, and the exit-code gate.
- [assets/claude-code-command.md](assets/claude-code-command.md) — paste-to-invoke command seed.
- spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/` — `skill-contracts.md` (ratmac-lint
  entry), `invariants.md` (R5/R7/R9/R11/R12/R18), `open-questions.md`, `layout.md` (the disk tree
  `-Strict` audits against), `model.md`, `orchestration.md`.
- upstream data model: `brain/buf/sparks/pdrft-brain-v3/s-scheduler/` — `invariants.md` (S1–S20),
  `lifecycle.md` (done → `## affects` frozen, residual regen), `layout.md`, `file-roles.md`.
