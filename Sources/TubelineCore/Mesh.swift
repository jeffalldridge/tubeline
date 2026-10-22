import Foundation
import simd

public struct Mesh: Sendable {
    public var positions: [SIMD3<Float>] = []
    public var normals: [SIMD3<Float>] = []
    public var indices: [UInt32] = []

    public var triangleCount: Int { indices.count / 3 }

    public var bounds: Box3 {
        var b = Box3()
        for p in positions { b.include(Vec3(Double(p.x), Double(p.y), Double(p.z))) }
        return b
    }
}
