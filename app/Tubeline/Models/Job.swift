import Foundation
import Observation
import TubelineCore

@Observable
final class Job: Identifiable {
    enum Status: Equatable {
        case pending
        case working
        case exported(URL)
        case outdated(URL)
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let source: URL
    var status = Status.pending
    var stats: ConversionStats?
    var overrides = ConversionOverrides()
    var revision = 0
    var lastExportURL: URL?
    var lastExportOptions: ConversionOptions?
    var lastExportRevision: Int?

    init(source: URL) { self.source = source }

    var name: String { source.deletingPathExtension().lastPathComponent }
    var hasOverrides: Bool { !overrides.isEmpty }
    var exportedURL: URL? { lastExportURL }
}
