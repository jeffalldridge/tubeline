import Foundation
import simd

/// Quadric error metric (Garland–Heckbert): sum of squared distances to a set of planes.
struct Quadric {
    // Symmetric 3×3 part, linear part, constant.
    var a00 = 0.0, a01 = 0.0, a02 = 0.0, a11 = 0.0, a12 = 0.0, a22 = 0.0
    var b = Vec3.zero
    var c = 0.0

    init() {}

    /// Plane n·x + d = 0 with unit normal n.
    init(normal n: Vec3, d: Double) {
        a00 = n.x * n.x; a01 = n.x * n.y; a02 = n.x * n.z
        a11 = n.y * n.y; a12 = n.y * n.z; a22 = n.z * n.z
        b = n * d
        c = d * d
    }

    static func += (q: inout Quadric, o: Quadric) {
        q.a00 += o.a00; q.a01 += o.a01; q.a02 += o.a02
        q.a11 += o.a11; q.a12 += o.a12; q.a22 += o.a22
        q.b += o.b; q.c += o.c
    }

    var matrix: simd_double3x3 {
        simd_double3x3(rows: [Vec3(a00, a01, a02), Vec3(a01, a11, a12), Vec3(a02, a12, a22)])
    }

    func error(_ v: Vec3) -> Double {
        max(0, simd_dot(v, matrix * v) + 2 * simd_dot(b, v) + c)
    }

    /// Minimizer, lightly regularized towards `anchor` so flat and cylindrical regions
    /// (where the quadric is singular along the surface) stay well defined.
    func optimum(near anchor: Vec3) -> Vec3 {
        let m = matrix
        let lambda = max((a00 + a11 + a22) * 1e-3, 1e-12)
        let reg = m + simd_double3x3(diagonal: Vec3(repeating: lambda))
        guard abs(reg.determinant) > 1e-24 else { return anchor }
        return reg.inverse * (lambda * anchor - b)
    }
}

/// Edge-collapse simplification of a closed mesh. Collapses are ordered by quadric error, and
/// each one is accepted only if the result stays within `maxError` of the exact surface (checked
/// against the signed distance field at the new vertex and across every changed triangle), keeps
/// the mesh manifold, and flips no triangle. Long runs of tube collapse to long thin quads while
/// curves, creases and fillets keep the detail they need.
struct Decimator {
    private(set) var positions: [Vec3]
    private(set) var crease: [Bool]
    private var triangles: [SIMD3<Int32>]
    private var triAlive: [Bool]
    private var vertexAlive: [Bool]
    private var vertexTris: [[Int32]]
    private var quadrics: [Quadric]
    private var version: [Int32]
    /// Vertices that must not move or disappear (shared with a neighboring tile).
    private let locked: [Bool]

    let maxError: Double
    let distance: (Vec3) -> Double

    init(positions: [Vec3], triangles: [SIMD3<Int32>], crease: [Bool], locked: [Bool]? = nil,
         maxError: Double, distance: @escaping (Vec3) -> Double) {
        self.positions = positions
        self.locked = locked ?? [Bool](repeating: false, count: positions.count)
        self.triangles = triangles
        self.crease = crease
        self.maxError = maxError
        self.distance = distance
        triAlive = [Bool](repeating: true, count: triangles.count)
        vertexAlive = [Bool](repeating: true, count: positions.count)
        vertexTris = [[Int32]](repeating: [], count: positions.count)
        quadrics = [Quadric](repeating: Quadric(), count: positions.count)
        version = [Int32](repeating: 0, count: positions.count)

        for (t, tri) in triangles.enumerated() {
            for k in 0..<3 { vertexTris[Int(tri[k])].append(Int32(t)) }
            let p0 = positions[Int(tri.x)], p1 = positions[Int(tri.y)], p2 = positions[Int(tri.z)]
            let n = simd_cross(p1 - p0, p2 - p0)
            let len = simd_length(n)
            guard len > 1e-20 else { continue }
            let q = Quadric(normal: n / len, d: -simd_dot(n / len, p0))
            for k in 0..<3 { quadrics[Int(tri[k])] += q }
        }
    }

