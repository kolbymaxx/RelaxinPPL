# Phase 3 — THEORETICAL / EDUCATIONAL Gate Analysis (Read-Only)

> **STATUS: THEORETICAL / EDUCATIONAL ONLY.**
> Nothing here is applied. No binary is modified, no IPA is repacked, no
> re-signing is described. This document exists to *study* how an early
> software gate is expressed in a compiled arm64e binary and why "the code
> exists" is not the same as "safe to run." The byte encodings below are
> reproduced from read-only disassembly purely to make the analysis concrete;
> they are **not** an install recipe.

Target: Relaxin `0.3.4(0)`, `Relaxin` main executable (arm64e, PIE, image base `0x100000000`).
File offset of any VA below = `VA − 0x100000000`.

---

## 1. The exact decision point

Function: `Relaxin.HomeView.startEngine(allowingUntestedPPLDevice:)`
Symbol: `_$s7Relaxin8HomeViewV11startEngine25allowingUntestedPPLDeviceySb_tF`
Entry: **`0x100030ac0`** (file `+0x30ac0`).

The gate is a three-branch funnel near the end of the target-confirmation block. All three "allow" branches jump to the **same** engine-start label `0x100030e44`:

```
; x19 = self/coroutine frame; [x19,#0x58] = the allowingUntestedPPLDevice arg (stored on entry)
0x100030de0  bl   isPPLDevice            ; -> w0 = (!sim && cpu∈{A13,A14/M1})
0x100030df0  tbz  w0, #0, 0x100030e44    ; (A) not a PPL device -> START ENGINE
             ... build DeviceInfo/log record ...
0x100030e28  ldrb w8, [x19,#0x103]       ; (B) "already confirmed / re-entry" flag
0x100030e2c  tbnz w8, #0, 0x100030e44    ;     set -> START ENGINE
0x100030e30  ldr  w8, [x19,#0x58]        ; (C) allowingUntestedPPLDevice
0x100030e34  tbnz w8, #0, 0x100030e44    ;     true -> START ENGINE (the bypass)
0x100030e38  mov  x20, x21
0x100030e3c  bl   presentPPLJailbreakGate ; else -> show "Unsupported" dialog
0x100030e40  b    0x10003140c            ;        and return (no engine start)
0x100030e44  str  x23, [x19,#0x58]       ; <== ENGINE START PATH
```

Exact enforcing instructions (VA, file offset, little-endian word):

| Role | VA | File off | Bytes (LE word) | Instruction |
|------|----|----------|-----------------|-------------|
| PPL test result | `0x100030de0` | `+0x30de0` | `97ff8950` | `bl isPPLDevice` |
| Skip-if-not-PPL | `0x100030df0` | `+0x30df0` | `360002a0` | `tbz w0,#0,+0x54` |
| Skip-if-confirmed | `0x100030e2c` | `+0x30e2c` | `370000c8` | `tbnz w8,#0,+0x18` |
| **Skip-if-bypass** | `0x100030e34` | `+0x30e34` | `37000088` | `tbnz w8,#0,+0x10` |
| Enter gate UI | `0x100030e3c` | `+0x30e3c` | `9400017c` | `bl presentPPLJailbreakGate` |

And the predicate it depends on, `JailbreakTarget.isPPLDevice` @ **`0x100013320`**:

```
0x100013320  ldrb w8,[x20,#0x14]         ; isSimulator flag
0x100013324  cmp  w8,#1
0x100013328  b.ne 0x100013334
0x10001332c  mov  w0,#0 ; ret            ; simulator -> false
0x100013334  ldr  w8,[x20,#0x10]         ; cpuFamily
0x100013338  mov  w9,#0x462504D2         ; A13
0x100013340  cmp  w8,w9
0x100013344  mov  w9,#0x1B588BB3         ; A14/M1
0x10001334c  ccmp w8,w9,#4,ne
0x100013350  cset w0,eq                  ; true iff cpu∈{A13,A14/M1}
0x100013354  ret
```

