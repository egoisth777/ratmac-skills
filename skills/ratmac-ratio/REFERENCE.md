# ratmac-ratio reference

This reference gives compact prompt shapes and checklists for the current
`ratmac-ratio` SPEC/DESIGN contract. The scheduler source of truth remains
`.arca/scheduler/issue/i-ratmac-ratio/{STATE.md,DECISION.md,spec.md,design.md}`.
Do not use future-stage artifacts such as `plan.md` or `test.md` as evidence
while SPEC or DESIGN is active.

## User-facing turn skeleton

```text
Current stage: <SPEC | DESIGN>

[Primary answer, boundary, evidence, or artifact update summary.]

[If DESIGN answer touches SPEC: explicit notice that SPEC artifacts will change while DESIGN remains active.]

[Exactly one labelled grilling question, or the applicable sign-off gate.]
```

## Stage and trust checklist

Before acting:

1. Read `STATE.md` for `phase` and `status`.
2. Trust only current-stage artifacts and explicit upstream sources.
3. Treat downstream/future-stage files, including `plan.md` and `test.md`, as
   untrusted until their owning phase is active.
4. Keep phase and status separate: valid `ratmac-ratio` phases are `SPEC` and
   `DESIGN`.
5. Inform the user when writing drafts or changing phase, state, or status.

## SPEC question template

```text
Current stage: SPEC

[Short answer grounded in SEED, DECISION, SPEC, or explicit user input.]

SPEC-only question: <one WHAT/domain/product behavior question>
```

SPEC questions ask for WHAT, not HOW. Do not ask for implementation mechanisms.
If unresolved feasibility or "good enough?" questions remain, defer to future
`ratmac-inqui` before DESIGN.

## SPEC sign-off gate

SPEC can advance to DESIGN only when the user says exactly:

```text
SPEC signed off
```

Informal approval, silence, non-objection, or topic change is not enough.

## DESIGN question templates

### DESIGN-only

```text
Current stage: DESIGN

[Short answer grounded in signed-off SPEC, DECISION, DESIGN, or required research.]

DESIGN-only question: <one HOW/implementation decision question>
```

### SPEC-affecting DESIGN question

```text
Current stage: DESIGN

This answer may require SPEC artifact changes while DESIGN remains active. I will reconcile SPEC and DESIGN together after the answer, with required research recorded and review performed.

< SPEC-only | combination | hybrid > question: <one question>
```

Use exactly one domain label for every DESIGN grilling question: `SPEC-only`,
`DESIGN-only`, `combination`, or `hybrid`.

## In-DESIGN SPEC reconciliation checklist

When DESIGN discovers a SPEC behavior or artifact change:

1. Keep `STATE.md` phase as `DESIGN`.
2. Give explicit notice that SPEC artifacts will change while DESIGN remains
   active.
3. Reconcile SPEC and DESIGN together so WHAT and HOW stay consistent.
4. Record required research when the decision is research-backed.
5. Review SPEC-affecting updates; reviewer findings are user-decision inputs and
   do not automatically pause discussion, reconcile artifacts, or apply fixes.
6. Revalidate DESIGN against the revised SPEC before DESIGN sign-off.

Do not announce a phase change merely to edit SPEC. Do not silently patch DESIGN
around missing or changed user-visible behavior.

## DECISION entry shape

```md
## <concise decision title>

Question: [<SPEC-only | DESIGN-only | combination | hybrid>] <question>

Answer: <accepted user answer>

Decision: <resulting decision>

Affected artifacts: `<path>`, `<path>`.
```

Entries are concise user-visible decision records, not raw transcripts or
internal reasoning logs. Keep them chronological during active DESIGN grilling.

## Traceability checklist

SPEC:

- Top-level sections are exactly Driving Question, Glossary, Requirements,
  Behaviors.
- No separate top-level Traceability section.
- Every SPEC item links to DECISION; SEED-derived SPEC items also link to SEED.
- Glossary links are double-sided.

DESIGN:

- Top-level sections are exactly Implementation Scope, Architecture,
  Implementation Decisions, Technical Constraints, Design Validation.
- Every top-level DESIGN section ends with `### Traceability`.
- DESIGN links to nearest stable SPEC headings and quotes exact Requirement or
  Behavior bullets when traceability is bullet-level.
- SPEC reciprocal backlinks are grouped under relevant Requirements or Behaviors;
  do not add per-bullet HTML anchors only for traceability.

## DESIGN sign-off and downstream handoff

DESIGN sign-off must be explicit after grilling, linting, SPEC coverage
validation, and any in-DESIGN SPEC reconciliation. There is no required exact
DESIGN sign-off phrase.

After DESIGN sign-off, stop at the TEST handoff. If the downstream owner is
missing, inactive, external, or otherwise not owned by `ratmac-ratio`, create or
route a raw requirement issue draft for the owning scheduler/inbox or an IPC
outbox item for the external system. Do not pretend a missing downstream skill was
invoked.
