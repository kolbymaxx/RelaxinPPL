import Foundation
import FathomCore

/// Models the A14 “retain IOGPU/direct-gfx until process exit” design —
/// but makes destroy-on-failure mandatory.
///
/// RelaxinEngine's A14 handoff path skips `physrw_gfx_backend_destroy` and
/// heartbeats `direct-gfx:a14-transaction-retained`. Fathom only allows that
/// retain when a userspace-reboot handoff is explicitly armed; every other
/// exit must `destroy()`.
public final class GfxLease: @unchecked Sendable {
    public enum State: String, Sendable {
        case inactive
        case acquired
        case retainedForReboot
        case destroyed
    }

    public private(set) var state: State = .inactive
    public let chip: CpuFamily

    public init(chip: CpuFamily) {
        self.chip = chip
    }

    /// Theory CLI only — advances state without a real primitive.
    public func theoryMarkAcquiredForFinalizeDemo() {
        state = .acquired
    }

    /// Stub: real code would open IOGPU / direct-gfx transaction.
    public func acquire() throws {
        throw FathomError.unimplemented("GfxLease.acquire — no primitive in Fathom")
    }

    /// Marks retain-for-reboot. Only valid after a successful acquire in a
    /// private engine; here it only advances the state machine for theory.
    public func retainForUserspaceReboot() throws {
        switch state {
        case .acquired:
            state = .retainedForReboot
        case .inactive:
            throw FathomError.stageFailed("retain requested without acquire")
        case .retainedForReboot:
            return
        case .destroyed:
            throw FathomError.stageFailed("retain after destroy")
        }
    }

    /// Restores alias PTEs / tears down backend — the call A14 success skips
    /// in Relaxin, and that several failure paths also skip.
    public func destroy() throws {
        switch state {
        case .inactive, .destroyed:
            state = .destroyed
            return
        case .acquired, .retainedForReboot:
            // Theory scaffold: mark destroyed. A private engine would restore
            // alias PTEs / tear down the IOGPU transaction here.
            state = .destroyed
        }
    }

    deinit {
        // Theory: if we somehow finish without destroy/retain-exit, that is a bug.
        // Cannot throw from deinit; assert in debug-shaped note only.
        if state == .acquired {
            fputs("Fathom: GfxLease deinit while still acquired — leak/panic class\n", stderr)
        }
    }
}
