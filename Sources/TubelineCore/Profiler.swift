import Foundation

/// Prints how long each stage takes when the TL_PROFILE environment variable is set.
/// A development aid: `TL_PROFILE=1 swift run -c release tubeline icon.svg`.
struct Profiler {
    static let enabled = ProcessInfo.processInfo.environment["TL_PROFILE"] != nil
    private var start = Date()

    mutating func lap(_ stage: @autoclosure () -> String) {
        guard Self.enabled else { return }
        print(String(format: "  %@: %.3f s", stage(), Date().timeIntervalSince(start)))
        start = Date()
    }
}
