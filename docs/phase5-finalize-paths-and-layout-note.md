# Phase 5 — Read-Only Technical Note: A14 Finalize Paths & Layout Tables

> **Read-only / educational.** No patches, no on-device steps. Offsets are for
> Relaxin `0.3.4(0)` `RelaxinEngine` (arm64e), unslid file VAs as linked
> (`vmaddr == fileoff` for these sections).

This note packages four static follow-ups that do not need a device:

1. Control-flow map of A14 finalize / early exits that skip IOGPU teardown  
2. Byte-level A13 vs A14/M1 layout side-by-side  
3. Cross-check against public Dopamine/Coruna A14 constants  
4. Offset-annotated facts a developer can verify with `nm` + a hex dump  

---

## 0. Quick verdict

- A14/M1 finalize **intentionally skips** `physrw_gfx_backend_destroy` and keeps
  the direct-gfx / IOGPU transaction until process exit.
- Several error / idle paths also **never** call destroy, so a failed or
  half-started A14 session can leave the same class of live state behind.
- `_kPhysrwGfxA13PplLayout` and `_kPhysrwGfxA14M1PplLayout` differ by **one
  byte** (the name-string pointer). All numeric fields are identical.
- Public Dopamine `dmaFail` A13/A14 **GFX register bases are not present** in
  this binary; the shared layout looks like a labeled A13 PPL geometry copy,
  not a Dopamine-style per-chip register table.

---

## 1. A14 finalize CFG — paths that skip IOGPU teardown

There is no symbol named `a14_kernel_access_finalize`. That string is a **phase
log** inside `-[RLXEngine12UserspaceRebootTask execute]` (`0x51384`).

### Call chain (success)

```
UserspaceRebootTask.execute                @ 0x51384
  requiresUserspaceRebootFinalization      @ 0x7daa8
    → kernel_exploit_requires_userspace_reboot_finalization @ 0x5aaa8
      → kernel_exploit_uses_process_exit_cleanup            @ 0x5aac0
         (true iff exploit-active byte @ 0xaac59 && backend chip == 5)
  finalizeAccess                           @ 0x7da10
    → rlx_finalize_rocket_runtime          @ 0x7ca38
       state 2/3 → rlx_deinitialize_rocket_runtime @ 0x7db68
         → kernel_exploit_finalize_handoff @ 0x5ab08
            A14: unpublish + heartbeat "direct-gfx:a14-transaction-retained"
                 **no** physrw_gfx_backend_destroy
         → exploit_deinit                  @ 0x5791c
            → krw_sockets_cleanup only     (**no** GFX destroy)
```

Chip id `5` = A14/M1 from `_physrw_gfx_chip_for_cpu_family` (`0x765f8`) when
`hw.cpufamily == 0x1B588BB3`.

### `kernel_exploit_finalize_handoff` (`0x5ab08`) — branch table

| # | Condition | Code path | `backend_destroy`? | Status |
|---|-----------|-----------|--------------------|--------|
| H1 | Exploit inactive (`*(uint8*)0xaac59 == 0`) | store `0`, return | **No** | `0` |
| H2 | Active **and** `uses_process_exit_cleanup` (A14/M1) | `unpublish_data_primitives` + heartbeat `direct-gfx:a14-transaction-retained` @ `0x8ba52` | **No** | `0` |
| H3 | Active **and not** A14 cleanup | `physrw_gfx_backend_destroy` → assert `retained == 0` → `release_cached_protected_descriptors` → `unpublish` + heartbeat `a17-direct:data-access-finalized` | **Yes** | `0` |

Only **one** non-bootstrap call site invokes `_physrw_gfx_backend_destroy`
(`0x6a6f4`): the H3 arm at `0x5ab5c`. (Bootstrap failure cleanup at `0x68400`
is the other site.)

On path H2, handoff **always** returns `0` in the disassembly (no status from
unpublish is propagated). Teardown of alias PTEs / IOGPU is deferred by design.

### `rlx_finalize_rocket_runtime` (`0x7ca38`) — state machine

Reads `_rlx_rocket_runtime_state` @ `0xab938`:

| State | Meaning (from control flow) | Action | Destroy? |
|------|-----------------------------|--------|----------|
| `0` | Idle / not started | return **`0x25`** | No |
| `1` | Early/alternate armed | `exploit_deinit` only (sockets) | **No** |
| `2` or `3` | Normal teardown | `rlx_deinitialize_rocket_runtime` | Only if handoff takes H3 |
| `4` | Failed terminal | return saved error @ `0xab93c`, or **`5`** if saved==0 | **No** |
| other | Default | fall through to return path | No |

