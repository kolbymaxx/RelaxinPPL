# Phase 2b – Disassembly of PPL Gate, A14/M1 physrw, and Coruna path

**Build:** Relaxin `0.3.4(0)` · arm64e · `com.aapl.relaxin`
**Mode:** strictly read-only disassembly (llvm-objdump / capstone / llvm-nm). No patches.
**Toolchain note:** both `Relaxin` (main app) and `RelaxinEngine` shipped with **debug symbol tables** (STABS/`FUN`), so every function below is named. The engine C code (`physrw_gfx_*`, `physrw_coruna_*`) is compiled at **-O0 with `__assert_rtn` precondition asserts left in** — i.e. a checked/dev build, which is why the disassembly is verbose but easy to read.

CPU family constants referenced throughout:
`A13=0x462504D2`, `A14/M1=0x1B588BB3`, `A15=0xDA33D83D`, `A16=0x8765EDEA`, `A17=0x2876F5B5`.

---

## 1. `JailbreakTarget.isPPLDevice` + `PPLJailbreakGate` check

### `isPPLDevice` — `Relaxin` @ `0x100013320`

```
ldrb  w8, [x20, #0x14]      ; DeviceInfo.isSimulator (or invalid flag)
cmp   w8, #1
b.ne  check_cpu
mov   w0, #0 ; ret           ; simulator  -> NOT a PPL device
check_cpu:
ldr   w8, [x20, #0x10]       ; DeviceInfo.cpuFamily
cmp   w8, #0x462504D2        ; A13
ccmp  w8, #0x1B588BB3, #4, ne; A14/M1
cset  w0, eq                 ; true iff A13 OR A14/M1
```

**Verdict: full implementation, trivial predicate.** `isPPLDevice == (!isSimulator) && (cpuFamily ∈ {A13, A14/M1})`. iPhone 12 mini (A14 = `0x1B588BB3`) → **true**. No model-string check; purely `hw.cpufamily`.

### `startEngine(allowingUntestedPPLDevice:)` — `Relaxin` @ `0x100030ac0`

Relevant gate region (after target confirmation / manifest build):

```
0x100030de0  bl   isPPLDevice
0x100030df0  tbz  w0, #0, +engine_start   ; not PPL -> start engine directly
             ...
0x100030e28  ldrb w8, [x19,#0x103]        ; some already-confirmed flag
0x100030e2c  tbnz w8, #0, +engine_start
0x100030e30  ldr  w8, [x19,#0x58]         ; <- the allowingUntestedPPLDevice arg
0x100030e34  tbnz w8, #0, +engine_start   ; bypass=true -> start engine
0x100030e3c  bl   presentPPLJailbreakGate ; else show "Unsupported" and return
0x100030e40  b    return
engine_start (0x100030e44): str x23,[x19,#0x58]; ... proceeds to RLXEngine
```

**Verdict: this is an early-return UI/policy gate, not a capability gate.** If `allowingUntestedPPLDevice == true`, the PPL branch is skipped and the engine start path runs unchanged — the same code path a non-PPL device takes.

### `presentPPLJailbreakGate` — `Relaxin` @ `0x10003142c`
- Resolves key-window presenter; if none, bails (`0x1001141e4`).
- Builds localized `Unsupported` title + `Jailbreaking PPL devices is not currently supported.` message.
- Allocates `PPLJailbreakGate` with a completion closure (`init` @ `0x100114208`) and calls `present()` (`0x100113f08`).

### `PPLJailbreakGate` hidden bypass (all full implementations)
- `present()` @ `0x100113f08` → shows the alert and calls `beginObservingVolume` (KVO on `AVAudioSession.outputVolume`).
- `handleVolumeChange(_:)` @ `0x100114c84` → classifies each change as an expected endpoint (compares against two float thresholds at `0x10012b8f8/8fc`) then calls `confirmExpectedEndpoint`.
- `confirmExpectedEndpoint()` @ `0x100115318`:

```
ldrb w8,[x20,#0x40]           ; expected-state
cmp  w8,#1
b.ne set_state_1
ldr  x8,[x20,#0x48]; add +1   ; completedRoundTrips++
cmp  x8,#3
b.gt reveal                   ; >3 round-trips -> revealBypassConfirmation
strb wzr,[x20,#0x40]          ; else reset
```

- `revealBypassConfirmation()` @ `0x100115358` → `presentBypassConfirmation()` @ `0x1001156cc` → alert `Bypass PPL Device Check?` + warning `Jailbreaking PPL devices has not been tested…`.
- `finish(shouldBypass:)` @ `0x100114634` → sets `isFinished`, stops volume KVO, invokes the stored completion with the `shouldBypass` bool.

The completion is the closure captured in `presentPPLJailbreakGate`; when `shouldBypass == true` it re-enters `startEngine(allowingUntestedPPLDevice: true)`.

**Section verdict:** the gate is a **fully implemented UI state machine** requiring **4 volume-endpoint round-trips** to reveal a bypass that flips one boolean argument. No missing pieces; nothing “stubbed.”

---

## 2. A14/M1 physrw + layout helpers (`RelaxinEngine`)

