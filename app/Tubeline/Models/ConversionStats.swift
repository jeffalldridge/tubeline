import Foundation
import TubelineCore

struct ConversionStats: Equatable {
    var triangles: Int
    var vertices: Int
    var seconds: Double
    var skipped: [String]
    var dimensions: SIMD3<Double>
}

extension ConversionStats {
    init(_ report: TubelineCore.ConversionReport) {
        self.init(triangles: report.triangles, vertices: report.vertices, seconds: report.seconds,
                  skipped: report.skipped, dimensions: report.dimensions)
    }
}