### `rlx_deinitialize_rocket_runtime` (`0x7db68`)

| # | Condition | Action | Destroy? |
|---|-----------|--------|----------|
| D1 | `finalize_handoff() != 0` | set state=`4`, save error, **skip** `exploit_deinit`, return error | No (handoff already failed; A14 H2 does not produce this) |
| D2 | `finalize_handoff() == 0` | `exploit_deinit` (sockets), clear rocket kread/kwrite ptrs @ `0xab940`/`0xab948` | **No on A14** (H2 already skipped destroy) |

### `UserspaceRebootTask.execute` — finalize phase (`0x5157c`…)

| # | Condition | Action | Destroy? | Dangerous leftover? |
|---|-----------|--------|----------|---------------------|
| U1 | `requiresUserspaceRebootFinalization == false` | skip finalize logs; continue reboot spawn | No | Only if GFX was raised earlier without this phase |
| U2 | `finalizeAccess` status **`0`** | log `…status=0; IOGPU transaction retained until process exit` (`0x8a417`); `setKernelAccess:` nil; continue | **No** | **Yes — intentional retain** |
| U3 | status **`0x25`** | treated as OK (same success join as U2) | No | Idle; no new retain |
| U4 | status **other** | `rlx_discard_suspended_process` + `rlx_userspace_reboot_error` | **No** | **Yes if GFX/IOGPU already live** — discard is the reboot *carrier*, not IOGPU |

### Concrete “failure / exit points that leave dangerous state”

These are the static answers to “which exits skip IOGPU teardown?” for A14:

1. **H2 success** — primary design: retain until process exit.  
2. **D2 after H2** — sockets cleared; GFX backend pointer path not destroyed.  
3. **State `1` finalize** — `exploit_deinit` only; never enters handoff destroy arm.  
4. **State `4` / unknown finalize returns** — U4 discards carrier only; no destroy.  
5. **H1 / U1** — no teardown in this phase (benign if never bootstrapped; stale if an earlier task armed GFX and flags disagree).  
6. **Assert abort inside non-A14 destroy (H3)** — not A14, but shows destroy is assert-hard; A14 avoids that arm entirely by retaining instead.

`exploit_deinit` is **not** a GFX teardown function; it only calls
`_krw_sockets_cleanup`.

---

## 2. Byte-level A13 vs A14/M1 layout tables

| Symbol | VA / fileoff |
|--------|----------------|
| `_kPhysrwGfxA13PplLayout` | `0xa1020` |
| `_kPhysrwGfxA14M1PplLayout` | `0xa1080` |

Each table is **`0x60` bytes**, selected by `_physrw_gfx_layout_for_chip`
(`0x76538`): chip `4`→A13, chip `5` (and default non-1/2/3/4)→A14/M1.
Bootstrap copies the full `0x60` into the backend at `backend+0xa8`
(`memcpy`-style at `0x67ff4`, size `#0x60`).

### Side-by-side (qwords)

| Offset | A13 | A14/M1 | Same? | Notes |
|--------|-----|--------|-------|-------|
| `+0x00` | chained ptr → `"A13-PPL"` @ `0x92f06` | chained ptr → `"A14/M1-PPL"` @ `0x92f0e` | **No** | **Only differing byte:** `0x06` vs `0x0e` at `+0x00` |
| `+0x08` | `0x0000000206050000` | identical | yes | Packed / version-like constant (not named in asserts) |
| `+0x10` | `0x0000000ffffffffe` | identical | yes | Wide mask (A16/A17 widen this to `…fffffffe`) |
| `+0x18` | `0xffffff8000000000` | identical | yes | High VA window base |
| `+0x20` | `0xffffffa000000000` | identical | yes | High VA window |
| `+0x28` | `0xffffffa000020000` | identical | yes | Window + `0x20000` |
| `+0x30` | `0xffffffa00008c000` | identical | yes | Window + `0x8c000` |
| `+0x38` | `0xfffffff000000000` | identical | yes | High VA window |
| `+0x40` | `0xffffffdc00000000` | identical | yes | **`pageInfoLinearBase`** (named) |
| `+0x48` | `0xffffff9100160000` | identical | yes | Companion linear / mapping VA |
| `+0x50` | `0xffffff9100170000` | identical | yes | Companion linear / mapping VA |
| `+0x58` | `0x0` | identical | yes | Flag; A16/A17 layouts set `1` |

**Differing bytes:** exactly **1** (`+0x00`).

### Named field (verified)