**Enforcement is exactly one taken/not-taken decision:** whether control reaches `bl presentPPLJailbreakGate` (`0x100030e3c`) or falls into the engine-start label (`0x100030e44`). Everything else is data feeding that branch.

---

## 2. Theoretical minimal-patch options (NOT applied)

Each is described only to understand the *shape* of the gate. "Clean always-allow" means it forces the supported path unconditionally; "conditional" means behavior still depends on runtime data.

### Option A — Force the argument true at the call site *(not in this function)*
- **Idea:** the gate is skipped when `[x19,#0x58]` (the `allowingUntestedPPLDevice` bool) is non-zero. The value originates at each **caller** of `startEngine`. Forcing the caller to pass `true` would skip the gate.
- **Edit size/kind:** change the constant that materializes the argument at the caller (typically one `mov w?, #0` → `mov w?, #1`, 4 bytes) — but there are multiple callers, so it is **not** a single-site change.
- **Clean vs conditional:** clean "always allow" only if *every* caller is changed; otherwise partial.
- **Static side effects:** the app already reaches this state via the volume-sequence bypass, so this only removes the manual step; no new code path is created.

### Option B — Neutralize the "enter gate" branch (the classic NOP)
- **Idea:** the only instruction that diverts a gated PPL device away from the engine is `bl presentPPLJailbreakGate` at `0x100030e3c`. If that call and the following `b 0x10003140c` (early return) are turned into no-ops, control falls straight into `0x100030e44`.
- **Edit size/kind:** ~2 instructions (8 bytes) replaced with `nop` (`1f2003d5`). Conceptually the smallest "always allow" in terms of decision logic.
- **Clean vs conditional:** clean always-allow for the *UI*, but it removes the user's warning entirely — worse from a safety standpoint, because the "untested" consent screen never appears.
- **Static side effects:** the branch at `0x100030df0`/`0x100030e2c` still work; only the final "else" arm changes. `x20`/`x21` bookkeeping just before the call becomes dead but harmless.

### Option C — Invert / force `isPPLDevice`
- **Idea:** make `isPPLDevice` (`0x100013320`) always return 0, so the very first `tbz w0,#0` at `0x100030df0` takes the "not a PPL device" path to the engine.
- **Edit size/kind:** replace the function prologue with `mov w0,#0` (`52800000`) + `ret` (`d65f03c0`), 8 bytes; or flip the final `cset` condition.
- **Clean vs conditional:** clean "always allow," but **global** — `isPPLDevice` is also read by logging/telemetry and by `startEngine`'s record-building block (`0x100030df4…`), so forcing it false would make the app mislabel the device as non-PPL everywhere, not just at the gate.
- **Static side effects:** the device/SoC log record (`socDescription`, `profileDescription`) would report the wrong classification; any other consumer of `isPPLDevice` is affected.

