# Phase 4 — Educational Static Analysis: Layouts, Finalize Statefulness, Self-Checks

> **Educational / theoretical only. Read-only.** No patches, no on-device
> instructions, no apply-ready diffs. The goal is understanding how a
> chip-specific table and a finalize stage encode risk.

Target: Relaxin `0.3.4(0)`, `RelaxinEngine` (arm64e).

---

## 1. A13 vs A14/M1 layout tables — what actually differs

Both tables live in `__const` and are selected by `physrw_gfx_layout_for_chip`:

| Chip | Symbol | Address |
|------|--------|---------|
| A13 | `_kPhysrwGfxA13PplLayout` | `0xa1020` |
| A14/M1 | `_kPhysrwGfxA14M1PplLayout` | `0xa1080` |

Each table is **0x60 bytes** (24 × `uint32` / 12 × `uint64`). Field-by-field compare:

| Offset | A13 | A14/M1 | Differs? | Meaning (from static context) |
|--------|-----|--------|----------|-------------------------------|
| `+0x00` | `0x00092f06` → `"A13-PPL"` | `0x00092f0e` → `"A14/M1-PPL"` | **YES** | Chip display-name string pointer |
| `+0x04` … `+0x5c` | identical | identical | no | Offset/mask/record fields |

**High-level finding:** A13 and A14/M1 share the **same numeric layout** (page masks, signed offsets, record constants). The only difference is the human-readable name pointer at word 0.

Contrast with later chips (for perspective, not an A14 claim):
- A15: different name pointer; rest matches A13/A14.
- A16/A17: diverge in mask width / address bits and a trailing flag (`+0x58`).

**Educational takeaway:** “Having an A14/M1 layout table” here does **not** mean a fully distinct geometry table. It means “same PPL layout constants as A13, labeled A14/M1.” Whether that is correct for A14 hardware is exactly the kind of unverified assumption the “untested” gate is warning about.

---

## 2. A14 finalize path — what is retained vs released

There is no single C function named `a14_kernel_access_finalize`. That string is a **phase log** inside the userspace-reboot task. The real call chain:

```
-[RLXEngine12UserspaceRebootTask execute]          @ 0x51384
  ├─ if requiresUserspaceRebootFinalization:       (ObjC query on RLXKernelAccess)
  │     log "phase=a14_kernel_access_finalize begin; reboot carrier is suspended"
  │     call -[RLXKernelAccess finalizeAccess]     @ 0x7da10
  │       └─ rlx_finalize_rocket_runtime           @ 0x7ca38
  │            └─ (state 2/3) rlx_deinitialize_rocket_runtime @ 0x7db68
  │                 └─ kernel_exploit_finalize_handoff @ 0x5ab08
  │     on status≠0 (and ≠0x25): rlx_discard_suspended_process
  │     on status==0: log "... IOGPU transaction retained until process exit"
  └─ continue userspace reboot spawn (jbctl reboot_userspace)
```

### The A14-specific branch inside `kernel_exploit_finalize_handoff`

```
kernel_exploit_uses_process_exit_cleanup()
  → true iff exploit-active flag set AND backend->chip == 5 (A14/M1)

if (uses_process_exit_cleanup) {          // A14/M1 path
    kernel_exploit_unpublish_data_primitives();
    heartbeat "direct-gfx:a14-transaction-retained";
    return 0;                             // success WITHOUT destroying backend
} else {                                  // other chips
    physrw_gfx_backend_destroy(...);      // restore alias PTEs, tear down
    assert(retained == 0);
    physrw_gfx_release_cached_protected_descriptors(...);
    kernel_exploit_unpublish_data_primitives();
    heartbeat "a17-direct:data-access-finalized";  // generic non-retain path
    return 0;
}
```

### Retain vs release (learning-focused)

| Asset / state | Non-A14 finalize | A14/M1 finalize (process-exit cleanup) |
|---------------|------------------|----------------------------------------|
| Process-local data primitives (read/write fn ptrs) | **Released** (`unpublish`) | **Released** (`unpublish`) |
| Cached protected descriptors | **Released** | **Not released here** |
| GFX backend / alias PTE restore (`physrw_gfx_backend_destroy`) | **Destroyed / restored** | **Skipped** — intentionally retained |
| IOGPU / direct-gfx transaction | Not retained | **Retained until process exit** (explicit log + heartbeat) |
| Reboot carrier process | N/A in this branch | **Suspended** during finalize; discarded only if finalize fails |
| Rocket runtime state (`_rlx_rocket_runtime_state`) | Cleared on clean deinit | Cleared only if `exploit_deinit` runs after handoff; A14 success path leaves gfx backend alive |

