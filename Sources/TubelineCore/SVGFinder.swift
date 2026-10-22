import Foundation

public enum SVGFinder {
    /// Expands files and folders (recursively) into a sorted list of .svg files.
    public static func collect(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let e = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                while let f = e?.nextObject() as? URL {
                    if f.pathExtension.lowercased() == "svg" { out.append(f) }
                }
            } else if url.pathExtension.lowercased() == "svg" {
                out.append(url)
            }
        }
        return out.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
