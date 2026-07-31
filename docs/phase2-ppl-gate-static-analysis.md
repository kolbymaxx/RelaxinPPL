# Phase 2 – Relaxin v0.3.4(0) PPL Device Gate Static Analysis

**Build:** Relaxin `0.3.4` (`CFBundleVersion` `0`)  
**Bundle ID:** `com.aapl.relaxin`  
**MinimumOSVersion:** `17.0`  
**Required capability:** `arm64e`  
**Analysis mode:** read-only strings / symbol mapping (no patches, no on-device tests)  
**Target context:** iPhone 12 mini (`iPhone13,1`), iOS 17.3, Darwin 23.3.0  
**On-device error:** `Unsupported` / `Jailbreaking PPL devices is not currently supported.`

---

## 1. Binaries analyzed

| Path | Size | Arch |
|------|------|------|
| `Payload/Relaxin.app/Relaxin` | 3,577,704 | arm64e executable (UI / gate) |
| `Payload/Relaxin.app/Frameworks/RelaxinEngine.framework/RelaxinEngine` | 921,384 | arm64e dylib (exploit / engine) |
| `Payload/Relaxin.app/libjailbreak.dylib` | 795,808 | fat arm64 + arm64e |
| `Payload/Relaxin.app/libxpf.dylib` | 372,768 | fat arm64 + arm64e (XPF / PPL symbol finders) |
| `Payload/Relaxin.app/libchoma.dylib` | 437,872 | fat arm64 + arm64e |
| `Payload/Relaxin.app/CydiaSubstrate.framework/CydiaSubstrate` | 833,984 | fat arm64 + arm64e (ElleKit) |

Also noted (not fully disassembled this pass): `basebin.tar` contains `jailbreakd`, `boomerang`, hooks, and copies of `libjailbreak` / `libxpf`.

Localization: `*.lproj/Localizable.strings` (exact error + bypass/warning copy).

---

## 2. Key string hits

### 2.1 Exact error (localization + main binary)

| String | Where | Offset (approx.) |
|--------|-------|------------------|
| `Jailbreaking PPL devices is not currently supported.` | `en.lproj/Localizable.strings` (and all other lproj) | plist key |
| same | `Relaxin` main binary | `0x12e940` |
| `Unsupported` / `Unsupported Target` | localization + main | UI title path |
| `Jailbreaking PPL devices has not been tested. Continuing may cause unexpected device behavior.` | localization + main | `0x12e9d0` |
| `Bypass PPL Device Check?` | localization + main | `0x12e9b0` |

### 2.2 Gate / device detection (main `Relaxin`)

| Hit | Offset / symbol | Notes |
|-----|-----------------|-------|
| `PPLJailbreakGate` | `0x12b940`, type `_TtC7Relaxin16PPLJailbreakGate` | Dedicated Swift class |
| `_pplJailbreakGate` | property | Stored on home flow |
| `hw.cpufamily` | `0x12bdc6` | CPU family via sysctl |
| `DeviceInfo.cpuFamily` | Swift symbol | Reads `hw.cpufamily` |
| `JailbreakTarget.isPPLDevice` | Swift getter | Boolean used before engine start |
| `JailbreakTarget.RuntimeProfile` | Swift enum/type | Maps CPU family → profile/SoC |
| `HomeView.presentPPLJailbreakGate` | Swift method | Shows the unsupported UI |
| `HomeView.startEngine(allowingUntestedPPLDevice:)` | Swift method | Engine entry with bypass flag |
| `PPLJailbreakGate.finish(shouldBypass:)` | Swift method | Completes gate with bool |
| `PPLJailbreakGate.presentBypassConfirmation` / `revealBypassConfirmation` | Swift methods | Hidden bypass confirm UI |
| `PPLJailbreakGate.handleVolumeChange` / `ExpectedVolumeEndpoint` / `completedRoundTrips` | Swift methods | Volume-based secret to reveal bypass |
| ConfirmationError cases | `unsupportedOS`, `unsupportedSoC`, `missingCPUFamily`, `simulator`, … | Broader target validation |

### 2.3 Runtime profiles + A14/Coruna (RelaxinEngine)

Cluster at ~`0x888ee`:

```text
hw.cpufamily
A13          -> ppl-gfx-a13
A14/M1       -> ppl-gfx-a14-m1
A15          -> sptm-gfx-a15
A16          -> sptm-gfx-a16
A17          -> sptm-gfx-a17
17.0 … 17.3.1
targetOSVersion unsupported=%@
runtimeProfile has no mapping for the live CPU family
target confirmed device=%@ soc=%@ cpu_family=%@ ios=%@ build=%@ profile=%@
```

A14-specific implementation names (not stubs-by-name):

| Symbol / string | Role |
|-----------------|------|
| `ppl-gfx-a14-m1` | Runtime profile id |
| `PHYSRW_GFX_CHIP_A14_M1` | Chip enum case |
| `_kPhysrwGfxA14M1PplLayout` | A14/M1 PPL layout table |
| `_kPhysrwGfxA13PplLayout` / `A15`/`A16`/`A17` layouts | Sibling chip tables |
| `physrw_gfx_prepare_a14_m1_control_data_alias` | A14 control-data alias prep |
| `physrw_gfx_find_a14_m1_custom_root_pte` | A14 custom root PTE find |
| `physrw_gfx_transact_a14_m1_ppl_control_pte` | A14 PPL control PTE transaction |
| `a14_kernel_access_finalize` | Post-handoff A14 finalize stage |
| `direct-gfx:a14-transaction-retained` | A14 IOGPU transaction retention |
| `A14/M1-PPL` | Human-readable backend label |