- Assert string @ `0x8dda1`:  
  `!g_linearPageInfoBase || g_linearPageInfoBase == layout->pageInfoLinearBase`
- `_physrw_gfx_active_layout` (`0x650c0`) loads `layout+0x40` and compares to
  `g_linearPageInfoBase` (`0xab8f0`).

So `+0x40` is the PPL **page-info linear base** used when walking/validating
GFX/PPL page-info views. Neighbor words at `+0x18…+0x50` are the same *class*
of constants (kernel/PPL VA windows), not AGX DMA register addresses.

### What these offsets are *not*

They are **not** Dopamine `gGFXBase` / CTRR MMIO values. Those public constants
live in a different layer (AGX debug / DMA). This table is a PPL geometry /
page-info layout blob shared across A13–A15 in this build.

---

## 3. Public Dopamine / Coruna cross-reference

Public Dopamine 2.x `dmaFail.c` (iOS 15/16 PPL bypass; fixed ~16.6) sets
**per-chip** hardware constants, including:

| CPU | `gGFXBase` | `gGFXCommand` | `gDMAIndex` | `gDMAMask` |
|-----|------------|---------------|-------------|------------|
| A13 `0x462504D2` | `0x23B080390` | `0x1F0003FF` | `0x28` | `0x3FFFFF` |
| A14 `0x1B588BB3` | `0x23B7003D0` | `0x1F0023FF` | `0x28` | `0x3FFFFF` |

Sources: [Dopamine `dmaFail.c`](https://github.com/opa334/Dopamine/blob/2.x/Application/Dopamine/Exploits/dmaFail/dmaFail.c),
[Apple Wiki – dmaFail](https://theapplewiki.com/wiki/DmaFail).

### Search results inside `RelaxinEngine`

| Constant | In binary? |
|----------|------------|
| `0x23B7003D0` (A14 GFX base) | **No** |
| `0x23B080390` (A13 GFX base) | **No** |
| `0x23B7003C8` / `0x23B700408` (A15/A16) | **No** |
| `0x1F0023FF` / `0x1F0003FF` | **No** |
| `0x206040000` / `0x206140000` / `0x206150000` | **No** |
| `0x3FFFFF` / `0x7FFFFFF` as raw words | Appear only inside **generic progressive mask tables** @ `0x83f90` / `0x84b78` (not chip-selected DMA config) |

Relaxin clearly has its **own** Coruna/PPL GFX path (`physrw_gfx_*a14_m1*`,
`physrw_coruna_*`, heartbeats `direct-gfx:*`). That path is not a literal copy of
Dopamine’s `dmaFail` register table.

**Implication for the identical A13/A14 layout words:** public knowledge says
A13 vs A14 **do** need different GFX MMIO bases for the classic dmaFail-style
primitive. Relaxin’s `_kPhysrwGfxA14M1PplLayout` does **not** encode that
distinction; it is an A13 PPL layout with an A14/M1 label. That matches the UI
copy (“has not been tested”) better than “known-good A14 constants landed.”

---

## 4. Developer verification checklist

```bash
# symbols
llvm-nm -arch arm64e RelaxinEngine | rg 'kPhysrwGfxA1[34]|finalize_handoff|uses_process_exit|backend_destroy'

# one-byte layout diff (expect only +0x00)
xxd -s 0xa1020 -l 0x60 RelaxinEngine > /tmp/a13.hex
xxd -s 0xa1080 -l 0x60 RelaxinEngine > /tmp/a14.hex
diff -u /tmp/a13.hex /tmp/a14.hex

# strings
strings -a RelaxinEngine | rg 'A13-PPL|A14/M1-PPL|pageInfoLinearBase|a14-transaction-retained|IOGPU transaction retained'
```

Expected:

- Name strings at `0x92f06` / `0x92f0e`  
- Heartbeat `direct-gfx:a14-transaction-retained` @ `0x8ba52`  
- Log `a14_kernel_access_finalize status=0; IOGPU transaction retained until process exit` @ `0x8a417`  
- Assert expression containing `layout->pageInfoLinearBase` @ `0x8dda1`  

---

## 5. How this refines Phase 4

| Phase 4 claim | Phase 5 refinement |
|---------------|--------------------|
| A14 finalize retains IOGPU | Enumerated **H2/D2/U2** plus error states **U4 / state 1 / state 4** that also skip destroy |
| Layout tables identical except name | Proven **single-byte** diff; qword table + confirmed `+0x40` name |
| “Untested” is about constants | Strengthened: no public Dopamine A14 GFX bases; A14 table is A13 geometry |

Still educational / read-only. Code exists ≠ safe to run on A14.
