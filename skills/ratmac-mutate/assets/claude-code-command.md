# ratmac-mutate — command seed

Paste this to invoke the skill:

> Run **ratmac-mutate** to revise an in-flight task in place instead of forking a rework sibling (S15,
> S16). Resolve the active project / slice / task, read its `state.md` first (R9), then: for `-Kind plan`
> or `approach`, revise `task.md` (replace its body from `-Diff` if given, else just bump `time-modified`
> so I can edit the body) and append a `<ts> replan <reason>` line to the task `log.md`; for `-Kind
> ticket`, append a `## ticket updates` entry to `issue.md` (preserving the original problem statement)
> and log `<ts> ticket-update <reason>`. Write only under the scheduler tree (R5) and touch `state.md`'s
> live cursor with `ratmac-checkpoint`, not here. If `task.md` is newer than `state.md` on a plan/approach
> mutate, STOP with `HUMAN_DECISION_REQUIRED` (likely already revised by hand) unless I pass `-Force`. End
> with the uniform contract block, then tell me to run `ratmac-checkpoint` + `ratmac-lint`.

Usage example:

```
# pwsh (primary)
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-mutate/scripts/mutate.ps1 `
  -Task t-fix-ao-door-intensity -Kind plan -Reason "dan-cr-wrong-class" -Proj p-lotus

# with a replacement task.md body
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-mutate/scripts/mutate.ps1 `
  -Task t-fix-ao-door-intensity -Kind approach -Reason "new-nav-api" -Diff E:/tmp/new-task.md

# ticket change (maintainer/dual): append a ## ticket updates note
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-mutate/scripts/mutate.ps1 `
  -Task t-fix-ao-door-intensity -Kind ticket -Reason "new AC: handle exterior shells"

# posix (shadow)
bash E:/packs/skills/ratmac-skills/skills/ratmac-mutate/scripts/mutate.sh \
  --task t-fix-ao-door-intensity --kind plan --reason "dan-cr-wrong-class" --proj p-lotus
```

Expect a one-line receipt (`mutate plan: t-fix-ao-door-intensity — dan-cr-wrong-class`), then a fenced
`contract` block with `Active task`, `Files touched` (`task.md`/`issue.md` + `log.md`), `Skill chain:
ratmac-mutate`, and `Next safe action: update task state.md via ratmac-checkpoint; ratmac-lint`. If you
hit `HUMAN_DECISION_REQUIRED task.md is newer than state.md ... (S15)`, the plan was likely already
hand-edited — re-run with `-Force` only if you really mean to overwrite. After the mutate, run
`ratmac-checkpoint` to record the new direction in the task's live cursor and `ratmac-lint` to verify;
run `ratmac-regen` only if a residual rollup depends on the revised plan.
