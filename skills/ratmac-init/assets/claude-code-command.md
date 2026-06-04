# ratmac-init — command seed

Paste this to invoke the loader:

> Load **ratmac-init**. Read `references/invariants.md` and `references/output-contract.md`
> under the skill, then recite the locked **R1-R18 invariants** (R5 scheduler-tree write
> boundary — never store/, spaces/, or code; R4 pwsh-primary + POSIX shadow at verb parity;
> R6/S20 generated-regions-only; R7 uniform output contract; R9 read-before-write; R10
> idempotent regen; R11 lint-never-writes; R12 auto-stops-on-ambiguity with
> HUMAN_DECISION_REQUIRED; R18 chain-don't-recurse) plus the **R2 note** that R1-R18 enforce
> the upstream **S1-S20** scheduler data model. Then print the uniform **output-contract**
> template — the fenced `contract` block, terminal states (completed-in-scope | blocked |
> human-decision-required), and STOP markers — that every ratmac-* skill must return. Write
> nothing; this is a stateless load with no script.

Usage example:

```
You: init ratmac / remind me of the ratmac rules before I kickoff a task
→ ratmac-init prints R1-R18 + the S1-S20 enforcement note + the contract template,
  writes nothing, and points you at ratmac-route to locate yourself next.
```
