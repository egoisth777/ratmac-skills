# ratmac skill roles (quick map)

All 11 skills (R3, frozen set). Mirrors the role table in `s-ratmac-skills/model.md`. "writes" = filesystem touch; every write stays under the `scheduler/` tree (R5).

| skill | role | writes | composes after |
|---|---|---|---|
| ratmac-init | load R1–R18 + output contract template | no | — |
| ratmac-route | session boot: read p-<active>/state.md, list slice + tasks, classify next-action mode | no | init |
| ratmac-kickoff | scaffold a proj \| slice \| task tier + required files (S2/S3 layout) | yes | init, route |
| ratmac-checkpoint | snapshot pause: bump state.md, append log.md line, add to `## affects` | yes | init, route |
| ratmac-mutate | in-place plan/approach/ticket change (S15, S16) | yes | init, route |
| ratmac-scope | sole/dual scope mutation: scope.md + scope-history.md + log line | yes | init, route |
| ratmac-close | task done/abandoned: freeze affects, status, log, mv to archive, trigger regen | yes | init, route |
| ratmac-transit | slice/proj transition: write summary.md, regen, mv to archive | yes | init, route |
| ratmac-regen | rebuild generated content: residuals + fenced `## affects` rollups (idempotent) | generated only | — |
| ratmac-lint | schema + invariant + fence + dangling-link check; `--strict` audits | no | — |
| ratmac-auto | orchestrator: state machine, closed-loop, delegates to other skills | delegates | init, route |
