# ratmac-kickoff — command seed

Paste this to invoke the skill:

> Run **ratmac-kickoff** to scaffold a new scheduler tier — a `proj`, `slice`, or `task` — under the
> `scheduler/` tree only (R5). Read the parent tier's `state.md` first (R9). For `-Tier proj` write
> `state.md` + `log.md` (and a `goal/` dir in sole|dual mode) — and STOP with `HUMAN_DECISION_REQUIRED` if
> `-Mode maintainer|sole|dual` is missing. For `-Tier slice` write `state.md` + `log.md` + `grad/` (plus
> `scope.md` + `scope-history.md` in sole|dual), then repoint the proj's active-slice pointer and append
> its log. For `-Tier task` write the four-file set `issue.md/task.md/state.md/log.md`, upsert the row into
> the slice `## tasks` table, and append the slice `log.md` line — and STOP with `BLOCKED` if there is no
> active slice, or (in maintainer mode) if `-Issue <ticket-id>` is missing (S15). STOP with `BLOCKED` if
> the tier already exists unless `-Force`. Seed `## affects` as an empty `<!-- GENERATED -->` fence; do not
> populate it. End with the uniform ratmac contract, then chain `ratmac-lint` to verify the new tier.

Usage example:

```
# pwsh (primary)
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-kickoff/scripts/kickoff.ps1 `
  -Tier proj  -Name lotus -Mode maintainer -Role "Lotus game scheduler" -Root E:/packs/brain/scheduler

pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-kickoff/scripts/kickoff.ps1 `
  -Tier slice -Name vert -Root E:/packs/brain/scheduler

pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-kickoff/scripts/kickoff.ps1 `
  -Tier task  -Name fix-ao-door-intensity -Issue EAV-1234 -Sprint 2026-w22 -Root E:/packs/brain/scheduler

# posix (shadow)
bash E:/packs/skills/ratmac-skills/skills/ratmac-kickoff/scripts/kickoff.sh \
  --tier task --name fix-ao-door-intensity --issue EAV-1234 --sprint 2026-w22 --root E:/packs/brain/scheduler
```

Expect a one-line `kickoff <tier>: <name> ...` receipt, then a fenced `contract` block with the new tier's
`Active proj` / `Active slice` / `Active task`, the `Files touched` list, and `Skill chain:
ratmac-kickoff` (kickoff spawns nothing — run `ratmac-lint` yourself to verify). On ambiguity it instead prints a STOP marker first — `HUMAN_DECISION_REQUIRED
proj kickoff needs -Mode (...)` (exit 3) or `BLOCKED ... already exists` / `no active slice` / `maintainer
mode requires -Issue` (exit 2) — followed by the contract. Then fill `issue.md`/`task.md` and drive the
task with `ratmac-checkpoint`, or kickoff the next tier down.
