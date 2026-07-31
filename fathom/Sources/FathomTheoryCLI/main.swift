import Foundation
import FathomCore
import FathomEngine

print("""
Fathom — theoretical PPL pipeline scaffold
NOT a jailbreak. NOT an IPA. Privilege stages are stubs.

""")

func printReport(_ title: String, _ r: PipelineReport) {
    print("=== \(title) ===")
    print("chip: \(r.chip.displayName) (engine id \(r.chip.engineChipId.map(String.init) ?? "?"))")
    print("layout: \(r.layoutName)")
    print("provenance: \(r.provenance)")
    print("lease: \(r.leaseState)")
    for (name, outcome) in r.stages {
        print("  - \(name): \(outcome)")
    }
    for n in r.notes {
        print("  note: \(n)")
    }
    print("")
}

// Default A14 path: should STOP at layout.validate (label-only clone).
printReport(
    "A14 with Relaxin-shaped unattested clone (Fathom default)",
    EnginePipeline(chip: .a14m1).dryRunTheory()
)

// What a developer would try after proving geometry on disposable hardware:
printReport(
    "A14 after attesting identical-to-A13 (still no primitives)",
    EnginePipeline(
        chip: .a14m1,
        layoutOverride: .theoryA14AttestedIdenticalToA13(
            reason: "developer-measured on disposable device — placeholder"
        )
    ).dryRunTheory()
)

printReport(
    "A13 template (still no primitives)",
    EnginePipeline(chip: .a13).dryRunTheory()
)

print("Finalize policy sketch (A14):")
let lease = GfxLease(chip: .a14m1)
lease.theoryMarkAcquiredForFinalizeDemo()
do {
    let o = try EnginePipeline.finalizePolicy(
        chip: .a14m1, lease: lease, rocketState: 2, handoffStatus: 0
    )
    print("  success handoff → \(o), lease=\(lease.state.rawValue)")
} catch {
    print("  \(error)")
}

let leaseFail = GfxLease(chip: .a14m1)
leaseFail.theoryMarkAcquiredForFinalizeDemo()
do {
    let o = try EnginePipeline.finalizePolicy(
        chip: .a14m1, lease: leaseFail, rocketState: 2, handoffStatus: 7
    )
    print("  failed handoff → \(o), lease=\(leaseFail.state.rawValue)")
} catch {
    print("  failed handoff → \(error), lease=\(leaseFail.state.rawValue)")
}

print("""

See docs/THEORY.md and docs/DEV_HANDOFF.md.
""")
