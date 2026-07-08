+++
id = "conv_260702_ratmac-ratio-design-and-automata-boundary-grilling"
topic = "ratmac-ratio design and automata boundary grilling"
status = "active"
tags = ["automata", "design", "ratio", "ratmac", "review", "scheduler"]
refs = [
  { id = "conv_260703_ratmac-ratio-design-review", rel = "informed" },
]
created = 2026-07-03T05:25:18Z
updated = 2026-07-03T20:32:22Z
+++
## summary
Designed and corrected ratmac-ratio/ratmac-automata boundaries, narrowed to nailing ratmac-ratio; now mid over-engineering review pass: 14 ranked findings in i-ratmac-ratio/review.md being ruled one by one (RV-1, RV-2 accepted - RV-2 de-mirror already executed; RV-3 presented, awaiting verdict).

## dict
- **ratmac-ratio** - plugin/process for grilling and producing SPEC + DESIGN artifacts; current focus.
- **SPEC** - answers WHAT; sign-off explicit, issue-qualified when multiple issues active.
- **DESIGN** - answers HOW; sign-off explicit, issue-qualified when multiple issues active.
- **multi-issue grilling thread** - one active thread may manage multiple issues with per-issue labeling and gates (under review: RV-8).
- **scope-out routing** - behavior/design outside the current issue routes to the right issue via spark/IPC; never absorbed.
- **terminal handoff** - ratio-side completion signal after DESIGN; ratio never flips phase (under review: RV-5 proposes deleting the artifact concept; the behavior stays).
- **ratmac-automata** - future central orchestration/state-machine issue; runtime delayed; per RV-1 it also controls the graph/registry subsystem.
- **owner/current-state owner** - neutral vocabulary used in i-ratmac-automata; the term scale is rejected.
- **graph topology** - .arca/scheduler/graph/issue-dep-graph.json + registry.json; contract owned by ratmac-automata (RV-1); schemas to migrate to its sparks.md.
- **flat registry** - registry.json flat dash-id map; concrete entries source-kind/source-id/source-path, virtual entries no fake source-path; same RV-1 ownership ruling.
- **review.md / review ledger** - .arca/scheduler/issue/i-ratmac-ratio/review.md; 14 ranked over-engineering findings RV-1..RV-14, statuses open/accepted/rejected/amended; ruled one by one by the user.
- **RV-N** - finding ids in review.md, ranked biggest cut first.
- **de-mirror** - SKILL.md/REFERENCE.md state no rules and point at the contract docs; executed 2026-07-03 (SKILL 188->46 lines, REFERENCE 175->118).
- **publish-at-sign-off** - one-time copy of the signed-off contract into the skill docs at DESIGN sign-off; replaces continuous mirroring.
- **ponytail pass** - complexity-only audit (tags delete/yagni/native/shrink); correctness excluded.
- **end-of-pass batch** - deferred execution after all verdicts: DECISION entries, spec/design surgery, RV-1 migration spark, AGENTS.md TEMP removal if RV-4 accepted.

