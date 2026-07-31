# Developer enable proposal — PPL / A14 gate (Relaxin 0.3.4)

Hand this to someone who can rebuild, resign, or instrument the IPA on a
**disposable** test device. This is an enable/test proposal for code that is
already in the binary — not a claim that A14 is safe.

**Device context of interest:** iPhone 12 mini (`iPhone13,1`), A14, iOS ~17.3.  
**Blocking UI today:** “Unsupported” / “Jailbreaking PPL devices is not currently supported.”

---

## What you are enabling

The UI gate is **policy only**. After bypass, the same engine path runs:

`startEngine(allowingUntestedPPLDevice: true)` → Coruna / `physrw_gfx_*` →
`_kPhysrwGfxA14M1PplLayout` → later userspace-reboot finalize that **retains**
the IOGPU/direct-gfx transaction until process exit.

Static caveats the tester must accept up front:

1. A13 and A14/M1 PPL layout tables differ by **one byte** (name string only).
2. A14 finalize **skips** `physrw_gfx_backend_destroy` on purpose.
3. Engine still has its own asserts / runtime checks after the UI gate.

Use a spare device and expect boot-loop class failure modes if mid-path abort
leaves GPU/PPL state dirty.

---

## Method 1 — Prefer this first: built-in volume bypass (no patch)

The app already ships a hidden enable path. No binary edit, no resign.

### Steps

1. Launch Relaxin on the A14 device; tap through to the unsupported / PPL gate UI.
2. While that gate is up, perform **more than 3 volume endpoint round-trips**  
   (volume up/down to the endstops — the code counts KVO endpoint transitions,
   not casual press counts). Threshold is **`> 3`**.
3. When revealed, confirm the alert: **“Bypass PPL Device Check?”**  
   Warning text: jailbreaking PPL devices has not been tested.
4. On confirm, `finish(shouldBypass: true)` re-enters  
   `startEngine(allowingUntestedPPLDevice: true)`.

### Why this is the best first test

- Uses the authors’ intended override variable.
- Keeps the consent alert (unlike NOP’ing the gate).
- Proves whether failure is “gate” vs “engine/constants/finalize,” which is the
  real question on A14.

### What to capture if it proceeds

- Full on-screen / os_log trail around:  
  `direct-gfx:*`, `a14_kernel_access_finalize`, `IOGPU transaction retained`,
  any `__assert_rtn` / `Bootstrap.c` / `GFXBridge.c` / `Handoff.c` messages.
- Whether it dies in bootstrap, PTE walk (`find_a14_m1_*`), or finalize/reboot.
- Whether a userspace reboot is attempted and whether the device recovers cleanly.

---

## Method 2 — Clean developer enable (if you can rebuild or inject)

If you control a rebuild, debug dylib, or ElleKit/substrate tweak into the app
process, do **not** NOP the warning away. Force the same bool the UI sets.

### Recommended semantic change

At every call site of:

```text
HomeView.startEngine(allowingUntestedPPLDevice:)
```

pass **`true`** for debug/internal builds (or default it true when
`hw.cpufamily` is A14/M1 and a compile flag like `RELAXIN_ALLOW_UNTESTED_PPL=1`
is set).

Still show a one-tap confirmation in debug builds so testers cannot “accidentally”
start the engine.

### Optional debug HUD (high value)

Log before engine start:

- `hw.cpufamily` / mapped chip id (expect A14 → chip `5`)
- selected layout name string (`A14/M1-PPL`)
- results of: `physrw_gfx_ppl_runtime_is_supported`,
  `physrw_gfx_resolved_offsets_are_valid`
- finalize path: `uses_process_exit_cleanup`, handoff heartbeat,
  whether `physrw_gfx_backend_destroy` was skipped

That turns a brick/non-brick run into actionable engineering data.

---

## Method 3 — Binary patch (only if resign/dev signing is already solved)

arm64e + AMFI mean on-disk patches are useless without a signing story you
already have. If you do:

| Priority | Edit | Where | Effect |
|----------|------|-------|--------|
| Best | Force bypass arg / caller `mov` `#0`→`#1` | callers of `startEngine` | Same as Method 1, no volume ritual |
| OK | NOP `bl presentPPLJailbreakGate` + following `b` | `Relaxin` `+0x30e3c` / `+0x30e40` | Always skips UI; **removes consent** — worse |
| Avoid | Force `isPPLDevice` → false | `+0x13320` | Mislabels device globally; muddies logs |

Exact instruction table: `docs/phase3-theoretical-gate-analysis.md`.  
Do **not** patch `RelaxinEngine` layout tables as an “enable” — that is a
different, higher-risk experiment (constants), not a gate bypass.

---

## Suggested test plan for the developer

1. **Method 1 only** on a disposable A14 on 17.0–17.3.1 (engine window from prior analysis).
2. If gate opens and engine starts: stop at first hard failure; collect logs; do not “retry harder.”
3. Classify failure:
   - UI never reveals bypass → volume/KVO issue, not exploit issue.
   - Engine refuses in `ppl_runtime_is_supported` / offsets → runtime gate, not UI.
   - Assert in PTE/alias/transact → A14 path fragile / constants suspect.
   - Finalize retain then reboot trouble → matches static “state left live” finding.
4. Only after Method 1 is understood, consider Method 2 for faster iteration.
5. Treat Method 3 as last resort plumbing.

---

## Explicit non-goals

- Do not “fix the check and see” on a daily driver.
- Do not patch A13 numbers into hoping A14 MMIO matches Dopamine `dmaFail`
  (those public GFX bases are not even present in this engine build).
- Do not equate “engine symbols exist” with “A14 support is finished.”

---

## Pointers in this repo

| Doc | Use |
|-----|-----|
| `docs/phase2b-ppl-gate-disassembly.md` | Gate + volume bypass CFG |
| `docs/phase3-theoretical-gate-analysis.md` | Patch shapes / encodings |
| `docs/phase5-finalize-paths-and-layout-note.md` | Why A14 retain + identical layouts matter after enable |
