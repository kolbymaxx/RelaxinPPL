# Fathom — best plausible theories (educational)

Derived from read-only analysis of Relaxin `0.3.4` `RelaxinEngine` (arm64e).
None of this is proven on hardware by this scaffold.

---

## T1 — Shared A13/A14 layout is the first honesty problem

**Observation:** `_kPhysrwGfxA13PplLayout` and `_kPhysrwGfxA14M1PplLayout` differ
by one byte (name pointer). All numeric qwords match, including
`pageInfoLinearBase` @ `+0x40` = `0xffffffdc00000000`.

**Theory A (optimistic):** On the exact iOS 17.0–17.3.1 window Relaxin targets,
A13 and A14 really share that PPL/page-info geometry. The duplicate table is
intentional labeling.

**Theory B (pessimistic, default for Fathom):** The A14 table is an unfinished
clone. Walkers that trust `pageInfoLinearBase` and sibling VA windows can
“succeed” into the wrong physical/PPL view, then fail loudly in alias/transact
or panic later.

**Fathom stance:** Layouts are **separate types**. A14 must either:

- pass an explicit `LayoutProvenance.validatedIdenticalToA13` attestation, or  
- supply distinct numeric fields once measured on-device by someone who accepts
  that risk (not this repo).

We do **not** invent alternate A14 VA windows here — fabricating geometry is
worse than admitting “unknown.”

---

## T2 — Retain-until-exit is only safe with exit hygiene

**Observation:** For chip id `5` (A14/M1), finalize unpublished data primitives,
heartbeats `direct-gfx:a14-transaction-retained`, and skips
`physrw_gfx_backend_destroy`. `exploit_deinit` only clears sockets.

**Theory:** Retain across userspace reboot can be valid *if and only if* the
process that owns the IOGPU/direct-gfx transaction is guaranteed to die (or
explicitly destroy) on every path — success, idle (`0x25`), error, and assert.

**Fathom stance:** Model a `GfxLease` with:

- `retainForUserspaceReboot` only when a reboot carrier is armed, and  
- `destroy()` on **all** other exits (RAII / `defer`-shaped API).

“Success retained” without paired process death is treated as a design bug.

---

## T3 — Failure exits are part of the privilege surface

**Observation:** Rocket states `1`/`4`, status `0x25` handling, and reboot-task
carrier discard do not call backend destroy.

**Theory:** Most “untested PPL” pain is not the happy path — it’s the first
assert after partial alias installation.

**Fathom stance:** Every stage returns a `StageResult`. The engine’s `run`
wrapper holds the lease and releases on any non-`.continueRebootRetain`.

---

## T4 — Historical dmaFail constants are a different layer

**Observation:** Dopamine-era A14 `gGFXBase = 0x23B7003D0` (etc.) are absent
from RelaxinEngine. dmaFail was fixed ~iOS 16.6.

**Theory:** Relaxin’s Coruna/direct-gfx path is not “Dopamine tables pasted into
a PPL layout blob.” Blindly injecting old MMIO bases into `pageInfoLinearBase`
slots would be a category error.

**Fathom stance:** Keep a `HistoricalDmaFailHints` table **labeled historical /
wrong layer** for contrast in code review only. The live PPL layout type does
not accept those values.

---

## T5 — What “maybe” actually means

A credible A14 maybe is not “policy bool true.” It is approximately:

1. Geometry attested (T1),  
2. Lease destroyed on every non-retain exit (T2–T3),  
3. Build/offset self-checks failing closed **before** mutation (engine already
   tries; Fathom makes the ordering explicit),  
4. Disposable-device validation by someone else — out of scope here.

Until (1)–(3) are real in a private tree that owns a primitive, Fathom stays
stubs-only.
