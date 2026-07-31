# Phase 6 — Differential analysis: Relaxin 0.3.4 → 0.3.8 beta (PPL)

> Read-only static diff. No on-device testing. Binaries gitignored.

| | OLD | NEW |
|--|-----|-----|
| Version | `0.3.4` (0) | `0.3.8` (0) beta |
| Bundle | `com.aapl.relaxin` | same |
| MinOS | 17.0 | 17.0 |
| `RelaxinEngine` size | 921 384 | 923 144 |
| Focus | arm64e `Relaxin` + `RelaxinEngine` | same |

---

## Verdict (residual risks A–D)

| Risk | Status | One-line |
|------|--------|----------|
| **A. A13/A14 layout numerics identical** | **Still present** | Still one-byte name-only diff; `pageInfoLinearBase` unchanged |
| **B. A14 finalize retains IOGPU / skips destroy** | **Still present** | Same CFG; still heartbeats `direct-gfx:a14-transaction-retained` |
| **C. Failure exits skip GFX teardown** | **Still present** | Rocket states / `0x25` / carrier-discard unchanged vs destroy |
| **D. Dopamine-style A14 GFX MMIO missing** | **Still present** | Those constants still absent; no new per-chip MMIO table found |

**What actually enabled “official PPL” in 0.3.8:** the **UI policy gate was removed** from the main app. The engine’s A14 retain/layout story is essentially the same relocated code, not a redesign of the residual-risk items above.

---

## A. Layout tables — **Still present**

Symbols still exist (addresses moved):

| Symbol | 0.3.4 | 0.3.8 |
|--------|-------|-------|
| `_kPhysrwGfxA13PplLayout` | `0xa1020` | `0xa1058` |
| `_kPhysrwGfxA14M1PplLayout` | `0xa1080` | `0xa10b8` |

Each table remains **`0x60` bytes**.

**A13 vs A14 inside 0.3.8:** still **exactly 1 differing byte** (chained name pointer low byte). Numeric fields `+0x08 … +0x5c` are identical, including:

| Off | Value (both chips, both versions) |
|-----|-----------------------------------|
| `+0x40` `pageInfoLinearBase` | `0xffffffdc00000000` |
| `+0x48` / `+0x50` | `0xffffff9100160000` / `0xffffff9100170000` |

**0.3.4 A14 vs 0.3.8 A14:** fields from `+0x08` onward are **byte-identical**. Only the name-pointer encoding at `+0x00` changed (string moved in `__TEXT`).

So 0.3.8 did **not** give A14 a distinct PPL geometry table. If shared A13/A14 numerics were a risk before, they still are — unless the authors validated that sameness off-tree (not visible in the binary).

---

## B. Finalize / handoff — **Still present**

`_kernel_exploit_finalize_handoff` size unchanged (`0xd8` bytes). Control flow matches 0.3.4 after relocation:

```
# 0.3.8 @ 0x567dc (was 0x5ab08)
tbz  exploit-active → return 0
bl   _kernel_exploit_uses_process_exit_cleanup   ; true iff active && chip==5
tbz  w0 → non-A14 arm
  ; ---- A14 / process-exit cleanup arm ----
  bl   _kernel_exploit_unpublish_data_primitives
  bl   _physrw_stage_heartbeat  ; "direct-gfx:a14-transaction-retained" @ 0x8c098
  return 0                      ; NO physrw_gfx_backend_destroy
  ; ---- other chips ----
  bl   _physrw_gfx_backend_destroy
  assert retained == 0
  bl   _physrw_gfx_release_cached_protected_descriptors
  bl   _kernel_exploit_unpublish_data_primitives
  heartbeat "a17-direct:data-access-finalized"
  return 0
```

`_kernel_exploit_uses_process_exit_cleanup` still: exploit flag set **and** `backend->chip == 5` (A14/M1).

Heartbeat string **still present** in 0.3.8:
`direct-gfx:a14-transaction-retained` @ `0x8c098`  
Log string still present: `IOGPU transaction retained until process exit` / `a14_kernel_access_finalize…`.

**Not fixed:** success path for A14 still retains the direct-gfx/IOGPU transaction and skips destroy.

---

## C. Destroy / teardown on failure paths — **Still present**

`_physrw_gfx_backend_destroy` call sites in 0.3.8 (same two roles as 0.3.4):

