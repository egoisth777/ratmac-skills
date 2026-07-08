---
name: ratmac-ratio
description: Use when the user asks for ratmac-ratio or ratmac SPEC/DESIGN phase work — drafting SPEC from upstream SEED, drafting DESIGN from a signed-off SPEC, SPEC/DESIGN reconciliation, being grilled toward sign-off ("grill me", "spec interview", "one question at a time"), or when the user types a sign-off phrase ("SPEC signed off" / "DESIGN signed off", optionally issue-qualified).
---

# ratmac-ratio

## Role

`ratmac-ratio` grills the user to produce SPEC (answers WHAT) and DESIGN
(answers HOW) artifacts for a scheduler issue, one question at a time, with
explicit sign-off gates.

## Contract — required reading

Canonical rules live in the ratio issue's contract docs:

- `.arca/scheduler/issue/i-ratmac-ratio/spec.md` — SPEC rules + linter contract
- `.arca/scheduler/issue/i-ratmac-ratio/design.md` — process/DESIGN rules
- `.arca/scheduler/issue/i-ratmac-ratio/DECISION.md` — rationale ledger,
  append-only

While the ratio issue is in phase DESIGN, those files are the sole statement
of rules. This file intentionally states no rules (de-mirrored per review.md
RV-2, 2026-07-03). You MUST read `spec.md` § Grilling, linting, and sign-off
and `design.md` § Implementation Decisions and § Technical Constraints in full
before asking the first grilling question or accepting any sign-off. If the
contract docs are missing or unreadable, STOP and tell the user — do not
improvise rules.

At DESIGN sign-off, a publish step regenerates SKILL.md and REFERENCE.md from
the signed-off contract as GENERATED views (rules: `design.md`).

## Turn skeleton

Workflow shape only — NOT executable on its own; every rule that binds a step
lives in the contract docs. Do not act from this list without having read them.

1. Resolve the target issue and read its `state.toml` (fields: phase, status,
   time-modified).
2. Grill one question at a time.
3. Record each accepted decision in DECISION.md and the affected artifacts
   before continuing.
4. Keep drafts current during grilling.
5. Lint before sign-off.
6. Phase transitions gate on the exact sign-off phrases.
7. On DESIGN sign-off, record the decision entry and stop; a downstream owner
   later sets phase to TEST.

## Pointers

Exact sign-off phrase strings, question templates, and the DECISION entry
shape live in the contract docs (`spec.md`, `design.md`). REFERENCE.md is a
stub until the publish step regenerates it.