Coruna bootstrap (physrw) — real error/format strings + globals:

- `[physrw][bootstrap] Coruna lock fd failed…`
- `Coruna voucher create/leak…`, `fileport`, `task anchor`, `port decode…`
- `_g_physrwCorunaTaskAnchor`
- `_physrw_coruna_create_voucher`, `_physrw_coruna_prepare_fileport_fd`, …
- `_physrw_gfx_find_coruna_first_masked_words`, `_physrw_gfx_find_coruna_first_self_branch`

PPL backend surface (examples): `physrw_gfx_bootstrap_ppl_backend`, `physrw_gfx_ppl_write32/64`, `physrw_gfx_ppl_runtime_is_supported`, `physrw_gfx_resolve_ppl_state`, `physrw_gfx_transact_ppl_control_pte`, plus ~150 `physrw_gfx_*` symbols total.

### 2.4 Supporting libraries

**libxpf.dylib:** full PPL finder surface (`src/ppl.c`, `ppl_enter`, `ppl_bootstrap_dispatch`, `pmap_enter_options_ppl`, `ppl_trust_cache_rt`, and SPTM variants).

**libjailbreak.dylib:** SPTM-aware physrw handoff strings, `InitPPLRW`, `pmap_mark_page_as_ppl_page`, Fugu14 kcall, IOSurface primitives.

**No `iPhone13` model hardcode** found in the gate path — detection is via `hw.cpufamily` / runtime profile, not model string.

---

## 3. Control-flow model (from symbols + strings)

```text
HomeView jailbreak action
  -> JailbreakTarget.current
       reads DeviceInfo (hw.cpufamily, model, os, build)
       maps RuntimeProfile (ppl-gfx-* vs sptm-gfx-*)
       exposes isPPLDevice
  -> if PPL and not already allowing untested:
       presentPPLJailbreakGate()
         UIAlert: title "Unsupported"
                  message "Jailbreaking PPL devices is not currently supported."
         secret: volume endpoint round-trips
           -> reveal/presentBypassConfirmation ("Bypass PPL Device Check?")
           -> warning: "…has not been tested…"
           -> finish(shouldBypass: true/false)
  -> startEngine(allowingUntestedPPLDevice: Bool)
       -> RelaxinEngine validate/confirm target
       -> physrw / Rocket path using chip layout (A14/M1-PPL vs SPTM)
```

This is primarily an **early UI/policy gate**, not a missing binary. The engine already contains A14/M1 PPL + Coruna paths.

---

## 4. Initial assessment

### Verdict: **dormant / gated code present** (not “support simply absent”)

| Hypothesis | Evidence |
|------------|----------|
| Gate only (flip check = works) | Gate is real, but “untested” warning + A14 finalize/Coruna complexity mean flip ≠ proven safe |
| Gate + missing primitives | **Rejected** — A14/M1 profile, layouts, PTE helpers, Coruna bootstrap, finalize stage all present |
| Dormant code present | **Supported** — substantial A14/PPL/Coruna implementation behind UI gate + optional volume bypass |

**Answer to the phase success question:**

> Does v0.3.4(0) contain usable A14/PPL support code that is merely gated, or is the support simply not present yet?

**Statically: A14/PPL/Coruna support code is present and merely gated (plus labeled untested).**  
We have **not** proven runtime usability or safety on iPhone12 mini / 17.3 — that would require agreed deeper disassembly and, only later, carefully scoped testing.

---

## 5. Safety notes (for Grok / user)

- Do **not** treat the volume-button bypass as an approved on-device experiment.
- Strings explicitly mark PPL as unsupported by default and untested if bypassed.
- A14 path retains IOGPU transactions and has Coruna failure modes — boot-loop / instability risk is non-trivial.
- No binary modification in this phase.

---

## 6. Recommended next static-analysis step

1. **Disassemble** `JailbreakTarget.isPPLDevice` and `HomeView.startEngine(allowingUntestedPPLDevice:)` in `Relaxin` to confirm exact branch predicates (which CPU families count as PPL; whether A13 is also gated the same way).
2. **Disassemble** in `RelaxinEngine`:
   - `physrw_gfx_chip_for_cpu_family`
   - `physrw_gfx_layout_for_chip` / `_kPhysrwGfxA14M1PplLayout`
   - `physrw_gfx_prepare_a14_m1_control_data_alias`
   - `physrw_gfx_transact_a14_m1_ppl_control_pte`
   - Coruna bootstrap (`physrw_coruna_*`)
   - `a14_kernel_access_finalize`
3. Classify each as **full implementation vs error-stub / `#if 0` residue**.
4. Only after that classification: Grok + user decide whether any controlled patch discussion is even warranted.

---

## 7. Artifact index (local, gitignored binaries)

- IPA source: Google Drive `Relaxin-v0.3.4.zip` (extracted under `Payload/`, gitignored)
- Working notes under `artifacts/analysis/`