**What “statefulness” means here (educational):**
- On A14, success does **not** mean “everything is cleaned up.” It means “userspace callbacks are unpublished, but the GPU/direct-gfx transaction is left alive and the reboot carrier was suspended while that happened.”
- Cleanup of the retained transaction is deferred to **process exit**, not to the finalize call.
- Failure mid-window (finalize returns non-zero / non-`0x25`) calls `rlx_discard_suspended_process` — a recovery attempt for the carrier — but the retained-transaction design implies that a crash *after* retain and *before* process exit is the fragile window the earlier analysis called boot-loop class.

Related ObjC surface (for orientation only):
- `-[RLXKernelAccess requiresUserspaceRebootFinalization]` — decides whether the A14 finalize phase runs at all during userspace reboot.
- `-[RLXKernelAccess finalizeAccess]` — thin wrapper around `rlx_finalize_rocket_runtime`, then clears some local buffers on success.

---

## 3. Remaining runtime checks that can still stop execution after the UI gate

These are **engine-layer** gates. They still run even if the UI `allowingUntestedPPLDevice` path is taken. Grouped by stage.

### A. Target / manifest confirmation (before physrw)
| Check | Where (conceptually) | Stops when… |
|-------|----------------------|-------------|
| Runtime profile mapping | `JailbreakTarget` / engine `confirm_target` | `hw.cpufamily` has no mapping |
| OS window | same | iOS outside ~17.0–17.3.1 |
| Manifest / device class match | grabkernel / confirm strings | firmware manifest doesn’t match device/build |

### B. Physrw bootstrap preconditions (`physrw_gfx_bootstrap` / early bootstrap)
| Check | Symbol | Stops when… |
|-------|--------|-------------|
| Null / invariant asserts | `__assert_rtn` in `Bootstrap.c` | `bootstrap`, `offsets`, `backendOut`, kernel read/write/vtophys callbacks missing |
| Protection mode | `physrw_gfx_protection_mode_for_chip` | chip unsupported / mode unavailable |
| Generic runtime support | `physrw_gfx_runtime_is_supported` | backend/runtime flags fail |
| **PPL runtime support** | `physrw_gfx_ppl_runtime_is_supported` | PPL-text / version / flag check fails |
| Offset validity | `physrw_gfx_resolved_offsets_are_valid` | XPF/pattern resolution incomplete |
| Layout presence | `physrw_gfx_layout_for_chip` | unknown chip → null layout |
| Backend readiness | `physrw_gfx_backend_is_ready` | bootstrap incomplete |

### C. A14-specific operation checks
| Check | Symbol / assert | Stops when… |
|-------|-----------------|-------------|
| Chip identity | `backend->chip == PHYSRW_GFX_CHIP_A14_M1` | wrong chip on A14-only helper |
| Page alignment | `(page.physicalAddress & PHYSRW_GFX_PAGE_MASK) == 0` | misaligned phys page |
| PTE walk failures | `physrw_gfx_find_a14_m1_custom_root_pte` | any root/L2/L3 resolve fails → returns false + log |
| Alias / allocate failures | `prepare_a14_m1_control_data_alias` | returns non-OK status (e.g. status `12`) |
| Transaction timeout / status | `transact_a14_m1_ppl_control_pte` + `wait_timeout` / `status_name` | trigger/fallback doesn’t complete |

### D. Finalize / reboot-carrier checks
| Check | Where | Stops when… |
|-------|-------|-------------|
| Finalize status | `UserspaceRebootTask` after `finalizeAccess` | status ≠ 0 and ≠ `0x25` → discard suspended process + error |
| Backend destroy invariants (non-A14) | `physrw_gfx_backend_destroy` asserts | lock / restore / verified PTE mismatch → `__assert_rtn` abort |
| A14 retain path | `kernel_exploit_finalize_handoff` | deliberately **does not** destroy backend; failure modes are deferred |

### E. Hard-abort class (not a clean “return error”)
Because the engine C is compiled with asserts left in (`-O0` / checked build), many of the checks above call `__assert_rtn` rather than returning a status. Educational distinction:
- **Clean stop:** function returns false / non-zero status → task reports error.
- **Hard abort:** assert fires → process `abort()`, possibly mid-mutation.

---

## 4. Short study synthesis

1. **Layout tables:** A14/M1 ≠ a unique geometry table here; it’s A13’s numbers with a different name string. That makes the “untested” label more understandable: the code path is complete, but the constants may simply be shared assumptions.
2. **Finalize statefulness:** A14 is special-cased to **retain** the direct-gfx/IOGPU transaction until process exit, while unpublished process-local callbacks. Other chips tear the backend down immediately. That asymmetry is the core risk lesson — success leaves live kernel/GPU state on purpose.
3. **UI gate ≠ last gate:** After the policy bool, many engine self-checks (runtime support, offsets, PTE walk, asserts, finalize status) can still stop — or, worse, abort after partial mutation.

> Still educational/read-only. No binary changes, no on-device steps.