### Which is "smallest"?
- **Fewest decision bytes:** Option B (one call site).
- **Most surgical semantically:** Option A (uses the code's own intended bypass variable), but multi-site.
- **Worst for safety:** Option B/C both *remove the "has not been tested" consent screen*, which is the opposite of what a cautious learner would want. The app's own design (volume-sequence → confirmation alert) is actually the "safest" way the authors left the door — it forces an explicit warning.

> **All three are documented only to illustrate how a single boolean funnel is compiled. None is applied, and see §4 for why even a "correct" patch would not make the run safe. Also note (educational): this is an arm64e binary — pointer-authentication (`pacibsp`/`retab`/`blraa`) and code-signing/AMFI mean the on-disk bytes are not freely modifiable and re-execution would require defeating signature enforcement, which we are explicitly not doing.**

---

## 3. Success path after a hypothetical bypass (A14 device)

Once control reaches `0x100030e44`, an A14/M1 device runs the **same** engine pipeline as a supported device. Traced from the disassembly:

```
startEngine (engine-start label 0x100030e44)          [Relaxin main app]
  └─ JailbreakTarget.confirmedManifest → RLXEngine manifest keys
        │  (targetDeviceIdentifier, targetCPUFamily, runtimeProfile)
        ▼                                              [RelaxinEngine]
  RLXKernelAccess:
    physrw_early_gfx_bootstrap  (0x5efd8)
      ├─ physrw_coruna_* : create_voucher → prepare_fileport_fd
      │                    → task-anchor → resolve_self_task (kobject/early kread)
      ├─ physrw_early_kernel_roots_resolve / _publish
      └─ physrw_gfx_bootstrap  (0x678f0)
           ├─ physrw_gfx_protection_mode_for_chip
           ├─ physrw_gfx_runtime_is_supported          ← runtime self-check
           ├─ physrw_gfx_ppl_runtime_is_supported (0x6858c) ← runtime self-check
           ├─ physrw_gfx_resolved_offsets_are_valid    ← runtime self-check
           ├─ physrw_gfx_layout_for_chip → _kPhysrwGfxA14M1PplLayout (0xa1080)
           └─ physrw_gfx_bootstrap_ppl_backend → resolve_ppl_state → build_alias_window
       A14/M1 PPL read/write:
         physrw_gfx_prepare_a14_m1_control_data_alias (0x70544)
           └─ physrw_gfx_find_a14_m1_custom_root_pte (0x71550)   ← multi-level PT walk
         physrw_gfx_transact_a14_m1_ppl_control_pte (0x753fc)
           ├─ prepare_common_control_records / trigger_sptm_records
           ├─ dispatch_sptm_fallback
           └─ request_framebuffer_power / wait_timeout / release_owned_kernel_page
  a14_kernel_access_finalize  →  RLXKernelAccess.finalizeAccess (0x7da10)
     └─ rlx_finalize_rocket_runtime (0x7ca38) / kernel_exploit_finalize_handoff (0x5ab08)
  → RLXBootstrapFinalizer.finalizeBootstrap (bootstrap install)
```

### Risky parts (flagged straight from strings/disassembly)
- **`a14_kernel_access_finalize`** — instrumentation strings state:
  - `phase=a14_kernel_access_finalize begin; reboot carrier is suspended`
  - `phase=a14_kernel_access_finalize status=0; IOGPU transaction retained until process exit`
  - error: `Rocket could not retire the A14/M1 process-local access callbacks after launchd accepted the handoff.`
  → the A14 path deliberately **pins an IOGPU transaction and suspends the reboot carrier**. A failure between "begin" and a clean retire is exactly the boot-loop/instability window.
- **`physrw_gfx_transact_a14_m1_ppl_control_pte`** — touches live PPL control PTEs with an SPTM trigger + fallback and a `wait_timeout`; a mis-timed or mis-resolved transaction writes to protected page-table state.
- **Coruna** — `voucher leak prepared…` shows an intentional voucher/port leak; `task_anchor_close_fds` is the only cleanup, and only runs on the paths that call it.

### Remaining runtime self-checks that can still abort (even after bypass)
- `physrw_gfx_ppl_runtime_is_supported` (`0x6858c`): returns false unless backend flag `+0xb8` is clear **and** `backend->[+0x98] ≥ packed_xnu_version`. On a mismatch it aborts before any PPL write.
- `physrw_gfx_runtime_is_supported` and `physrw_gfx_resolved_offsets_are_valid`: gate on whether XPF/pattern resolution produced valid offsets for the live kernelcache.
- Engine C is compiled `-O0` with `__assert_rtn` precondition asserts left in (e.g. `backend->chip == PHYSRW_GFX_CHIP_A14_M1`, `(page.physicalAddress & PHYSRW_GFX_PAGE_MASK) == 0`): a violated invariant **`abort()`s the process** rather than degrading gracefully.

**Consequence:** flipping the UI gate does **not** guarantee the engine proceeds — it may (a) abort safely at a self-check, (b) `abort()` on an assert, or (c) proceed and hit the fragile finalize window. Only (a)/(b) are "safe failures."

---

## 4. Risk summary (what static analysis already revealed)

Concrete failure modes visible without ever running anything:

1. **Boot-loop class:** IOGPU transaction retained + reboot carrier suspended in `a14_kernel_access_finalize`; a failed retire leaves kernel/GPU state pinned.
2. **Protected-memory corruption class:** `transact_a14_m1_ppl_control_pte` writes PPL control PTEs; wrong offsets → writes to the wrong physical page.
3. **Hard abort class:** `-O0` `__assert_rtn` on any violated precondition kills the process mid-operation (state may be half-applied).
4. **Resource-leak class:** Coruna voucher/port leak by design; cleanup only on specific paths.
5. **Offset-mismatch class:** XPF/pattern resolution (`resolved_offsets_are_valid`, `ppl_runtime_is_supported`) may not have been validated against iPhone13,1 / Darwin 23.3.0 — the "untested" label is literal.

### Why "the code exists" ≠ "safe to run"
- **Presence ≠ validation.** The A14/M1 layout, page-table walk, and transaction are *complete*, but completeness says nothing about whether the **offset tables were verified on this exact SoC + kernelcache**. The authors gated it precisely because that validation isn't done.
- **A gate is a policy statement, not a capability statement.** `isPPLDevice`/`allowingUntestedPPLDevice` encode "we don't vouch for this," not "this can't work." Removing the policy doesn't add the missing validation.
- **Failure is stateful.** Unlike a pure computation, this path mutates kernel page tables and holds GPU transactions; a wrong guess isn't a clean error return — it can leave the device unbootable.

### Additional static checks wise *before* anyone ever considered a real patch
1. **Field-diff `_kPhysrwGfxA13PplLayout` vs `_kPhysrwGfxA14M1PplLayout`** — confirm the A14 masks/offsets are genuinely A14-derived, not a copy of A13.
2. **Disassemble `RLXKernelAccess.finalizeAccess` + `rlx_finalize_rocket_runtime`** — enumerate exactly what is released vs retained on both success and every failure branch (does a failure path *always* retire the IOGPU transaction?).
3. **Trace the inputs to `physrw_gfx_ppl_runtime_is_supported`** (`+0x98`, `+0xb8`) back to their producers — learn what real conditions on iPhone13,1 make it abort-safe vs proceed.
4. **Map every `__assert_rtn` site on the A14 path** — assert that failures land *before* any protected write, not after a partial mutation.
5. **Confirm XPF pattern coverage** for the target kernelcache build (23.x) — unresolved offsets are the leading cause of "wrong write" corruption.

Only after all five would the risk even be *characterizable*; none of it involves modifying the binary.

---

## 5. What I learned about binary gates and risk (study summary)

- **A gate is usually one branch.** Even a scary "Unsupported" wall often compiles down to a single `tbz/tbnz` deciding between a UI call and the real work label. Finding that one branch is most of reverse-engineering a gate.
- **The predicate is separable from the policy.** `isPPLDevice` (a `hw.cpufamily` compare) is *facts*; `allowingUntestedPPLDevice` is *policy*. Gates layer a cheap fact-check under a boolean override — which is why "flip one bool" feels tempting and is exactly why it's dangerous.
- **Where the bool comes from matters more than the branch.** The cleanest conceptual change (force the argument) is multi-site; the smallest byte change (NOP the else-arm) also deletes the user's safety warning. "Minimal" and "safe" are different axes.
- **Self-checks can outlive the gate.** Good exploit code re-verifies capability at the engine layer (`*_runtime_is_supported`, `resolved_offsets_are_valid`, asserts). So bypassing the UI doesn't bypass correctness — it just changes *who* says no and *how loudly* (clean return vs `abort()` vs corruption).
- **Statefulness is the real risk multiplier.** Gates in front of pure functions are low-stakes to study; gates in front of kernel-page-table mutation + retained GPU transactions are not, because the failure mode is a bricked boot, not an error dialog.
- **Modern hardening changes the whole calculus.** arm64e PAC + code signing/AMFI mean the on-disk bytes aren't a free text field: a "theoretical" patch and an actually-loadable one are separated by signature enforcement, which is its own reason to keep this purely analytical.

> Reiterating: **THEORETICAL / EDUCATIONAL. No patch applied, no IPA produced, no re-signing. Binaries were only read.**
