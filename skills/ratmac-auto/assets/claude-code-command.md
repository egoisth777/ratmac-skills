# ratmac-auto — command seed

Paste this to invoke the skill:

> Run **ratmac-auto** to drive the scheduler for me. Take my free-text `-Intent`, run the orchestration loop `INIT → CLASSIFY → EVIDENCE → ROUTE → EXECUTE → VERIFY → REPORT`: spawn `ratmac-route` to resolve the active project/mode/slice/tasks (CLASSIFY), read the single active task's `state.md` for status evidence (EVIDENCE), then classify my intent against the A–L branch table (ROUTE). **Auto-run only the two safe ops** — `ratmac-regen` for branch F (regen/rollup/rebuild) and `ratmac-lint` for branch G / VERIFY. For ANY write branch (kickoff/checkpoint/mutate/scope/close/transit), STOP with `HUMAN_DECISION_REQUIRED`, print the exact `ratmac-*` command line with my active task wired in, and write nothing — R12 forbids guessing a scheduler write. Also STOP with `BLOCKED` if route can't resolve the scheduler context, `STOP-MODE` if the proj `mode:` is invalid, and `STOP-SCOPE` if my intent says rewrite/redesign/scrap/re-architect/overhaul. Always end with the uniform ratmac output contract.

Usage example:

```
# pwsh (primary, R4)
pwsh -NoProfile -File E:/packs/skills/ratmac-skills/skills/ratmac-auto/scripts/auto.ps1 `
  -Intent "regen the rollups then lint the scheduler" `
  -Until user-intervention `
  -Root E:/dev/lotus/arca/scheduler -Proj p-lotus

# posix (shadow, verb parity)
bash E:/packs/skills/ratmac-skills/skills/ratmac-auto/scripts/auto.sh \
  --intent "checkpoint progress on the active task" \
  --until user-intervention \
  --root E:/dev/lotus/arca/scheduler --proj p-lotus
```

Expect the phase headers (`-- CLASSIFY (ratmac-route) --`, `-- EVIDENCE --`, `-- ROUTE --`, `-- EXECUTE --`, `-- VERIFY (ratmac-lint) --`, `-- REPORT --`), a `Classification: <branch>` line, then a fenced `contract` block. On a **safe** branch (F=regen, G=lint) it auto-completes — `Skill chain: ratmac-route -> ratmac-regen -> ratmac-lint`, `Files touched: — (auto ran only read/verify ops)`, a `Regen result` / `Lint result`, and `Next safe action: review …` (exit 0). On a **write** branch it prints `HUMAN_DECISION_REQUIRED write branch '<X>'` plus a `run this: <exact ratmac-* command>` line and the task evidence, sets `Next safe action` to that command, and exits 3 without writing — then you confirm and invoke the named write skill (`ratmac-kickoff` / `ratmac-checkpoint` / `ratmac-mutate` / `ratmac-scope` / `ratmac-close` / `ratmac-transit`) yourself. A `BLOCKED` (exit 2) means route couldn't resolve the project/slice — pass `-Root`/`-Proj` or repair the missing `state.md`.
