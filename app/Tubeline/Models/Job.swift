import Foundation
import Observation

@Observable
final class Job: Identifiable {
    enum Status: Equatable {
        case pending
        case working
        case exported(URL)
        case outdated(URL)
        case failed(String)
    }

    let id = UUID()
    let source: URL
    var status = Status.pending
    var stats: ConversionStats?

    init(source: URL) { self.source = source }

    var name: String { source.deletingPathExtension().lastPathComponent }
}

extension Job {
    var exportedURL: URL? {
        switch status {
        case .exported(let u), .outdated(let u): return u
        default: return nil
        }
    }
}
