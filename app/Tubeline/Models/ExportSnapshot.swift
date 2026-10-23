import Foundation
import TubelineCore

struct ExportSnapshot {
    let job: Job
    /// Destination without an extension; each format adds its own.
    let stem: URL
    let formats: [Converter.Format]
    let options: ConversionOptions
    let revision: Int
    let sourceStamp: SourceStamp

    var folder: URL { stem.deletingLastPathComponent() }
    var extensions: [String] { formats.map(\.rawValue) }
}