### `physrw_gfx_chip_for_cpu_family` @ `0x765f8`
Pure switch, `hw.cpufamily → chip enum`: `A15→1, A16→2, A17→3, A13→4, A14/M1→5, unknown→0`. **Full impl.**

### `physrw_gfx_layout_for_chip` @ `0x76538`
Switch returning pointers into `__const` at `0xa1000`:

| chip enum | layout ptr | symbol |
|-----------|-----------|--------|
| 4 (A13) | `0xa1020` | `_kPhysrwGfxA13PplLayout` |
| **5 (A14/M1) → default** | **`0xa1080`** | **`_kPhysrwGfxA14M1PplLayout`** |
| 1 (A15) | `0xa10e0` | `_kPhysrwGfxA15Layout` |
| 2 (A16) | `0xa1140` | `_kPhysrwGfxA16Layout` |
| 3 (A17) | `0xa11a0` | `_kPhysrwGfxA17Layout` |
| 0 | null | (unknown) |

**Important:** A14/M1 (chip 5) falls through to the **default** case, which returns the **real, populated** `_kPhysrwGfxA14M1PplLayout`. Dumped bytes (non-zero PTE masks):

```
+00: 0e2f0900 00006000 00000506 02000000
+10: feffffff 0f000000 00000000 80ffffff
+20: 00000000 a0ffffff 00000200 a0ffffff
...  (mask/offset table, identical shape to the A13 layout)
```

So the A14/M1 layout is **present and non-null**, not a stub. **Full impl.**

### `physrw_gfx_prepare_a14_m1_control_data_alias` @ `0x70544`
- Asserts `backend != NULL`, `backend->chip == PHYSRW_GFX_CHIP_A14_M1` (`__assert_rtn`), then real work:
  - `physrw_gfx_allocate_owned_kernel_page`
  - `physrw_gfx_find_a14_m1_custom_root_pte`
  - `physrw_gfx_build_alias_window`, diagnostic logging (`gfx:alias-a14-control-data-*`).
- Returns a status byte (12 = `PHYSRW_GFX_STATUS_*` on the “page not present” early exit; success continues). **Full impl.**

### `physrw_gfx_find_a14_m1_custom_root_pte` @ `0x71550`
- A genuine **multi-level ARM64 page-table walk**: masks `& 0xffffffffc000`, level shifts `>>0x16`, `>>0xb`, `& 0x3ff8`, per-level descriptor reads via signed function pointers (`blraaz`), logging each phase (`phase=root / l2-resolve / l2-entry / l3-resolve / l3-entry`).
- On every failure it logs (`physrw_gfx_diagnostic_printf`) and returns **false**; on success writes the resolved PTE pointer/value to the out-params and returns **true**. **Full impl** (no early “return true” shortcut, no TODO).

### `physrw_gfx_transact_a14_m1_ppl_control_pte` @ `0x753fc`
- Asserts inputs, then orchestrates the real transaction:
  `prepare_common_control_records` → `trigger_sptm_records` → `store64` → `dispatch_sptm_fallback` → `request_framebuffer_power` → `wait_timeout` → `release_owned_kernel_page`, with `physrw_diagnostics_set_suppressed` around the critical window. **Full impl** (31 call sites; real control flow, not a wrapper).

### Engine-side capability check: `physrw_gfx_ppl_runtime_is_supported` @ `0x6858c`
Returns false unless `backend` flags at `+0xb8` clear and `backend->[+0x98] >= packed_xnu_version`. So even after the UI bypass, the **engine independently verifies PPL runtime support** for the resolved offsets before proceeding.

**Section verdict:** the A14/M1 PPL primitives are a **complete, instrumented implementation** (allocate → walk → alias → transact), with a populated layout table and an engine-side support gate. Nothing is stubbed.

---

## 3. Coruna bootstrap / voucher / task-anchor path (`RelaxinEngine`)

### `physrw_coruna_create_voucher` @ `0x586d8`
Builds a `mach_voucher_attr_recipe` (command `7`, key `0xd3` = `MACH_VOUCHER_ATTR_...`, size `8`, payload = arg) and calls the voucher-create wrapper (`0x80cc0`, `0x80b40`). **Full impl.**

### `physrw_coruna_prepare_fileport_fd` @ `0x5873c`
Real fd plumbing via a syscall wrapper (`0x809d0`): `fileport_makeport`-style op then a sequence of `fcntl`/dup operations (`orr #1`, `orr #4`), returning **false** on any `-1` errno. **Full impl.**

### `physrw_coruna_task_anchor_close_fds` @ `0x588bc`
Iterates the 3 fds stored in global `_g_physrwCorunaTaskAnchor` (`0xaabf0`), `close()`s each valid one, resets to `-1`, clears the anchor’s ready byte. **Full impl** (proper cleanup).

### `physrw_coruna_resolve_self_task` @ `0x5e730`
- `kernel_exploit_prepare_task_anchor` → `physrw_coruna_port_kobject` → validates with `physrw_kernel_address_valid` / `physrw_try_kread32/64` → `physrw_decode_copyio_kernel_ptr`; on failure logs and calls `physrw_coruna_task_anchor_close_fds`. **Full impl.**

