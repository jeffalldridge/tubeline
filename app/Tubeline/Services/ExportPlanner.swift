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

    /// Reserves one name for all of an icon's files, such as "icon.usdz" and "icon.glb", so
    /// they stay together. `stem` has no extension; the returned stem is free for every one.
    static func uniqueStem(for stem: URL, extensions: [String], reserved: inout Set<String>) -> URL {
        let folder = stem.deletingLastPathComponent()
        let name = stem.lastPathComponent
        var candidate = stem
        var number = 2
        func files(_ s: URL) -> [URL] { extensions.map { s.appendingPathExtension($0) } }
        while files(candidate).contains(where: { reserved.contains(key($0)) || FileManager.default.fileExists(atPath: $0.path) }) {
            candidate = folder.appendingPathComponent("\(name) \(number)")
            number += 1
        }
        for file in files(candidate) { reserved.insert(key(file)) }
        return candidate
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
