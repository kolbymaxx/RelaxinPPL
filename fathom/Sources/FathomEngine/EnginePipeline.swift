import Foundation
import FathomCore

public enum StageOutcome: Sendable, Equatable, CustomStringConvertible {
    case ok
    /// Only legal outcome that may leave a GFX lease retained.
    case continueRebootRetain
    case failed(String)

    public var description: String {
        switch self {
        case .ok: return "ok"
        case .continueRebootRetain: return "continueRebootRetain"
        case .failed(let s): return "failed(\(s))"
        }
    }
}

public struct PipelineReport: Sendable {
    public var chip: CpuFamily
    public var layoutName: String
    public var provenance: String
    public var stages: [(String, StageOutcome)]
    public var leaseState: String
    public var notes: [String]
}

/// Staged pipeline mirroring the Relaxin-shaped flow at a conceptual level:
/// confirm target → layout → early roots → gfx bootstrap → ppl ops → finalize.
///
/// Every privilege-touching stage is a stub. The “best theory” is the
/// control structure: validate layout before mutation, hold a lease, destroy
/// on any outcome except armed reboot retain.
public struct EnginePipeline: Sendable {
    public var chip: CpuFamily
    /// If set, replaces the default catalog layout (e.g. attested A14).
    public var layoutOverride: PplLayout?

    public init(chip: CpuFamily, layoutOverride: PplLayout? = nil) {
        self.chip = chip
        self.layoutOverride = layoutOverride
    }

    public func dryRunTheory() -> PipelineReport {
        var stages: [(String, StageOutcome)] = []
        var notes: [String] = []
        let lease = GfxLease(chip: chip)

        guard chip.usesPPLOnIOS17 else {
            return PipelineReport(
                chip: chip,
                layoutName: "n/a",
                provenance: "n/a",
                stages: [("ppl-scope", .failed("chip is SPTM-era on iOS 17; out of PPL sketch"))],
                leaseState: lease.state.rawValue,
                notes: ["Fathom only sketches A13/A14 PPL."]
            )
        }

        guard var layout = layoutOverride ?? LayoutCatalog.layout(for: chip) else {
            return PipelineReport(
                chip: chip, layoutName: "?", provenance: "?",
                stages: [("layout", .failed("no layout"))],
                leaseState: lease.state.rawValue,
                notes: []
            )
        }

        // --- Stage: layout honesty (THEORY T1) ---
        do {
            try layout.validateForUse()
            stages.append(("layout.validate", .ok))
        } catch {
            stages.append(("layout.validate", .failed(String(describing: error))))
            notes.append("A14 default is label-only clone of A13 numerics — attest or remeasure.")
            return report(layout, stages, lease, notes)
        }

        // --- Stage: historical constant hygiene (THEORY T4) ---
        if let hints = HistoricalDmaFailHints.forChip(chip) {
            notes.append(
                "Historical dmaFail gfxBase=\(hex(hints.gfxBase)) exists for contrast; \(HistoricalDmaFailHints.caveat)"
            )
            stages.append(("constants.layerCheck", .ok))
        }

        // --- Stub stages (no primitives) ---
        // Privilege stages are intentionally unimplemented. First stub stops
        // the dry-run; a private engine would acquire a GfxLease before mutation
        // and destroy it on any failure (T2/T3).
        let stubStages = [
            "coruna.earlyRoots",
            "gfx.bootstrap",
            "ppl.prepareAlias",
            "ppl.transactControlPte",
            "finalize.handoff",
        ]
        if let first = stubStages.first {
            stages.append((first, .failed(FathomError.unimplemented(first).description)))
            notes.append("Would acquire GFX lease before mutation; destroy on failure (T2/T3).")
            notes.append("Later stubs not run: \(stubStages.dropFirst().joined(separator: ", "))")
            _ = try? lease.destroy()
        }
        return report(layout, stages, lease, notes)
    }

    /// Illustrates the finalize policy Fathom wants (THEORY T2/T3).
    public static func finalizePolicy(
        chip: CpuFamily,
        lease: GfxLease,
        rocketState: Int,
        handoffStatus: Int
    ) throws -> StageOutcome {
        // chip == 5 → A14 uses process-exit cleanup in Relaxin.
        let usesProcessExitCleanup = (chip.engineChipId == 5)

        if rocketState == 0 {
            try lease.destroy()
            return .ok // idle / 0x25-shaped: no retain
        }

        if handoffStatus != 0 && handoffStatus != 0x25 {
            // Relaxin discards reboot carrier here but may skip GFX destroy.
            try lease.destroy()
            return .failed("handoff status \(handoffStatus) — carrier discard + mandatory GFX destroy")
        }

        if usesProcessExitCleanup && handoffStatus == 0 {
            try lease.retainForUserspaceReboot()
            return .continueRebootRetain
        }

        try lease.destroy()
        return .ok
    }

    private func report(
        _ layout: PplLayout,
        _ stages: [(String, StageOutcome)],
        _ lease: GfxLease,
        _ notes: [String]
    ) -> PipelineReport {
        let prov: String = {
            switch layout.provenance {
            case .measured(let c, let os): return "measured(\(c.displayName), \(os))"
            case .attestedIdentical(let c, let r): return "attestedIdentical(to: \(c.displayName), \(r))"
            case .labelOnlyClone(let c): return "labelOnlyClone(of: \(c.displayName))"
            }
        }()
        return PipelineReport(
            chip: chip,
            layoutName: layout.name,
            provenance: prov,
            stages: stages,
            leaseState: lease.state.rawValue,
            notes: notes
        )
    }

    private func hex(_ v: UInt64) -> String { String(format: "0x%llX", v) }
}