    // MARK: Running

    private struct Candidate: Comparable {
        var cost: Double
        var a: Int32, b: Int32
        var va: Int32, vb: Int32
        static func < (l: Candidate, r: Candidate) -> Bool { l.cost < r.cost }
    }

    mutating func run() {
        var heap = MinHeap<Candidate>()
        var seen = Set<UInt64>()
        for tri in triangles {
            for k in 0..<3 {
                let a = min(tri[k], tri[(k + 1) % 3]), b = max(tri[k], tri[(k + 1) % 3])
                if locked[Int(a)] || locked[Int(b)] { continue }
                if seen.insert(UInt64(a) << 32 | UInt64(b)).inserted { heap.push(candidate(a, b)) }
            }
        }
        while let c = heap.pop() {
            let a = Int(c.a), b = Int(c.b)
            guard vertexAlive[a], vertexAlive[b], version[a] == c.va, version[b] == c.vb else { continue }
            let target = targetPosition(a, b)
            guard let shared = validate(a, b, target) else { continue }
            collapse(keep: a, remove: b, at: target, shared: shared)
            for n in neighbors(a) where !locked[n] {
                heap.push(candidate(Int32(a), Int32(n)))
            }
        }
    }

    /// Compacted result: positions, triangles and crease flags of surviving vertices, plus each
    /// vertex's index in the input (`source`).
    func output() -> (positions: [Vec3], triangles: [SIMD3<Int32>], crease: [Bool], source: [Int]) {
        var remap = [Int32](repeating: -1, count: positions.count)
        var pos: [Vec3] = [], cr: [Bool] = [], src: [Int] = []
        var tris: [SIMD3<Int32>] = []
        for (t, tri) in triangles.enumerated() where triAlive[t] {
            var out = SIMD3<Int32>()
            for k in 0..<3 {
                let v = Int(tri[k])
                if remap[v] < 0 {
                    remap[v] = Int32(pos.count)
                    pos.append(positions[v]); cr.append(crease[v]); src.append(v)
                }
                out[k] = remap[v]
            }
            tris.append(out)
        }
        return (pos, tris, cr, src)
    }

    // MARK: Collapse steps

    private func candidate(_ a: Int32, _ b: Int32) -> Candidate {
        let (x, y) = a < b ? (a, b) : (b, a)
        var q = quadrics[Int(x)]
        q += quadrics[Int(y)]
        let p = targetPosition(Int(x), Int(y))
        return Candidate(cost: q.error(p), a: x, b: y, va: version[Int(x)], vb: version[Int(y)])
    }

    private func targetPosition(_ a: Int, _ b: Int) -> Vec3 {
        var q = quadrics[a]
        q += quadrics[b]
        let mid = (positions[a] + positions[b]) * 0.5
        var p = q.optimum(near: mid)
        // Never let the optimum wander off along a near-singular direction.
        let reach = simd_distance(positions[a], positions[b])
        if simd_distance(p, mid) > reach { p = mid }
        return p
    }

    private func neighbors(_ v: Int) -> Set<Int> {
        var s = Set<Int>()
        for t in vertexTris[v] where triAlive[Int(t)] {
            let tri = triangles[Int(t)]
            for k in 0..<3 where Int(tri[k]) != v { s.insert(Int(tri[k])) }
        }
        return s
    }

    @inline(__always) private func contains(_ tri: SIMD3<Int32>, _ v: Int32) -> Bool {
        tri.x == v || tri.y == v || tri.z == v
    }

