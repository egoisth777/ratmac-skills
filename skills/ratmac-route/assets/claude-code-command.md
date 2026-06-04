# ratmac-route — command seed

Paste this to invoke the skill:

> Run **ratmac-route** to orient me in scheduler land before I write anything. Resolve the scheduler root and the active project (`-Proj`, else the single `p-*`, else the `status: active` one), read its `state.md` for the mode, find the active slice, list the in-flight tasks under `s-<slice>/grad/t-*` with each task's status and `blocked-by`, tail the last 5 dated lines of the slice (else proj) `log.md`, then suggest a next-action mode (`continue-task | new-task | scope-mutation | slice-transit`, or `new-slice` / `new-task` when none are in flight). This is read-only: do not write, regen, or lint anything. If the project can't be resolved, or the proj `state.md` is missing, stop with `BLOCKED <reason>` (exit 2) and return the contract.

Usage example:

```
# pwsh (primary)
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-route/scripts/route.ps1 -Root E:/packs/brain/scheduler

# posix (shadow)
bash E:/packs/skills/ratmac-skills/skills/ratmac-route/scripts/route.sh --root E:/packs/brain/scheduler
```

Expect an `Active project: ...` line, a `Mode:` line, an `Active slice:` line, an `Active tasks: [...]` list, a `Recent log entries:` tail, a `Suggested next-action mode:` line, then a fenced `contract` block (`Files touched: — (read-only)`, `Lint result: not-run`). Then pick the suggested mode and invoke its write-skill — `ratmac-kickoff` for new-task/new-slice, `ratmac-checkpoint`/`ratmac-mutate` to continue a task, `ratmac-scope` for scope mutation, or `ratmac-close` + `ratmac-transit` to wind a slice down.
