# ratmac-checkpoint — command seed

Paste this to invoke the skill:

> Run **ratmac-checkpoint** to snapshot my progress on `t-<task>` without changing the plan or archiving
> anything. Read the task `state.md` first (R9), then: replace the `## status` body with the first line of my
> note, bump `time-modified` (S6), and append a `<ts> checkpoint <note>` line to the task `log.md` (S19). If I
> pass `-AddAffects`, add those paths to the task `## affects` list, deduped (S18). If I pass `-Status` and it
> differs from the current value, also flip the task frontmatter `status:`, upsert the slice `## tasks` table
> row, and append a `task-status` line to the slice `log.md`. Write ONLY under the scheduler tree (R5); touch
> no GENERATED region; trigger no other skill. If there is no active slice, stop with `BLOCKED no active
> slice ...`; if the task is not in the slice's `grad/`, stop with `BLOCKED task '<task>' not found ...`. End
> with the ratmac output contract.

Usage example:

```
# pwsh (primary)
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-checkpoint/scripts/checkpoint.ps1 `
  -Task fix-ao-door-intensity `
  -Note "wired up the indoor/outdoor intensity lerp; verifying on the porch locus next session" `
  -AddAffects MaxisGame/Source/TSOCEngine/Foo.cpp,MaxisGame/Source/TSOCEngine/Foo.h `
  -Root E:/dev/lotus/arca/scheduler

# posix (shadow)
bash E:/packs/skills/ratmac-skills/skills/ratmac-checkpoint/scripts/checkpoint.sh \
  --task fix-ao-door-intensity \
  --note "wired up the indoor/outdoor intensity lerp; verifying on the porch locus next session" \
  --add-affects MaxisGame/Source/TSOCEngine/Foo.cpp,MaxisGame/Source/TSOCEngine/Foo.h \
  --root E:/dev/lotus/arca/scheduler

# flip to blocked (ripples to the slice table + slice log)
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-checkpoint/scripts/checkpoint.ps1 `
  -Task fix-ao-door-intensity -Note "stalled: waiting on locus normals fix from t-foo" -Status blocked
```

Expect a `checkpoint: t-<name> — <note>` receipt line (plus an `affects +n (dup m)` line if you added paths,
and a `status -> blocked (slice table + log updated)` line if the status changed), then a fenced `contract`
block. `Files touched` lists the task `state.md` and `log.md` — and the slice `state.md` + `log.md` too only
when `-Status` actually changed. There is no `Files generated` / `Regen result` (checkpoint touches no
GENERATED rollups and chains to nothing). `Next safe action` points you at `ratmac-close` when the AC is met,
and `ratmac-lint` to verify the frontmatter bump and links.
