# ratmac-scope — command seed

Paste this to invoke the skill:

> Run **ratmac-scope** to expand or contract the active slice's scope. Resolve the scheduler root and
> active sole/dual-mode proj, confirm the slice has a `scope.md`, then add (`-Op +`) or remove
> (`-Op -`) the `[[<goal-topic>]]` ref: edit `scope.md`, append `+/- <topic> <reason> <YYYY-MM-DD>` to
> `scope-history.md` (S14), log `<ts> scope+|- <topic>` to the slice `log.md` (S19), and spawn
> `ratmac-regen` so `scope-residual.md` + `goal-residual.md` refresh. Write only under the scheduler
> tree (R5). STOP before any write if the proj is `maintainer` mode (`BLOCKED maintainer mode has no
> scope`), if `scope.md` is missing, if a `-Op -` ref isn't actually in scope, or — on `-Op +` naming a
> goal item that doesn't exist — with `HUMAN_DECISION_REQUIRED` unless I pass `-CreateGoal` to scaffold
> `goal/<topic>.md` (`current: false`). Return the contract.

Usage example:

```
# pwsh (primary)
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-scope/scripts/scope.ps1 `
  -Op + -Ref balance-pass -Reason "split out of build-buy, grew too big" -CreateGoal -Root E:/packs/brain/scheduler

# posix (shadow)
bash E:/packs/skills/ratmac-skills/skills/ratmac-scope/scripts/scope.sh \
  --op + --ref balance-pass --reason "split out of build-buy, grew too big" --create-goal --root E:/packs/brain/scheduler
```

Expect a one-line receipt (`scope+ balance-pass in s-<slice>`, with `(goal item scaffolded, current:
false)` when `-CreateGoal` fired), then a fenced `contract` block listing `Classification:
scope-mutation:+`, `Skill chain: ratmac-scope -> ratmac-regen`, the `Files touched` set
(`scope.md, scope-history.md, log.md`, plus `goal/<topic>.md` if scaffolded), `Regen result: regen
spawned`, and `Next safe action: ratmac-lint to verify scope/residual consistency`. Then run
**ratmac-lint** to confirm the scope and the regenerated residuals agree.
