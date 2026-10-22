import Foundation
import TubelineCore

/// Preview and export share one worker because each mesher already uses all cores.
actor ConversionQueue {
    typealias Convert = @Sendable (URL, URL, ConversionOptions) throws -> ConversionReport
    private let convert: Convert

    init(convert: @escaping Convert = { source, output, options in
        try Converter.convert(svg: source, to: output, options: options)
    }) {
        self.convert = convert
    }

    func run(source: URL, output: URL, options: ConversionOptions) throws -> ConversionReport {
        try Task.checkCancellation()
        do {
            let report = try convert(source, output, options)
            try Task.checkCancellation()
            return report
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
