# Fathom

**Theoretical research scaffold** for an iOS 17.x A14/PPL *pipeline shape*,
derived from static observations of Relaxin `0.3.4`’s public binary layout —
not a fork of their sources, and **not a working jailbreak**.

> **Non-goals (hard):** no runnable IPA, no kernel r/w primitive, no IOGPU /
> Coruna exploit payload, no on-device instructions, no resign recipe.
> Kernel-touching entry points are stubs that return `.unimplemented`.

Fathom exists so a developer can read one place that says:

1. what Relaxin-shaped stages look like conceptually, and  
2. which **plausible** changes (layout honesty, finalize teardown, exit hygiene)
   would need to be true before “PPL support” is more than a UI maybe.

If you want the observational risk note for upstream authors, see
`../docs/phase5-finalize-paths-and-layout-note.md` in this repo.

---

## Name

**Fathom** — measure the depth before you dive. The gated path looks complete
in a binary; the depth is in geometry, retain semantics, and failure exits.

---

## What’s in here

| Path | Role |
|------|------|
| `docs/THEORY.md` | Best plausible theories (layout / finalize / exits / constants) |
| `docs/DEV_HANDOFF.md` | Short note you can forward to a developer |
| `Sources/FathomCore/` | Chip IDs, layout tables, validation |
| `Sources/FathomEngine/` | Staged pipeline + finalize state machine (stubs) |
| `Package.swift` | SwiftPM package so the stubs typecheck on macOS/Linux |

Build (typecheck only):

```bash
cd fathom && swift build
```

---

## Relationship to Relaxin / Dopamine

- **Relaxin** appears to be a closed IPA with a Coruna/direct-gfx shaped engine
  and a UI policy gate around PPL devices. We do **not** redistribute or patch
  that IPA here.
- **Dopamine** is open source and historically used `dmaFail` (fixed ~iOS 16.6).
  Those per-chip GFX MMIO constants are cited in THEORY as *contrast*, not as
  copy-paste fuel for an iOS 17 Coruna path.
- **Fathom** is an independent sketch: same *stage concepts* (target → early
  roots → gfx bootstrap → ppl alias/transact → finalize/reboot), with our
  residual-risk theories encoded as APIs and comments.

---

## License / use

Educational / design discussion only. Do not treat this tree as permission or
capability to run privileged code on anyone’s device.
