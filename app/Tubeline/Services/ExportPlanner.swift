import Foundation

/// Reserves distinct destinations before any conversion begins. Existing files are kept.
enum ExportPlanner {
    static func uniqueURL(for proposed: URL, reserved: inout Set<String>) -> URL {
        let folder = proposed.deletingLastPathComponent()
        let stem = proposed.deletingPathExtension().lastPathComponent
        let ext = proposed.pathExtension
        var candidate = proposed
        var number = 2
        while reserved.contains(key(candidate)) || FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(stem) \(number).\(ext)")
            number += 1
        }
        reserved.insert(key(candidate))
        return candidate
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