1. Non-A14 arm of `_kernel_exploit_finalize_handoff` (`0x56830`)
2. Failure cleanup inside `_physrw_gfx_bootstrap` (`0x6940c`)

**Not** called from the A14 success arm.

Rocket / reboot CFG (sizes unchanged for finalize/deinit):

| Path | 0.3.8 behavior | Destroy? |
|------|----------------|----------|
| `rlx_finalize` state `0` | return `0x25` | No |
| state `1` | `exploit_deinit` only (sockets) | No |
| state `2`/`3` | `rlx_deinitialize` → handoff (A14 retain) + `exploit_deinit` | No on A14 |
| state `4` | return saved error / `5` | No |
| UserspaceReboot: status `0` | log retain; continue | No |
| status `0x25` | treated OK | No |
| other status | `rlx_discard_suspended_process` + error | **No** (carrier only) |

So the earlier “failure leaves live GFX state” exits were **not** closed in this beta.

Minor size deltas (not teardown redesign):  
`_physrw_gfx_transact_a14_m1_ppl_control_pte` `0x554`→`0x574`, `_physrw_gfx_bootstrap` `0xb30`→`0xb5c`. No new destroy-related symbols.

---

## D. Constants / windows — **Still present** (no Dopamine MMIO incorporation)

Searched both engines for public dmaFail-era values:

| Constant | 0.3.4 | 0.3.8 |
|----------|-------|-------|
| A14 `0x23B7003D0` | absent | absent |
| A13 `0x23B080390` | absent | absent |
| A15/A16 GFX bases | absent | absent |
| `0x1F0023FF` / `0x1F0003FF` | absent | absent |
| `0x206040000` / `0x206140000` / `0x206150000` | absent | absent |

Profile strings still in engine: `ppl-gfx-a13`, `ppl-gfx-a14-m1`. No evidence that classic Dopamine GFX MMIO tables were added. Coruna/direct-gfx path remains the in-tree approach; 0.3.8 does not suddenly look like dmaFail constants landed.

---

## What *did* change to enable PPL support (UI / product)

This is where 0.3.8 actually differs for “PPL devices officially enabled”:

### Main app (`Relaxin`) — gate removed

| Artifact | 0.3.4 | 0.3.8 |
|----------|-------|-------|
| `JailbreakTarget.isPPLDevice` | present | **gone** |
| `PPLJailbreakGate` (+ volume bypass) | present | **gone** |
| `startEngine(allowingUntestedPPLDevice:)` | present | **replaced by** `startEngine()` (no bool) |
| `presentPPLJailbreakGate` | present | **gone** |
| Localizable: “not currently supported” / “Bypass PPL…” / “has not been tested” | present | **removed** |
| New copy | — | `RootHide, PPL/TXM` string in binary |

So “official PPL” here means **the app no longer refuses A13/A14 at the UI policy layer**. Engine entry is unconditional `startEngine()` from HomeView.

### Engine (`RelaxinEngine`) — mostly relocate + small edits

- Same A14 helpers (`prepare` / `find` / `transact_a14_m1_*`), Coruna symbols, layout symbols, finalize/retain path.
- No new teardown API; no layout numeric split; no dmaFail MMIO blob.
- Slight growth in bootstrap / A14 transact (likely local fixes, not visible as a new destroy policy).

---

## Short summary for a developer

1. **Residual risks A–D from the 0.3.4 read-only note are still present in 0.3.8’s engine.**  
2. **PPL “enablement” in this beta is primarily shipping without the UI gate**, i.e. trusting the existing A14/Coruna path rather than redesigning layout distinctness or finalize teardown.  
3. If those risks were acceptable because of on-device validation, that validation is **not** reflected as distinct A14 layout bytes or destroy-on-failure CFG in this build.  
4. Classic Dopamine A14 GFX constants were **not** the enable mechanism.

---

## How to verify quickly

```bash
# layouts: expect 1-byte A13/A14 diff
xxd -s 0xa1058 -l 0x60 RelaxinEngine   # A13 in 0.3.8
xxd -s 0xa10b8 -l 0x60 RelaxinEngine   # A14 in 0.3.8

# retain heartbeat still there
strings -a RelaxinEngine | grep a14-transaction-retained

# UI gate gone
llvm-nm -arch arm64e Relaxin | grep -E 'isPPLDevice|PPLJailbreakGate|allowingUntested'   # empty on 0.3.8
llvm-nm -arch arm64e Relaxin | grep startEngine   # startEngineyyF only
```
