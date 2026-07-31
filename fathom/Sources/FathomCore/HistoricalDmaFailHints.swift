import Foundation

/// Historical Dopamine `dmaFail` per-chip hints (iOS 15/16 era).
///
/// Present **only** as contrast documentation in code form. These values must
/// not be written into `PplLayout` fields. dmaFail was fixed around iOS 16.6;
/// Relaxin 0.3.4’s Coruna/direct-gfx path did not embed these constants.
public struct HistoricalDmaFailHints: Sendable, Equatable {
    public var gfxBase: UInt64
    public var gfxCommand: UInt32
    public var dmaIndex: UInt64
    public var dmaMask: UInt64

    public static func forChip(_ chip: CpuFamily) -> HistoricalDmaFailHints? {
        switch chip {
        case .a13:
            return .init(gfxBase: 0x2_3B08_0390, gfxCommand: 0x1F00_03FF, dmaIndex: 0x28, dmaMask: 0x3F_FFFF)
        case .a14m1:
            return .init(gfxBase: 0x2_3B70_03D0, gfxCommand: 0x1F00_23FF, dmaIndex: 0x28, dmaMask: 0x3F_FFFF)
        case .a15:
            return .init(gfxBase: 0x2_3B70_03C8, gfxCommand: 0x1F00_23FF, dmaIndex: 8, dmaMask: 0x7FF_FFFF)
        case .a16:
            return .init(gfxBase: 0x2_3B70_0408, gfxCommand: 0x1F00_23FF, dmaIndex: 8, dmaMask: 0x7FF_FFFF)
        case .a17:
            return nil
        }
    }

    public static let caveat = """
    Historical / wrong layer for an iOS 17 Coruna+PPL layout table. \
    Do not paste gfxBase into pageInfoLinearBase.
    """
}
