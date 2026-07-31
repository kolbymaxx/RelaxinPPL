# Fathom — note for a developer

This folder is a **theoretical scaffold**, not a Relaxin rebuild and not an IPA.

**Why it exists:** static analysis of Relaxin 0.3.4 suggested the gated A14/PPL
path’s residual risk is less “missing symbols” and more:

- A14 layout numerics identical to A13 (name-only diff)
- finalize retains IOGPU/direct-gfx and skips normal destroy
- several failure exits also skip destroy
- public dmaFail A14 MMIO constants are not in that binary (and are a
  different OS-era layer anyway)

**What Fathom encodes:** those concerns as types and a staged pipeline with
stubbed privilege ops (`unimplemented`). The interesting bits to skim:

- `PplLayout.swift` — refuses silent A13→A14 clones without attestation  
- `GfxLease.swift` — retain only for reboot; destroy on every other exit  
- `EnginePipeline.swift` — ordered stages + lease hygiene  

**What it deliberately omits:** any real Coruna/IOGPU/PTE primitive, any patch
to Relaxin’s IPA, any run instructions.

If you already own a private engine: treat Fathom as a checklist shaped like
code. If you don’t: this is not a substitute.
