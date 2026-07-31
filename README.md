# RelaxinPPL

Static analysis notes for Relaxin jailbreak IPA **v0.3.4(0)** PPL device gate.

## Phase 2 result (summary)

**A14/PPL/Coruna support code is present in the binary and UI-gated**, not absent.

- Phase 2 (strings/symbols): [docs/phase2-ppl-gate-static-analysis.md](docs/phase2-ppl-gate-static-analysis.md)
- Phase 2b (disassembly): [docs/phase2b-ppl-gate-disassembly.md](docs/phase2b-ppl-gate-disassembly.md)
- Phase 3 (THEORETICAL/EDUCATIONAL gate analysis — no patching): [docs/phase3-theoretical-gate-analysis.md](docs/phase3-theoretical-gate-analysis.md)
- Phase 4 (layouts / finalize statefulness / self-checks — read-only): [docs/phase4-layout-finalize-selfchecks.md](docs/phase4-layout-finalize-selfchecks.md)
- Phase 5 (finalize failure paths / byte-level layouts / Dopamine cross-ref — read-only): [docs/phase5-finalize-paths-and-layout-note.md](docs/phase5-finalize-paths-and-layout-note.md)
- Developer enable proposal (for a tester with a disposable device): [docs/developer-enable-proposal.md](docs/developer-enable-proposal.md)
- Phase 6 (0.3.4 → 0.3.8 beta PPL residual-risk diff — read-only): [docs/phase6-diff-038-ppl-residual-risks.md](docs/phase6-diff-038-ppl-residual-risks.md)

Phase 2b confirms: in **0.3.4**, `isPPLDevice` fed a UI gate around an already-present A14/Coruna engine path. Phase 5 documented layout/finalize residual risks. Phase 6 finds those engine risks **still present in 0.3.8 beta**; official PPL enablement there is primarily **removal of the UI gate** (`startEngine()` with no bypass flag), not a distinct A14 layout or destroy-on-failure redesign.

## Fathom (theoretical scaffold)

Independent design sketch — **not** a Relaxin IPA rebuild and **not** a working jailbreak:

- [fathom/README.md](fathom/README.md)
- Developer note: [fathom/docs/DEV_HANDOFF.md](fathom/docs/DEV_HANDOFF.md)

## Safety

Read-only analysis / theoretical scaffolds only unless explicitly agreed. No patching / re-signing / on-device experiments by default. No exploit payloads.

## Local binaries

`Payload/` and downloaded IPA/zip are gitignored. Place extracted IPA contents locally for further analysis.
