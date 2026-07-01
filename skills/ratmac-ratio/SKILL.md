---
name: ratmac-ratio
description: Turns required upstream SEED material into grilled, linted, signed-off SPEC and DESIGN artifacts. Use when the user asks for ratmac-ratio, SPEC/DESIGN reconciliation, SPEC drafting from upstream SEED, DESIGN drafting from signed-off SPEC, or ratmac SPEC/DESIGN phase work.
---

# ratmac-ratio

## Mission

Operate as the ratmac SPEC and DESIGN phase skill. `ratmac-ratio` owns only
`spec.md` and `design.md`; it does not own SEED, TEST, BUILD, implementation,
release, executable tests, test contracts, or test plans.

Consume required upstream SEED material as input, produce internally consistent
SPEC and DESIGN artifacts, and follow scheduler `STATE.md` for the active phase
and status. During SPEC or DESIGN, trust only current-stage artifacts and
explicit upstream sources as evidence. Future-stage or downstream artifacts are
untrusted until their owning phase is active.

## Stage boundaries

- Required input: upstream SEED material. The default input name is `SEED`, but
  the user may provide another seed file.
- Upstream owner: `ratmac-creavit` owns SEED meaning and content.
- Current owner: `ratmac-ratio` owns SPEC and DESIGN.
- Downstream owner: `ratmac-ianitor` owns TEST when it exists and is active.

STATE phase values for `ratmac-ratio` are `SPEC` and `DESIGN`. Read `STATE.md`
before acting. Update STATE before the first draft of a new phase and inform the
user when a draft is written or when phase, state, or status changes.

If SEED meaning or content must change, stop SPEC/DESIGN work and route the
change to `ratmac-creavit`. Traceability-only forward links from SEED to SPEC are
allowed when they do not change SEED meaning or content and do not require
renewed SEED sign-off.

If SPEC or DESIGN work discovers a dependency on another ratmac skill, project
scheduler, external system, or a downstream owner that is missing or inactive,
create or route a raw requirement issue draft for the owning scheduler/inbox, or
an IPC outbox item for an external system. Do not fake an invocation of a missing
skill and do not route these needs as knowledge notes.

## Artifact rules

Write `DECISION.md` before SPEC or DESIGN. `DECISION.md` records accepted
user-visible decision entries. Each entry includes the domain-labelled question,
the user's accepted answer, the resulting decision, and affected artifacts.
Entries stay concise, avoid raw transcripts and internal reasoning, remain
chronological during active DESIGN grilling, may be revised as understanding
improves, and may be grouped later only if navigation becomes hard.

During DESIGN discussion, record each accepted user decision in `DECISION.md` and
reflect it into SPEC, DESIGN, or other relevant decision artifacts as applicable.
Continue DESIGN grilling without waiting for artifact updates unless the next
question depends on them, an edit collision occurs, or another blocker appears.
Accepted decisions and artifact updates must not be silently lost.

Stale future-stage artifacts such as `plan.md` or `test.md` are not current
evidence during SPEC or DESIGN. If scheduler-local `plan.md` or `test.md` exists
while DESIGN is active, treat it as stale/untrusted and remove it under the
scheduler source-of-truth rule rather than letting it steer SPEC/DESIGN work.

## SPEC

SPEC answers WHAT, not HOW. It must include all SEED content, may extend
SEED-derived content only through explicit user decisions, and must not include
implementation instructions or implementation details.

Generated SPEC artifacts have exactly these top-level sections:

1. Driving Question
2. Glossary
3. Requirements
4. Behaviors

Generated SPEC artifacts have no separate Traceability top-level section.
Traceability uses real double-sided Markdown links. For DESIGN coverage, link to
the nearest stable SPEC heading and quote the exact Requirement or Behavior
bullet instead of using ID-only references or explicit per-bullet HTML anchors.

Driving Question has one labelled main question and may include related
subquestions.

Glossary defines every term used in Requirements or Behaviors. Glossary entries
include behavior-domain examples. Each term usage links to its glossary entry,
and each glossary entry links forward to its usages.

Requirements contain only domain/product behavior-domain constraints and use:

`For all <subjects in scope>, under <condition>, <behavioral constraint> must hold, unless <explicit exception>.`

Each requirement has a behavior-domain example immediately below it.

Behaviors use strict `given...when...then...` form. Each behavior has a
behavior-domain example immediately below it.

Every SPEC item links to the relevant DECISION entry, and that DECISION entry
links back to the SPEC item. SEED-derived SPEC items link to both SEED and
DECISION. SPEC-added items link to DECISION.

Grill SPEC one user-facing question at a time. If unresolved feasibility or
"good enough?" questions remain, defer to future `ratmac-inqui` before DESIGN.

The linter blocks SPEC sign-off on malformed behaviors, missing glossary
definitions, missing or broken double-sided glossary links, missing or broken
DECISION-to-SPEC links, broken traceability, implementation details, or any other
SPEC rule failure.

Proceed to DESIGN only after the user says exactly:

`SPEC signed off`

## DESIGN

DESIGN answers HOW and remains subordinate to signed-off SPEC. It must cover
every SPEC behavior and requirement. It must not silently redefine WHAT or change
user-visible behavior.

Label every DESIGN grilling question as one of: `SPEC-only`, `DESIGN-only`,
`combination`, or `hybrid`.

If DESIGN work discovers SPEC behavior or artifact changes, stay in DESIGN.
Explicitly tell the user SPEC artifacts will change while DESIGN remains active,
then reconcile SPEC and DESIGN together only after required research is recorded
and the changes are reviewed. Do not announce a phase change merely to edit SPEC.

DESIGN records accepted implementation decisions only. Rejected alternatives may
appear in DECISION if discussed, but do not belong in DESIGN. DESIGN may include
operational concerns when they affect correctness, safety, maintainability, or
delivery of SPEC. DESIGN examples are implementation-domain examples that clarify
accepted decisions and must not create or change behavior.

Generated DESIGN artifacts have exactly these top-level sections:

1. Implementation Scope
2. Architecture
3. Implementation Decisions
4. Technical Constraints
5. Design Validation

Each top-level DESIGN section ends with a small `### Traceability` block. Blocks
contain outbound DESIGN-to-SPEC Markdown links grouped by SPEC source category or
actual SPEC section headings. Requirement and Behavior links target the nearest
stable SPEC heading and quote the exact source bullet. SPEC keeps reciprocal
SPEC-to-DESIGN backlinks grouped under relevant Requirements or Behaviors.

Before DESIGN sign-off, grill, lint, validate SPEC coverage, and revalidate DESIGN
against any reconciled SPEC changes. DESIGN sign-off must be explicit, but SPEC
defines no exact DESIGN sign-off phrase.

After DESIGN sign-off, stop at the TEST handoff. If `ratmac-ianitor` is missing
or inactive, route a raw requirement issue draft/handoff instead of invoking a
nonexistent downstream skill.