    /// Returns the two triangles shared by edge a–b if collapsing it to `p` is safe.
    /// Cheap topological and orientation checks run first; exact-surface probes run last.
    private func validate(_ a: Int, _ b: Int, _ p: Vec3) -> (Int, Int)? {
        let a32 = Int32(a), b32 = Int32(b)
        var shared = (-1, -1)
        var sharedCount = 0
        for t in vertexTris[a] where triAlive[Int(t)] && contains(triangles[Int(t)], b32) {
            if sharedCount == 0 { shared.0 = Int(t) } else { shared.1 = Int(t) }
            sharedCount += 1
        }
        guard sharedCount == 2 else { return nil }

        // Link condition: the endpoints may share only the two vertices opposite the edge,
        // otherwise the collapse would pinch the surface into a non-manifold fold.
        var common = 0
        var seenA: [Int32] = []
        seenA.reserveCapacity(16)
        for t in vertexTris[a] where triAlive[Int(t)] {
            let tri = triangles[Int(t)]
            for k in 0..<3 where tri[k] != a32 && !seenA.contains(tri[k]) { seenA.append(tri[k]) }
        }
        var seenB: [Int32] = []
        seenB.reserveCapacity(16)
        for t in vertexTris[b] where triAlive[Int(t)] {
            let tri = triangles[Int(t)]
            for k in 0..<3 where tri[k] != b32 && !seenB.contains(tri[k]) {
                seenB.append(tri[k])
                if seenA.contains(tri[k]) { common += 1 }
            }
        }
        guard common == 2 else { return nil }

        // Orientation: no remaining triangle may flip or collapse to a sliver.
        for v in [a, b] {
            for t in vertexTris[v] where triAlive[Int(t)] && Int(t) != shared.0 && Int(t) != shared.1 {
                let tri = triangles[Int(t)]
                let o0 = positions[Int(tri.x)], o1 = positions[Int(tri.y)], o2 = positions[Int(tri.z)]
                let n0 = tri.x == a32 || tri.x == b32 ? p : o0
                let n1 = tri.y == a32 || tri.y == b32 ? p : o1
                let n2 = tri.z == a32 || tri.z == b32 ? p : o2
                let before = simd_cross(o1 - o0, o2 - o0), after = simd_cross(n1 - n0, n2 - n0)
                let lb = simd_length(before), la = simd_length(after)
                guard la > 1e-14 else { return nil }
                if lb > 1e-14, simd_dot(before, after) < 0.2 * lb * la { return nil }
            }
        }

        // Geometry: the new vertex and every changed triangle must hug the true surface,
        // never cutting through the tube or across a crease.
        guard abs(distance(p)) <= maxError else { return nil }
        for v in [a, b] {
            for t in vertexTris[v] where triAlive[Int(t)] && Int(t) != shared.0 && Int(t) != shared.1 {
                let tri = triangles[Int(t)]
                let n0 = tri.x == a32 || tri.x == b32 ? p : positions[Int(tri.x)]
                let n1 = tri.y == a32 || tri.y == b32 ? p : positions[Int(tri.y)]
                let n2 = tri.z == a32 || tri.z == b32 ? p : positions[Int(tri.z)]
                if abs(distance((n0 + n1 + n2) / 3)) > maxError { return nil }
                if abs(distance((n0 + n1) * 0.5)) > maxError { return nil }
                if abs(distance((n1 + n2) * 0.5)) > maxError { return nil }
                if abs(distance((n2 + n0) * 0.5)) > maxError { return nil }
            }
        }
        return shared
    }

    private mutating func collapse(keep a: Int, remove b: Int, at p: Vec3, shared: (Int, Int)) {
        triAlive[shared.0] = false
        triAlive[shared.1] = false
        positions[a] = p
        quadrics[a] += quadrics[b]
        crease[a] = crease[a] || crease[b]
        for t in vertexTris[b] where triAlive[Int(t)] {
            var tri = triangles[Int(t)]
            for k in 0..<3 where tri[k] == Int32(b) { tri[k] = Int32(a) }
            triangles[Int(t)] = tri
            vertexTris[a].append(t)
        }
        vertexTris[a].removeAll { !triAlive[Int($0)] }
        vertexTris[b] = []
        vertexAlive[b] = false
        version[a] += 1
    }
}

/// Binary min-heap.
struct MinHeap<T: Comparable> {
    private var items: [T] = []

    mutating func push(_ x: T) {
        items.append(x)
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard items[i] < items[parent] else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> T? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count, items[l] < items[m] { m = l }
                if r < items.count, items[r] < items[m] { m = r }
                if m == i { break }
                items.swapAt(i, m)
                i = m
            }
        }
        return top
    }
}
