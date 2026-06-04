# ratmac-regen — command seed

Paste this to invoke the skill:

> Run **ratmac-regen** to rebuild the GENERATED scheduler content from its source-of-truth. Resolve the active project + mode, then recompute the whole-file residuals (`goal-residual.md` from goal `current:` flags, per-slice `scope-residual.md` from scope refs ∩ goal flags, per-slice `issues-residual.md` from open task `issue:` tags) and the fenced `## affects` rollups in slice + proj `state.md` (union of each task's `## affects` list). Touch ONLY generated content — the `<!-- GENERATED — do not edit -->` residual files (S13) and the `<!-- GENERATED -->` … `<!-- /GENERATED -->` fences (S20); leave everything else byte-for-byte intact (R6). Be byte-idempotent (R10): if nothing drifted, write nothing and report `hash-stable (no drift)`. Do not lint, do not guess a write branch (R12), and never spawn yourself (R18). If `--tier` is invalid or the project can't be resolved, stop with `BLOCKED <reason>` and return the contract.

Usage example:

```
# pwsh (primary)
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-regen/scripts/regen.ps1 -Root E:/packs/brain/scheduler -Tier all

# posix (shadow)
bash E:/packs/skills/ratmac-skills/skills/ratmac-regen/scripts/regen.sh --root E:/packs/brain/scheduler --tier all
```

Expect a `regen: <N> generated region(s) rebuilt` line, then a fenced `contract` block. On a clean run `Files generated` is empty and `Regen result: hash-stable (no drift)`; on drift, `Files generated` lists each rewritten region (residuals and/or slice/proj `state.md`) and `Regen result: <N> regions rebuilt`. `Next safe action: ratmac-lint to verify` — run **ratmac-lint** after to confirm fence integrity (S20), residual sentinels (S13), and `time-modified` bumps (S6). Pass `-Ts <stamp>` to pin a deterministic timestamp when you want reproducible output.
