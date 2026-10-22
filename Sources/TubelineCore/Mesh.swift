import Foundation
import simd

public struct Mesh: Sendable {
    public var positions: [SIMD3<Float>] = []
    public var normals: [SIMD3<Float>] = []
    public var indices: [UInt32] = []
    public var warnings: [String] = []

    public var triangleCount: Int { indices.count / 3 }

    public var bounds: Box3 {
        var b = Box3()
        for p in positions { b.include(Vec3(Double(p.x), Double(p.y), Double(p.z))) }
        return b
    }
}

/// Checks the exported surface after welding vertices duplicated for hard normals.
/// Disconnected closed components are valid, as with a dotted icon.
public struct MeshValidation: Sendable {
    public var boundaryEdges = 0
    public var nonManifoldEdges = 0
    public var inconsistentEdges = 0
    public var degenerateTriangles = 0
    public var duplicateTriangles = 0
    public var invalidVertices = 0
    public var invalidNormals = 0
    public var invalidVertexLinks = 0
    public var invalidIndices = 0

    public var isValid: Bool {
        boundaryEdges + nonManifoldEdges + inconsistentEdges + degenerateTriangles
            + duplicateTriangles + invalidVertices + invalidNormals + invalidVertexLinks + invalidIndices == 0
    }

    public var summary: String {
        let values = [(boundaryEdges, "boundary edges"), (nonManifoldEdges, "non-manifold edges"),
                      (inconsistentEdges, "inconsistently wound edges"), (degenerateTriangles, "degenerate triangles"),
                      (duplicateTriangles, "duplicate triangles"), (invalidVertices, "invalid vertices"), (invalidNormals, "invalid normals"),
                      (invalidVertexLinks, "non-manifold vertices"), (invalidIndices, "invalid indices")]
        return values.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }
}

public extension Mesh {
    func validation() -> MeshValidation { validation(checkAllFailures: true) }

    internal func validation(checkAllFailures: Bool) -> MeshValidation {
        var result = MeshValidation()
        if normals.count != positions.count { result.invalidNormals += 1 }
        result.invalidNormals += normals.filter { !$0.x.isFinite || !$0.y.isFinite || !$0.z.isFinite || simd_length_squared($0) == 0 }.count
        var ids: [SIMD3<Float>: Int] = [:]
        var welded = [Int](repeating: -1, count: positions.count)
        for (i, p) in positions.enumerated() {
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { result.invalidVertices += 1; continue }
            if let id = ids[p] { welded[i] = id } else { welded[i] = ids.count; ids[p] = ids.count }
        }
        struct EdgeUse { var count = 0; var winding = 0 }
        var edges: [SIMD2<Int>: EdgeUse] = [:]
        var faces = Set<SIMD3<Int>>()
        var links = [[SIMD2<Int>]](repeating: [], count: ids.count)
        if indices.count % 3 != 0 { result.invalidIndices += 1 }
        for t in stride(from: 0, to: indices.count - indices.count % 3, by: 3) {
            let raw = (0..<3).map { Int(indices[t + $0]) }
            guard raw.allSatisfy({ $0 < welded.count && welded[$0] >= 0 }) else {
                result.invalidIndices += 1; continue
            }
            let v = raw.map { welded[$0] }
            let p = raw.map { Vec3(positions[$0]) }
            guard Set(v).count == 3, simd_length_squared(simd_cross(p[1] - p[0], p[2] - p[0])) > 0 else {
                result.degenerateTriangles += 1; continue
            }
            let sorted = v.sorted()
            if !faces.insert(SIMD3(sorted[0], sorted[1], sorted[2])).inserted { result.duplicateTriangles += 1 }
            for k in 0..<3 {
                let a = v[k], b = v[(k + 1) % 3]
                let key = SIMD2(min(a, b), max(a, b))
                edges[key, default: EdgeUse()].count += 1
                edges[key, default: EdgeUse()].winding += a < b ? 1 : -1
                links[a].append(SIMD2(b, v[(k + 2) % 3]))
            }
        }
        for use in edges.values {
            if use.count == 1 { result.boundaryEdges += 1 }
            else if use.count != 2 { result.nonManifoldEdges += 1 }
            if use.count == 2 && use.winding != 0 { result.inconsistentEdges += 1 }
        }
        // Meshing retries need only a verdict. A known failure cannot become valid
        // after checking vertex links; preserve the complete public report by default.
        if !checkAllFailures && !result.isValid { return result }
        for link in links where !link.isEmpty {
            var adjacency: [Int: [Int]] = [:]
            for edge in link {
                adjacency[edge.x, default: []].append(edge.y)
                adjacency[edge.y, default: []].append(edge.x)
            }
            guard adjacency.values.allSatisfy({ $0.count == 2 }) else { result.invalidVertexLinks += 1; continue }
            var visited = Set<Int>(), pending = [link[0].x]
            while let v = pending.popLast() {
                if visited.insert(v).inserted { pending.append(contentsOf: adjacency[v] ?? []) }
            }
            if visited.count != adjacency.count { result.invalidVertexLinks += 1 }
        }
        return result
    }
}
