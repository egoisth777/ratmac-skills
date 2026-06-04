---
name: ratmac-init
description: >-
  Load this FIRST whenever you are about to touch the brain scheduler model
  (scheduler/p-<proj>/ trees) or run any other ratmac-* skill. Trigger phrases: "load the
  ratmac invariants", "what are the ratmac rules", "init ratmac", "remind me of R1-R18",
  "what is the ratmac output contract", or any session where you are about to kickoff /
  checkpoint / mutate / scope / close / transit a scheduler tier. It is a stateless loader —
  it writes nothing and has no script. It prints the locked R1-R18 invariants (scheduler-tree
  write boundary, pwsh-primary + POSIX shadow at verb parity, generated-regions-only,
  read-before-write, idempotent regen, lint-never-writes, auto-stops-on-ambiguity,
  chain-don't-recurse) plus the AQ note that R1-R18 enforce the upstream S1-S20 scheduler data
  model. It also prints the uniform output-contract template every ratmac skill must return.
  Other ratmac-* skills (ratmac-route, ratmac-kickoff, ratmac-checkpoint, ratmac-mutate,
  ratmac-scope, ratmac-close, ratmac-transit, ratmac-regen, ratmac-lint, ratmac-auto) load it
  via composition before they do anything. Use before everything; nothing composes after it
  but everything composes on it.
---

# ratmac-init

Stateless loader for the ratmac-skills family — the scheduler-automation twin of arca-init.
It is the shared preamble: it surfaces the locked **R1-R18 invariants** and the **uniform
output-contract template** so every downstream skill speaks the same rules and returns the
same shaped result. It performs **no filesystem writes** and has **no script** — it is pure
reference.

## when to use

- You are starting a session that will touch `brain/scheduler/p-<proj>/` (kickoff, checkpoint,
  mutate, scope, close, transit).
- You are about to run any other ratmac-* skill and need the shared rule set loaded first.
- Trigger phrases: "load the ratmac invariants", "what are the ratmac rules", "init ratmac",
  "remind me of R1-R18", "what is the ratmac output contract", "what shape do ratmac skills return".
- You need to recall the **write boundary (R5)**: ratmac skills mutate only under a
  `scheduler/` tree — never `store/`, `spaces/`, source code, or external systems.
- You need to recall the **upstream-authority seam (R2)**: ratmac skills automate the
  scheduler **S1-S20** data model; the S-invariants govern and the R-invariants enforce them.
- You need to recall the **generated boundary (R6/S20)**: generated-content writers touch
  only `<!-- GENERATED -->` … `<!-- /GENERATED -->` fenced regions (or whole residual files
  headed by `<!-- GENERATED — do not edit -->`).

Do NOT use it to scaffold anything — it never writes. For discovery use `ratmac-route`; to
start a tier use `ratmac-kickoff`; to record progress use `ratmac-checkpoint`.

## invocation

This skill has **no script** (pure loader). There is no `.ps1` and no `.sh` shadow.

- **manual invocation**: read `references/invariants.md` and `references/output-contract.md`
  (and `references/modes.md` for the quick role map). Recite the R1-R18 list and the
  `contract` block back; that is the entire behavior.
- **composition**: other ratmac-* skills load ratmac-init implicitly — they inherit R1-R18 and
  the output contract from these reference docs rather than re-stating them.

```
pwsh:  (no script — read references/invariants.md and references/output-contract.md)
posix: (no script — read references/invariants.md and references/output-contract.md)
```

## inputs

| param | required | description |
|---|---|---|
| — | — | none. ratmac-init takes no inputs and resolves no roots. |

## outputs

ratmac-init prints two things, then (when invoked standalone) closes with the contract block:

1. The **R1-R18 invariants** (verbatim from `references/invariants.md`), including the note
   that they enforce the upstream **S1-S20** scheduler data model (R2).
2. The **output-contract template** (verbatim from `references/output-contract.md`) — the
   fenced ```contract``` block, terminal-state set, and STOP markers that all ratmac skills reuse.

When run on its own it returns the ratmac output contract:

```contract
Run mode: single
Active proj: —
Active slice: —
Active task: —
Classification: —
Skill chain: ratmac-init
Files touched: —
Files generated: —
Lint result: not-run
Regen result: not-run
Open questions: —
Human decisions required: —
Blocked items: —
Next safe action: run ratmac-route to locate yourself, then ratmac-kickoff / ratmac-checkpoint / ratmac-close
Residual risk: none — loader is read-only
```

## stop rules

- ratmac-init **never stops** and **never blocks** — it is a pure load with no side effects
  (R9-adjacent: read-only, R11-adjacent: writes nothing). It emits no `BLOCKED` and no
  `HUMAN_DECISION_REQUIRED`.
- The only failure mode is a missing reference doc; if `references/invariants.md` or
  `references/output-contract.md` cannot be read, report that path and stop — there is
  nothing to load.

## composes

- **after**: nothing. ratmac-init is the root of the composition chain — it is loaded first.
- **triggers**: nothing directly. It does not call ratmac-regen or ratmac-lint (it writes
  nothing to lint or regenerate).
- **composed-on-by**: every other ratmac-* skill — `ratmac-route`, `ratmac-kickoff`,
  `ratmac-checkpoint`, `ratmac-mutate`, `ratmac-scope`, `ratmac-close`, `ratmac-transit`,
  `ratmac-regen`, `ratmac-lint`, `ratmac-auto` — loads ratmac-init before acting so they share
  R1-R18 and the output contract (R7).

## refs

- `references/invariants.md` — the locked R1-R18 invariants + the note that they enforce the
  upstream S1-S20 scheduler model (R2).
- `references/output-contract.md` — the uniform ```contract``` block, terminal states, and STOP markers (R7).
- `references/modes.md` — quick role map of all 11 ratmac skills (who writes, what composes after).
- Spec source: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/` — see `invariants.md`,
  `skill-contracts.md`, `model.md`, `orchestration.md`, `layout.md`, and `open-questions.md`;
  and the upstream data model `brain/buf/sparks/pdrft-brain-v3/s-scheduler/` (`invariants.md`
  for S1-S20, `lifecycle.md`, `layout.md`, `file-roles.md`).
