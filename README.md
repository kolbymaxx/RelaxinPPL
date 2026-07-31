# RelaxinPPL

Static analysis notes for Relaxin jailbreak IPA **v0.3.4(0)** PPL device gate.

## Phase 2 result (summary)

**A14/PPL/Coruna support code is present in the binary and UI-gated**, not absent.

- Phase 2 (strings/symbols): [docs/phase2-ppl-gate-static-analysis.md](docs/phase2-ppl-gate-static-analysis.md)
- Phase 2b (disassembly): [docs/phase2b-ppl-gate-disassembly.md](docs/phase2b-ppl-gate-disassembly.md)
- Phase 3 (THEORETICAL/EDUCATIONAL gate analysis — no patching): [docs/phase3-theoretical-gate-analysis.md](docs/phase3-theoretical-gate-analysis.md)
- Phase 4 (layouts / finalize statefulness / self-checks — read-only): [docs/phase4-layout-finalize-selfchecks.md](docs/phase4-layout-finalize-selfchecks.md)
- Phase 5 (finalize failure paths / byte-level layouts / Dopamine cross-ref — read-only): [docs/phase5-finalize-paths-and-layout-note.md](docs/phase5-finalize-paths-and-layout-note.md)

Phase 2b confirms: `isPPLDevice` is a one-line `hw.cpufamily` check feeding an early-return UI gate; the A14/M1 physrw + `_kPhysrwGfxA14M1PplLayout` and the Coruna bootstrap are full implementations (no stubs), gated only by the `allowingUntestedPPLDevice` boolean — but the A14 path is fragile and self-labeled untested. Phase 5 shows A13/A14 layout tables differ by one byte (name pointer only) and maps every A14 finalize exit that skips IOGPU teardown.

## Safety

Read-only analysis only unless explicitly agreed. No patching / re-signing / on-device experiments by default.

## Local binaries

`Payload/` and downloaded IPA/zip are gitignored. Place extracted IPA contents locally for further analysis.
