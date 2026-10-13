import Foundation
import SpriteKit

/// Tiny opt-in profiler: RIFTBORN_PROFILE=1 prints labelled timings.
enum Prof {
    static let on = ProcessInfo.processInfo.environment["RIFTBORN_PROFILE"] != nil
    static var acc: [String: Double] = [:]
    @discardableResult
    static func time<T>(_ label: String, _ f: () -> T) -> T {
        guard on else { return f() }
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = f()
        acc[label, default: 0] += (CFAbsoluteTimeGetCurrent() - t0) * 1000
        return r
    }
    static func dump() {
        guard on else { return }
        for (k, v) in acc.sorted(by: { $0.value > $1.value }) { print(String(format: "  %-22@ %8.1f ms", k as NSString, v)) }
    }
}
