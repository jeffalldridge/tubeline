import Foundation

struct ConversionStats: Equatable {
    var triangles: Int
    var vertices: Int
    var seconds: Double
    var skipped: [String]
    var dimensions: SIMD3<Double>
}
