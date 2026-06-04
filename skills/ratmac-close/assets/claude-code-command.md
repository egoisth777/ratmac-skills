# ratmac-close — command seed

Paste this to invoke the skill:

> Run **ratmac-close** to seal and file a finished or abandoned scheduler task. Resolve the active project/slice, find the task in `grad/`, then for a `done` close verify its `## affects` is non-empty and every `- [ ]` acceptance criterion in `issue.md` is checked — if `## affects` is empty stop with `BLOCKED need affects`, and if any criteria are unchecked stop with `HUMAN_DECISION_REQUIRED AC incomplete` (unless I pass `-Force`). On a clean close: set `status: done|abandoned` in the task `state.md` frontmatter, write the outcome into `## scratch`, append `status:<...>` to the task `log.md` and `close-task <t> status:<...>` to the slice `log.md`, flip `current: true` on the named `[sole|dual]` goal item, move the task dir `grad/t-<name>` → `s-<slice>/archive/`, and upsert the slice `## tasks` row. Then spawn **ratmac-regen** to rebuild the slice/proj `## affects` rollups and residuals (never re-run close itself, R18). Write only under the scheduler tree (R5) and return the contract; I'll run **ratmac-lint** after to verify.

Usage example:

```
# pwsh (primary)
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-close/scripts/close.ps1 -Task t-fix-ao-door-intensity -Status done -Cl 1234567 -Outcome "shipped: AO intensity reworked for in/out door transition" -Root E:/packs/brain/scheduler

# posix (shadow)
bash E:/packs/skills/ratmac-skills/skills/ratmac-close/scripts/close.sh --task t-fix-ao-door-intensity --status done --cl 1234567 --outcome "shipped: AO intensity reworked" --root E:/packs/brain/scheduler
```

For an abandoned task, swap `-Status done` for `-Status abandoned` (the affects + AC gates are skipped, and the log records `reason:<outcome>` instead of `cl:<id>`). For a `[sole|dual]` project, add `-Goal <topic>` to flip `current: true` on `goal/<topic>.md`. Pass `-Force` to override the `done`-only gates.

Expect a `close: <t-name> status:<...> -> archived under <slice>/archive/` receipt line (plus a goal-flip note if `-Goal` matched), then a fenced `contract` block (`Classification: close-task:<status>`, `Skill chain: ratmac-close -> ratmac-regen`, `Regen result: regen spawned`, `Next safe action: ratmac-lint to verify post-archive`). If a stop fires you'll see `BLOCKED ...` (exit 2) or `HUMAN_DECISION_REQUIRED ...` (exit 3) before the contract and no archive move happens. After it returns, run **ratmac-lint** to confirm the archived task, slice table row, and regenerated rollups are consistent.
