# ratmac output contract (R7)

Every ratmac-* skill returns a fenced `contract` block. Omit fields that don't apply; keep the order. Machine-parseable, human-readable. The field order is fixed by the engine's `Write-RatmacContract` (pwsh) / `ratmac_contract` (sh).

```contract
Run mode: <single | auto>
Active proj: <p-name, or —>
Active slice: <s-name, or —>
Active task: <t-ref, or —>
Classification: <branch letter, auto only>
Skill chain: <ratmac-route -> ratmac-kickoff -> ...>
Files touched: <abs/rel paths>
Files generated: <paths regen overwrote>
Lint result: <pass | N warn | N error | not-run>
Regen result: <hash-stable | N regions rebuilt | not-run>
Open questions: <...>
Human decisions required: <...>
Blocked items: <...>
Next safe action: <...>
Residual risk: <...>
```

## terminal states (closed-loop)

A run is closed iff it ends in exactly one of:

- `completed-in-scope` — skill reported success + lint passed + regen consistent
- `blocked` — named missing artifact (e.g. no active slice, empty `## affects`), decision, or authority
- `human-decision-required` — options + evidence prepared, no decision made

## STOP markers

When a skill cannot proceed it prints, before the contract block, one of:

- `BLOCKED <reason>` — missing artifact / authority (exit 2)
- `HUMAN_DECISION_REQUIRED <reason>` — ambiguous, needs a human call (exit 3)
