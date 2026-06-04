# ratmac-transit — command seed

Paste this to invoke the skill:

> Run **ratmac-transit** to end the active slice (or retire the project). First make sure every live
> task in the slice has been closed or migrated (`ratmac-close`) — transit STOPs with
> `HUMAN_DECISION_REQUIRED` if `t-*` dirs remain in `grad/`. Then it runs a final `ratmac-regen` of
> the tier's `## affects` rollup, writes `summary.md` (the one-pager: what shipped, what carried
> forward, key decisions), sets `status: done`, and `mv`s the tier dir into the parent's `archive/`.
> For a slice, pass `-NewSlice <s-name>` to point the project at its successor (it is NOT
> auto-created — `ratmac-kickoff` is the next step) or `-NoSuccessor` to end the line; for a project,
> use `-Tier proj`. Write only under the scheduler tree (R5), read `state.md` first (R9), and let
> every STOP fire before any write (R12). Finish with `ratmac-lint` on the archived tree.

Usage example:

```
# pwsh (primary)
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-transit/scripts/transit.ps1 `
  -Tier slice -NewSlice s-mp-alpha `
  -Summary "vert slice shipped: AO rework + posture graph landed; CAS deferred to s-mp-alpha; key decision — agents drive actors via visulator timeline"

# posix (shadow)
bash E:/packs/skills/ratmac-skills/skills/ratmac-transit/scripts/transit.sh \
  --tier slice --new-slice s-mp-alpha \
  --summary "vert slice shipped: AO rework + posture graph landed; CAS deferred to s-mp-alpha; key decision — agents drive actors via visulator timeline"
```

Expect a `transit slice: <s-name> archived under <p-name>` line and a `next:` hint, then a fenced
`contract` block (`Classification: slice-transit`, `Skill chain: ratmac-transit -> ratmac-regen ->
ratmac-lint`, `Active slice: <s-name> (archived)`, `Regen result: proj rollup rebuilt (final)`, a
`Lint result`, and `Next safe action: ratmac-kickoff -Tier slice -Name <s-new>`). For `-Tier proj`
expect `transit proj: <p-name> retired → <archive path>` with `Classification: proj-retire` and
`Next safe action: none — project archived`. If live tasks remain you instead get
`HUMAN_DECISION_REQUIRED active tasks present: <list>` (exit 3) — close them with `ratmac-close`
first, or re-run with `-Force`. If you forgot the successor decision you get
`HUMAN_DECISION_REQUIRED no successor slice` — re-run with `-NewSlice <s-name>` or `-NoSuccessor`.
Then, for a slice with a successor, run `ratmac-kickoff -Tier slice -Name <s-new>` to scaffold it.
