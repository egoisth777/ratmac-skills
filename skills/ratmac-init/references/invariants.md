# ratmac invariants (R1–R18)

Locked rules for the ratmac-skills family. Inline copy (resilient to spec moves). Source spec: `brain/buf/sparks/pdrft-brain-v3/s-ratmac-skills/invariants.md`.

- **R1 — canonical location.** `E:/packs/skills/ratmac-skills/`. Symlinked into `~/.claude/skills/`. Single source per machine.
- **R2 — scheduler is upstream authority.** Skills automate the scheduler data model defined in `s-scheduler`. Scheduler invariants S1–S20 govern; skills enforce them via `ratmac-lint`.
- **R3 — 11 skills, frozen set.** `init, route, kickoff, checkpoint, mutate, scope, close, transit, regen, lint, auto`. Adding a 12th requires bumping this invariant + spec revision.
- **R4 — pwsh primary, POSIX shadow.** Every script ships `<verb>.ps1` (canonical) + `<verb>.sh` (shadow at verb parity). Windows is the priority; cross-platform is best-effort.
- **R5 — no skill writes outside scheduler tree.** Skills mutate only files under `brain/scheduler/p-<proj>/`. No edits to `brain/store/`, `brain/spaces/`, source code, or external systems.
- **R6 — generated vs hand-edited boundary.** Skills that write generated content (`ratmac-regen`) only touch `<!-- GENERATED -->`-headed files or `<!-- GENERATED -->...<!-- /GENERATED -->` fenced regions. Outside these, generated-content skills MUST stop and report (S13, S20 enforcement).
- **R7 — output contract uniform.** Every skill returns the contract template defined in `ratmac-init/references/output-contract.md`. No ad-hoc formats.
- **R8 — composition declared in description.** Skills declare composes-after / composes-before in SKILL.md description body. Agent uses descriptions to dispatch.
- **R9 — read before write.** Every write skill reads the relevant `state.md` first; if `time-modified` is newer than the in-memory snapshot, STOP and report concurrent-edit risk.
- **R10 — idempotent regen.** `ratmac-regen` is byte-idempotent on stable inputs. Re-run produces identical output. Used as drift detector.
- **R11 — lint never writes.** `ratmac-lint` is read-only; reports only. `--strict` raises severity but does NOT auto-fix.
- **R12 — auto orchestrator stops on ambiguity.** `ratmac-auto` stops at the first ambiguous classification, reporting `HUMAN_DECISION_REQUIRED`. Never guesses route.
- **R13 — install modes are mutually exclusive.** A skill is installed via develop OR debug, never both. Switching modes requires uninstall + install.
- **R14 — skill versioning by source repo state.** No version field in SKILL.md. Source-repo git history is canonical version. Symlink installs reflect HEAD.
- **R15 — symlinks preferred; junction fallback for develop only.** Debug mode requires file-level symlinks (no junction equivalent); fail loudly if symlinks unavailable.
- **R16 — no shell=true / inline shell.** All scripts dispatch from .ps1/.sh files. No `subprocess.run(..., shell=True)` patterns. Mirrors brain-ws .scripts/ shim discipline.
- **R17 — POSIX paths in source-of-truth fields.** `time-created`, `time-modified`, log timestamps use ISO `YYYY-MM-DD-HH:MM:SS`. Path strings normalized to forward-slash regardless of platform.
- **R18 — skill self-reference allowed for chaining only.** A skill MAY spawn another skill's script as a subprocess (e.g., close → regen). Skill MAY NOT recursively spawn itself.

## upstream enforcement (R2)

R1–R18 do not define a new data model — they enforce the upstream **S1-S20 scheduler model**
(`brain/buf/sparks/pdrft-brain-v3/s-scheduler/invariants.md`). The scheduler S-invariants are
the authority; the ratmac R-invariants are the automation contract that keeps every skill
faithful to them. Key load-bearing mappings:

- **R5 ⇐ S1 / S8** — writes stay under `brain/scheduler/p-<proj>/`; archive by `mv`, never delete.
- **R6 ⇐ S13 / S20** — generated content lives only in `<!-- GENERATED — do not edit -->`-headed
  residual files and `<!-- GENERATED -->` … `<!-- /GENERATED -->` fences; hand-edits outside.
- **R7 / R8** — uniform output contract + declared composition so the agent dispatches the
  three-tier **proj → slice → task** model (S2) and the four-file task set (S3) correctly.
- **R9 ⇐ S5 / S6** — read `state.md` (mandatory frontmatter, `time-modified` reflects real
  edits) before writing; bump on every state change.
- **R10 ⇐ S13** — residuals/rollups are regenerated, byte-stable, never hand-authored.
- **R11** — lint is the read-only enforcer for S1 (paths), S5 (frontmatter), S6 (stamp bump),
  S7 (naming prefixes), S13 (residual hand-edits), S20 (fence integrity), S15/S16 (one active
  task per `issue:` tag), and dangling `[[t-...]]` links.

`ratmac-lint` is where these S-rules are mechanically checked; the other skills are written so
that following them keeps S1-S20 satisfied by construction.
