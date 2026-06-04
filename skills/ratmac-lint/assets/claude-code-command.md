# ratmac-lint — command seed

Paste this to invoke the skill:

> Run **ratmac-lint** to audit my active scheduler project tree for schema, invariant, and fence defects without changing anything. Resolve the proj (a scheduler dir holding `p-*`, or a `p-<name>` dir directly), then walk the proj tier, every non-archive slice, and every task in `grad/` + `archive/`, and report a violations table covering S5 (frontmatter + `status`/`mode`), S7 (`p-`/`s-`/`t-` naming prefixes), S13 (residual `<!-- GENERATED` sentinel on line 1), S15/S16 (maintainer-mode `issue:` tag), S18 (`## affects` on done tasks), S20 (GENERATED fence balance), plus dangling `[[t-...]]` links. This is strictly read-only (R11: lint NEVER writes, even with `-Strict`): do not write, regen, or fix anything. Pass `-Strict` to add the per-mode required-files layout audit, or `-Rules S5,S20` to scope the checks. If no project resolves, stop with `BLOCKED <reason>` before the contract and exit 2. Exit 1 if any error-severity row so it can fail a commit hook.

Usage example:

```
# pwsh (primary)
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-lint/scripts/lint.ps1 -Root E:/packs/brain/scheduler -Proj p-lotus

# strict per-mode layout audit, scoped to two rules
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-lint/scripts/lint.ps1 -Proj p-lotus -Strict -Rules S5,S20

# posix (shadow)
bash E:/packs/skills/ratmac-skills/skills/ratmac-lint/scripts/lint.sh --root E:/packs/brain/scheduler --proj p-lotus
```

Expect a markdown violations table (`| severity | rule | path | message | fix-hint |`) — a clean tree prints a single `pass` row — then a fenced `contract` block (`Files touched: — (read-only, R11)`, `Lint result: pass | N warn | N error, M warn`). The process exits 1 if any error-severity row exists (else 0), so you can wire `lint.ps1` / `lint.sh` into a pre-commit hook. To repair what it flags, run **ratmac-regen** (rebuilds GENERATED `## affects` rollups + residual sentinels), then re-run ratmac-lint to confirm the drift is gone.