### `physrw_early_gfx_bootstrap` @ `0x5efd8` / `physrw_gfx_bootstrap` @ `0x678f0`
The orchestrators tie it together:
`protection_mode_for_chip` → `physrw_gfx_runtime_is_supported` → `physrw_gfx_ppl_runtime_is_supported` → `resolved_offsets_are_valid` → `layout_for_chip` → backend bring-up (`bootstrap_ppl_backend` → `resolve_ppl_state` → `build_alias_window`). Coruna is the early-primitive path feeding kernel-root resolution (`physrw_early_kernel_roots_*`).

**Section verdict:** Coruna is a **complete early-exploit primitive layer** (voucher leak → fileport/task-anchor → self-task kobject → early kernel read), with real cleanup on failure. Not stubbed.

---

## 4. Rough control flow AFTER the PPL gate is passed

```
startEngine(allowingUntestedPPLDevice: true)          [Relaxin main app]
  └─ JailbreakTarget.current  (device/CPU/OS/build)
  └─ confirmedManifest → hands RLXEngineManifest keys to RelaxinEngine
        │
        ▼ [RelaxinEngine, C/Obj-C]
  RLXKernelAccess:
    physrw_early_gfx_bootstrap
      ├─ physrw_coruna_* (voucher → fileport → task anchor → self-task)
      ├─ physrw_early_kernel_roots_resolve/publish  (early kread)
      └─ physrw_gfx_bootstrap
           ├─ physrw_gfx_chip_for_cpu_family  → chip 5 (A14/M1)
           ├─ physrw_gfx_ppl_runtime_is_supported  (engine-side gate)
           ├─ physrw_gfx_layout_for_chip → _kPhysrwGfxA14M1PplLayout
           └─ physrw_gfx_bootstrap_ppl_backend → resolve_ppl_state
       A14/M1 PPL read/write:
         prepare_a14_m1_control_data_alias
           └─ find_a14_m1_custom_root_pte (page-table walk)
         transact_a14_m1_ppl_control_pte (trigger/fallback/framebuffer-power)
      a14_kernel_access_finalize  → RLXKernelAccess.finalizeAccess
         └─ rlx_finalize_rocket_runtime / kernel_exploit_finalize_handoff
  → bootstrap install (RLXBootstrapFinalizer.finalizeBootstrap)
```

---

## 5. Safety flags (for Grok / user) — read-only observations

1. **Not a capability gate.** The UI bypass flips `allowingUntestedPPLDevice` to `true` and routes A14 devices into the *same* engine path as supported devices. There is no separate “A14 stub that no-ops.”
2. **Engine still self-gates.** `physrw_gfx_ppl_runtime_is_supported` and `resolved_offsets_are_valid` can still abort on A14 if offsets don’t resolve — so a bypassed run may simply fail rather than proceed.
3. **Fragility signals (genuine risk):**
   - `a14_kernel_access_finalize`: strings state `IOGPU transaction retained until process exit` and `reboot carrier is suspended`, and an error `Rocket could not retire the A14/M1 process-local access callbacks…`. The A14 path deliberately **pins GPU/kernel state** — a failure mid-transaction is exactly the boot-loop/instability class.
   - Assert-heavy `-O0` engine build: `__assert_rtn` on precondition violations will **abort()** the process rather than unwind cleanly.
   - Coruna leaks a voucher/port by design (`voucher leak prepared…`) — resource-fragile.
4. **No literal “TODO”/“NOT IMPLEMENTED”/`return -1` stubs** were found in any of the three areas. The A14 support is real but labeled *untested* by the app itself.

---

## 6. Answer to this step’s question

- **isPPLDevice / gate:** full impl; a one-line CPU-family predicate feeding an early-return UI gate; bypass = one bool.
- **A14/M1 physrw + layout:** full, instrumented impl with a populated `_kPhysrwGfxA14M1PplLayout`; no stubs.
- **Coruna bootstrap:** full early-primitive impl (voucher/fileport/task-anchor/self-task) with real cleanup.

**Overall: the A14/PPL/Coruna support is genuinely present and wired end-to-end, gated only by a UI boolean — but it is a fragile, assert-heavy, self-described “untested” path that pins GPU/kernel state, so “merely gated” does not imply “safe to run.”**

---

## 7. Recommended next static-analysis step (still read-only)

1. Diff `_kPhysrwGfxA13PplLayout` vs `_kPhysrwGfxA14M1PplLayout` field-by-field to confirm the A14 offsets look device-correct (not copied from A13).
2. Disassemble `RLXKernelAccess.finalizeAccess` / `rlx_finalize_rocket_runtime` to see exactly what state is retained vs released on the A14 success and failure paths.
3. Disassemble `physrw_gfx_ppl_runtime_is_supported` inputs (where `+0x98`/`+0xb8` come from) to learn what would make a real iPhone13,1 run *abort safely* vs *proceed*.
4. Only after that: you + Grok decide whether any controlled test is even worth discussing.

### Disassembly artifacts (local, gitignored)
`artifacts/analysis/disasm/*.asm` (per-function), `artifacts/analysis/disasm/gate_syms.txt`.