## qa
- **Q:** Can ratmac-ratio manage multiple issues in one active thread? **A:** Yes (decision 7); the labeling machinery is under review (RV-8, pending).
- **Q:** Should SPEC/DESIGN sign-off be issue-qualified? **A:** Yes (decision 8); the dual-binding rule is under review (RV-8, pending).
- **Q:** Deliver the automata daemon/runtime now? **A:** No; manual/agent-triggered while the contract is unsettled.
- **Q:** Use the term scale? **A:** No; neutral owner/current-state owner wording.
- **Q:** Is the ratio design overcomplicated? **A:** Yes - ponytail audit produced 14 findings, ~600-700 cuttable lines of ~1725; ledger at review.md.
- **Q:** Where does the graph/registry contract live? **A:** RV-1 accepted - controlled by ratmac-automata; schemas migrate to i-ratmac-automata/sparks.md; ratio keeps one blocked-routing paragraph.
- **Q:** Keep SKILL/REFERENCE mirrors? **A:** RV-2 accepted - de-mirrored (executed 2026-07-03); publish-once at DESIGN sign-off.
- **Q:** Linter contract-only first? **A:** Effectively settled contract-first: SPEC checklist exists (RV-13 trims 8->4, pending); DESIGN checklist falls out of RV-3 (pending).
- **Q:** Terminal handoff fields? **A:** RV-5 (pending) proposes none - state.toml + the sign-off DECISION entry suffice (GATE.md precedent, DECISION #47).
- **Q (open):** RV-3 verdict - compress design.md Design Validation (111-line paraphrase) to the 5-assert DESIGN lint checklist? Presented, awaiting ruling.
- **Q (open):** RV-4..RV-14 verdicts (writer/IRC fleet, handoff repetition, IPC layer, baseline renderer, multi-issue machinery, reciprocal links, 3 named reviewers, automata mentions, state.toml negatives, linter 8->4, DECISION ledger hygiene).
- **Q (open):** Stale .arca/scheduler/draft/* disposition (archive/drop/re-import) - outside the review corpus.
- **Q (open):** Exact wording of the batched DECISION entries (RV-1 residency supersession; RV-2 publish step).

## resume
- goal: Finish the one-by-one verdict pass over review.md (RV-3 presented, RV-4..RV-14 queued), then execute the end-of-pass batch.
- next-steps:
  - Get RV-3 verdict (design.md Design Validation 111-line paraphrase -> 5-assert DESIGN lint checklist; recommendation: accept)
  - Continue RV-4..RV-14 one at a time: discuss (case for cut / steelman / recommendation), user rules, flip status in review.md
  - End-of-pass batch: append DECISION entries (RV-1 residency supersession of #30-34 #39-43 #51-54; RV-2 de-mirror + publish-at-sign-off; plus later accepts), surgery on spec.md/design.md, migration spark into i-ratmac-automata/sparks.md, AGENTS.md TEMP block removal if RV-4 accepted
  - Verify the batch (fence/link lint pass), then resolve the remaining thread: .arca/scheduler/draft/* disposition
- open-questions:
  - RV-3..RV-14 verdicts
  - batched DECISION entry wording
  - draft/* disposition (archive/drop/re-import)
- suggested-skills:
  - conversate
  - ratmac-ratio
  - ponytail-audit

## user-instructions
- Begin every chat response with Aye, m'lord
- Do not use the word scale in automata terminology; it was rejected
- Nail ratmac-ratio first as starter for whole-system SPEC/DESIGN
- Do not blindly accept suggestions; research feasibility before recording decisions
- Keep daemon/automata runtime delayed; use manual/agent-triggered transitions
- Route behavior/design outside the current issue to other issues; never absorb out-of-scope behavior
- Review findings are ruled one by one by the user - discuss each (case for cut, steelman, recommendation) and wait for the verdict; never rule autonomously
- Flip review.md statuses immediately on a ruling; batch DECISION entries and artifact surgery at end of pass (RV-2 de-mirror was explicitly ordered executed immediately)

## condensed-transcript
- U: handoff from temp file
- A: Loaded/verified handoff, continued ratmac-ratio grilling.
- U: confirmed graph topology
- A: Recorded issue-dep-graph.json + registry.json and flat registry shape.
- U: ratio only cares about output; automata handles global state machine
- A: Recorded ratio output-only boundary and revised TEST-owner/two-outcome text.
- U: merge lifecycle-state-machine and scheduler-vision into automata
- A: Created i-ratmac-automata, moved old issues to dropped, linked backups.
- U: incoming skill writes might be better
- A: Recorded ratio-side terminal handoff/no phase TEST write; activation left open under automata.
- U: automata has many issues/goals/residuals
- A: Researched dropped scheduler-vision content and corrected issue-only bias; later user rejected the scale term.
- U: delay daemon?
- A: Recommended and recorded daemon delay; keep manual/agent transitions while contract unsettled.
- U: what remains in ratio?
- A: Listed remaining ratio items; then recorded multi-issue grilling and issue-qualified sign-off.
- U: quit / conversate
- A: Saved distilled resumable conversation record.
- U: resume from the conversation on ratmac
- A: Resumed record; scouted current artifacts: closing decisions persisted, baseline renderer spec'd, 6 stale STATE.md refs, SPEC linter exists contract-only; teed up the linter question.
- U: audit the whole ratmac design for overcomplication; write findings to i-ratmac-ratio/review.md
- A: Ponytail audit via 3 parallel readers; ground truth: graph/ and ipc/ do not exist, one issue past SEED; wrote review.md with 14 ranked findings (~600-700 cuttable lines).
- U: discuss findings one by one, I decide
- A: Presented RV-1 (graph/registry residency).
- U: accept RV-1; graph/registry controlled by ratmac-automata
- A: Flipped RV-1 accepted; execution batched (schema spark to automata, ratio keeps blocked-routing paragraph); presented RV-2 (triple-mirror).
- U: accept RV-2, go ahead and de-mirror
- A: Executed de-mirror (SKILL 188->46, REFERENCE 175->118, STATE.md refs fixed, mechanism-neutral skeleton); flipped RV-2; presented RV-3 (Design Validation paraphrase -> 5-assert DESIGN lint checklist).
- U: conv:save
- A: Restored store CLI (copied conv_cli.py into .conversate/scripts/) and upserted this checkpoint.

## sources
- Handoff source: C:/Users/egois/AppData/Local/Temp/ratmac-ratio-handoff-2026-07-02.md
- Project instructions: AGENTS.md and .arca/AGENTS.md
- Ratio artifacts: .arca/scheduler/issue/i-ratmac-ratio/spec.md, design.md, DECISION.md
- Review ledger: .arca/scheduler/issue/i-ratmac-ratio/review.md (physical: E:/repos/brain/scheduler/p-ratmac-skill/issue/i-ratmac-ratio/review.md)
- Ratio runtime docs (de-mirrored): skills/ratmac-ratio/SKILL.md, skills/ratmac-ratio/REFERENCE.md
- Automata artifacts: .arca/scheduler/issue/i-ratmac-automata/sparks.md
- Dropped source material: .arca/scheduler/issue/dropped/i-ratmac-scheduler-vision/sparks.md, dropped/i-ratmac-lifecycle-state-machine/sparks.md
- Graph contract paths (ownership now automata per RV-1; neither file exists yet): .arca/scheduler/graph/issue-dep-graph.json, registry.json
- conversate CLI: C:/Users/egois/.claude/skills/conversate/scripts/conv_cli.py (restored into .conversate/scripts/)

## insights
- Do not let ratmac-ratio become the global daemon; nail ratio first, route automata concerns out.
- Richer scheduler-vision material still lives in dropped sparks and may need migration later.
- A future automata daemon is feasible only as scan-first/read-first supervisor; pure event-driven monitoring is unsupported by current artifacts/locks.
- Writer/subagent coordination was noisy; a speculative decision-recorder issue was parked under dropped as over-routed.
- Instance-counting beats prose review: .arca/scheduler/graph/ and ipc/ have zero files behind ~250 lines of schema spec - reality vs spec surface was the audit's strongest lever.
- The AGENTS.md TEMP writer/IRC protocol leaked session scaffolding into permanent docs; TEMP blocks need explicit expiry.
- Copy-based mirroring drifted 3x in under a week; pointer-while-developing + publish-once-at-gate matches the house regen pattern.
- BRAIN_CONV points at a bare legacy store (E:/repos/brain/conv) and hijacks CLI store resolution - always pass --conv-root for this project store.

## decisions
1. Local graph filename is `.arca/scheduler/graph/issue-dep-graph.json`; global registry is `.arca/scheduler/graph/registry.json`; dash-separated keys include `ready-for-test`, `blocked-by`, `source-kind`, `source-id`, `source-path`.
2. `registry.json` is a flat map keyed by dash-id; concrete issue entries carry source-kind/source-id/source-path; virtual entries carry source-kind/source-id and omit fake source-path.
3. `ratmac-ratio` owns only SPEC/DESIGN output and does not discover/check TEST owner, self-block on missing ratmac-ianitor, or file a dependency spark merely because TEST owner is missing.
4. Lifecycle-state-machine and scheduler-vision concerns were merged into i-ratmac-automata; old issue dirs moved under dropped/ with backup links from the new automata issue.
5. Automata runtime/daemon delivery is delayed; current operation remains manual/agent-triggered while the model is unsettled.
6. Formal `scale` wording is rejected in i-ratmac-automata; use neutral owner/current-state owner wording there for now.
7. `ratmac-ratio` may manage multiple issues per active grilling thread, but every target issue must be explicit and out-of-scope behavior/design routes to another issue.
8. SPEC/DESIGN sign-off is issue-qualified when multiple issues are active/pending: `SPEC signed off: <issue-id>` / `DESIGN signed off: <issue-id>`; bare forms only bind when exactly one issue is active/pending.
9. RV-1 accepted (2026-07-02): the graph/registry subsystem is controlled by ratmac-automata, not ratmac-ratio. Schemas (content of DECISION #30-34, #39-43, #51-54) migrate to i-ratmac-automata/sparks.md; ratio docs keep one blocked-routing paragraph (reason in own sparks.md, status blocked, explicit reconcile to unblock); a batched DECISION entry supersedes the residency portions.
10. RV-2 accepted (2026-07-03): de-mirror SKILL.md/REFERENCE.md immediately (executed - rules replaced by contract pointers, STATE.md refs fixed, executing #35); continuous mirroring replaced by a one-time publish step at DESIGN sign-off; batched DECISION entry encodes both.
11. Review-pass protocol: findings are ruled one by one by the user; statuses flip in review.md immediately; DECISION entries and artifact surgery batch at end of pass.
