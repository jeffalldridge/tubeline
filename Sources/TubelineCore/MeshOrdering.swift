import Foundation
import simd

extension Mesh {
    /// Reorders triangles along a Morton (Z-order) curve and renumbers vertices by first use,
    /// so neighboring triangles share recently transformed vertices and vertex reads walk
    /// memory forward. The geometry is unchanged but cheaper to draw, which matters when dozens of
    /// icons are animated at once.
    mutating func optimizeForGPU() {
        let triCount = triangleCount
        guard triCount > 1 else { return }
        let b = bounds
        let scale = 1023 / simd_max(b.size, Vec3(repeating: 1e-12))

        func spread(_ v: UInt32) -> UInt32 {
            var x = v & 0x3FF
            x = (x | (x << 16)) & 0x0300_00FF
            x = (x | (x << 8)) & 0x0300_F00F
            x = (x | (x << 4)) & 0x030C_30C3
            x = (x | (x << 2)) & 0x0924_9249
            return x
        }
        var keys = [(code: UInt32, tri: Int)]()
        keys.reserveCapacity(triCount)
        for t in 0..<triCount {
            var c = SIMD3<Float>.zero
            for k in 0..<3 { c += positions[Int(indices[t * 3 + k])] }
            let q = simd_clamp((Vec3(c / 3) - b.min) * scale, .zero, Vec3(repeating: 1023))
            let code = spread(UInt32(q.x)) | spread(UInt32(q.y)) << 1 | spread(UInt32(q.z)) << 2
            keys.append((code, t))
        }
        keys.sort { $0.code < $1.code }

        var remap = [Int32](repeating: -1, count: positions.count)
        var newPositions: [SIMD3<Float>] = [], newNormals: [SIMD3<Float>] = []
        newPositions.reserveCapacity(positions.count)
        newNormals.reserveCapacity(normals.count)
        var newIndices = [UInt32]()
        newIndices.reserveCapacity(indices.count)
        for (_, t) in keys {
            for k in 0..<3 {
                let v = Int(indices[t * 3 + k])
                if remap[v] < 0 {
                    remap[v] = Int32(newPositions.count)
                    newPositions.append(positions[v])
                    newNormals.append(normals[v])
                }
                newIndices.append(UInt32(remap[v]))
            }
        }
        positions = newPositions
        normals = newNormals
        indices = newIndices
    }
}
