import Foundation
import TubelineCore

/// Preview and export share one worker because each mesher already uses all cores.
actor ConversionQueue {
    /// Converts one SVG and writes the same mesh to every output URL (one per format).
    typealias Convert = @Sendable (URL, [URL], ConversionOptions) throws -> ConversionReport
    private let convert: Convert

    init(convert: @escaping Convert = { source, outputs, options in
        try Converter.convert(svg: source, to: outputs, options: options)
    }) {
        self.convert = convert
    }

    func run(source: URL, outputs: [URL], options: ConversionOptions) throws -> ConversionReport {
        try Task.checkCancellation()
        do {
            let report = try convert(source, outputs, options)
            try Task.checkCancellation()
            return report
        } catch {
            for output in outputs { try? FileManager.default.removeItem(at: output) }
            throw error
        }
    }
}
