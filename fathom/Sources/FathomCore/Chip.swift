import Foundation

/// CPU families observed in Relaxin-shaped gates / layout selection.
public enum CpuFamily: UInt32, Sendable, CaseIterable {
    case a13 = 0x4625_04D2
    case a14m1 = 0x1B58_8BB3
    case a15 = 0xDA33_D83D
    case a16 = 0x8765_EDEA
    /// Matches RelaxinEngine `chip_for_cpu_family` mapping for 0x2876F5B5.
    case a17 = 0x2876_F5B5

    public var displayName: String {
        switch self {
        case .a13: return "A13"
        case .a14m1: return "A14/M1"
        case .a15: return "A15"
        case .a16: return "A16"
        case .a17: return "A17"
        }
    }

    /// Engine chip ids from RelaxinEngine `_physrw_gfx_chip_for_cpu_family`.
    public var engineChipId: UInt32? {
        switch self {
        case .a13: return 4
        case .a14m1: return 5
        case .a15: return 1
        case .a16: return 2
        case .a17: return 3
        }
    }

    public var usesPPLOnIOS17: Bool {
        switch self {
        case .a13, .a14m1: return true
        case .a15, .a16, .a17: return false // SPTM-era on 17+ for these
        }
    }
}

public enum FathomError: Error, CustomStringConvertible, Sendable {
    case unimplemented(String)
    case layoutUnattested(String)
    case leaseStillHeld(String)
    case stageFailed(String)

    public var description: String {
        switch self {
        case .unimplemented(let s): return "unimplemented: \(s)"
        case .layoutUnattested(let s): return "layout unattested: \(s)"
        case .leaseStillHeld(let s): return "gfx lease still held: \(s)"
        case .stageFailed(let s): return "stage failed: \(s)"
        }
    }
}
