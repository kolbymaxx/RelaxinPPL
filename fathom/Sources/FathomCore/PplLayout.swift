import Foundation

/// Provenance for a PPL geometry blob.
///
/// Relaxin 0.3.4 ships A13 and A14/M1 tables that differ only in the name
/// pointer. Fathom refuses to treat that as “A14 support” unless someone
/// explicitly attests the clone — or supplies measured distinct fields.
public enum LayoutProvenance: Sendable, Equatable {
    /// Numbers measured / validated on the named chip + OS window.
    case measured(chip: CpuFamily, osWindow: String)
    /// Intentionally identical to another chip’s measured table.
    case attestedIdentical(to: CpuFamily, reason: String)
    /// Copied from another table with only a label change — **not** good enough.
    case labelOnlyClone(of: CpuFamily)
}

/// Conceptual 0x60-byte PPL layout (qword view), aligned with RelaxinEngine
/// `_kPhysrwGfx*PplLayout` field offsets from static analysis.
public struct PplLayout: Sendable, Equatable {
    public var name: String
    public var provenance: LayoutProvenance

    /// +0x08 — packed / version-like (observed `0x0000000206050000` on A13/A14).
    public var word08: UInt64
    /// +0x10 — wide mask (A13/A14: `0x0000000ffffffffe`; A16/A17 widen).
    public var word10: UInt64
    /// +0x18 … +0x38 — high VA windows (observed shared A13/A14 values).
    public var word18: UInt64
    public var word20: UInt64
    public var word28: UInt64
    public var word30: UInt64
    public var word38: UInt64
    /// +0x40 — `pageInfoLinearBase` (assert-named in RelaxinEngine).
    public var pageInfoLinearBase: UInt64
    /// +0x48 / +0x50 — companion linear / mapping VAs.
    public var word48: UInt64
    public var word50: UInt64
    /// +0x58 — flag (0 on A13–A15 tables; 1 on A16/A17 in that binary).
    public var flags: UInt64

    public static let tableByteSize: Int = 0x60

    /// Numeric fields observed for A13-PPL / A14/M1-PPL in Relaxin 0.3.4
    /// (identical between those two symbols).
    public static func relaxinObservedSharedA13A14Numerics(name: String, provenance: LayoutProvenance) -> PplLayout {
        PplLayout(
            name: name,
            provenance: provenance,
            word08: 0x0000_0002_0605_0000,
            word10: 0x0000_000f_ffff_fffe,
            word18: 0xffff_ff80_0000_0000,
            word20: 0xffff_ffa0_0000_0000,
            word28: 0xffff_ffa0_0002_0000,
            word30: 0xffff_ffa0_0008_c000,
            word38: 0xffff_fff0_0000_0000,
            pageInfoLinearBase: 0xffff_ffdc_0000_0000,
            word48: 0xffff_ff91_0016_0000,
            word50: 0xffff_ff91_0017_0000,
            flags: 0
        )
    }

    /// Fathom default for A13: treat observed numerics as a starting point only.
    public static func theoryA13Template() -> PplLayout {
        .relaxinObservedSharedA13A14Numerics(
            name: "A13-PPL",
            provenance: .measured(chip: .a13, osWindow: "observed-in-relaxin-0.3.4-static")
        )
    }

    /// Fathom default for A14: **label-only clone** until attested or remeasured.
    public static func theoryA14UnattestedClone() -> PplLayout {
        .relaxinObservedSharedA13A14Numerics(
            name: "A14/M1-PPL",
            provenance: .labelOnlyClone(of: .a13)
        )
    }

    /// What a developer would do if they prove A14 matches A13 on their builds.
    public static func theoryA14AttestedIdenticalToA13(reason: String) -> PplLayout {
        .relaxinObservedSharedA13A14Numerics(
            name: "A14/M1-PPL",
            provenance: .attestedIdentical(to: .a13, reason: reason)
        )
    }

    public var isAcceptableForEngine: Bool {
        switch provenance {
        case .measured, .attestedIdentical:
            return true
        case .labelOnlyClone:
            return false
        }
    }

    public func validateForUse() throws {
        guard isAcceptableForEngine else {
            throw FathomError.layoutUnattested(
                "\(name) is a label-only clone; attest identical geometry or measure A14 fields (see docs/THEORY.md T1)"
            )
        }
        // Category error guard: dmaFail MMIO bases must never sit in pageInfoLinearBase.
        let forbidden: Set<UInt64> = [
            0x2_3B70_03D0, // historical A14 dmaFail gGFXBase
            0x2_3B08_0390, // historical A13 dmaFail gGFXBase
            0x2_3B70_03C8,
            0x2_3B70_0408,
        ]
        if forbidden.contains(pageInfoLinearBase) {
            throw FathomError.layoutUnattested(
                "pageInfoLinearBase looks like a dmaFail GFX MMIO base — wrong layer (THEORY T4)"
            )
        }
    }
}

public enum LayoutCatalog {
    public static func layout(for chip: CpuFamily) -> PplLayout? {
        switch chip {
        case .a13:
            return .theoryA13Template()
        case .a14m1:
            // Deliberately unattested — this is the whole point of Fathom.
            return .theoryA14UnattestedClone()
        case .a15, .a16, .a17:
            return nil // SPTM path; out of scope for this PPL sketch
        }
    }
}
