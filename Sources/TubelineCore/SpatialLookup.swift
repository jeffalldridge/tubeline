import Foundation
import simd

/// Exact distance to the whole icon near a point, for snapping vertices and checking
/// simplification. Data is flattened into plain arrays (no nested arrays, no class references
/// on the hot path) because it is queried millions of times from many threads at once.
struct SpatialLookup {
    private struct Flat {
        enum Kind: UInt8 { case capsule, cylinder, sphere, slab }
        var kind: Kind
        var group: Int32
        var slab: Int32
        var a: Vec3
        var b: Vec3
        var r: Double
    }

    private let prims: [Flat]
    private let slabs: [SlabRegion]
    private let slabRefs: [Unmanaged<SlabRegion>]
    private let cell: Double
    private let origin: Vec2
    private let nx: Int, ny: Int
    /// Bucket b holds bucketItems[bucketStart[b] ..< bucketStart[b + 1]], sorted by group.
    private let bucketStart: [Int32]
    private let bucketItems: [Int32]
    private let blend: Double

    init(groups: [PrimitiveGroup], cell: Double, pad: Double, blend: Double) {
        self.cell = cell
        self.blend = blend
        var flat: [Flat] = []
        var slabs: [SlabRegion] = []
        var bounds: [Box3] = []
        for (gi, g) in groups.enumerated() {
            for p in g.primitives {
                switch p {
                case let .capsule(a, b, r): flat.append(Flat(kind: .capsule, group: Int32(gi), slab: -1, a: a, b: b, r: r))
                case let .cylinder(a, b, r): flat.append(Flat(kind: .cylinder, group: Int32(gi), slab: -1, a: a, b: b, r: r))
                case let .sphere(c, r): flat.append(Flat(kind: .sphere, group: Int32(gi), slab: -1, a: c, b: c, r: r))
                case let .slab(s):
                    flat.append(Flat(kind: .slab, group: Int32(gi), slab: Int32(slabs.count), a: .zero, b: .zero, r: 0))
                    slabs.append(s)
                }
                bounds.append(p.bounds.expanded(by: pad))
            }
        }
        prims = flat
        self.slabs = slabs
        slabRefs = slabs.map { Unmanaged.passUnretained($0) }

        var total = Box3()
        for g in groups { total.include(g.bounds) }
        let o = Vec2(total.min.x, total.min.y) - Vec2(repeating: pad + cell)
        origin = o
        let nx = Int(ceil((total.size.x + 2 * (pad + cell)) / cell)) + 1
        let ny = Int(ceil((total.size.y + 2 * (pad + cell)) / cell)) + 1
        self.nx = nx
        self.ny = ny

        // Two passes: count per bucket, then fill (prims are already in group order).
        var counts = [Int32](repeating: 0, count: nx * ny + 1)
        func cells(_ b: Box3) -> (ClosedRange<Int>, ClosedRange<Int>)? {
            let i0 = max(0, Int(floor((b.min.x - o.x) / cell))), i1 = min(nx - 1, Int(floor((b.max.x - o.x) / cell)))
            let j0 = max(0, Int(floor((b.min.y - o.y) / cell))), j1 = min(ny - 1, Int(floor((b.max.y - o.y) / cell)))
            return i0 <= i1 && j0 <= j1 ? (i0...i1, j0...j1) : nil
        }
        for b in bounds {
            guard let (ri, rj) = cells(b) else { continue }
            for j in rj { for i in ri { counts[i + nx * j + 1] += 1 } }
        }
        for k in 1..<counts.count { counts[k] += counts[k - 1] }
        var items = [Int32](repeating: 0, count: Int(counts[counts.count - 1]))
        var fill = counts
        for (pi, b) in bounds.enumerated() {
            guard let (ri, rj) = cells(b) else { continue }
            for j in rj {
                for i in ri {
                    items[Int(fill[i + nx * j])] = Int32(pi)
                    fill[i + nx * j] += 1
                }
            }
        }
        bucketStart = counts
        bucketItems = items
    }

    @inline(__always) private func smin(_ a: Double, _ b: Double) -> Double {
        guard blend > 0 else { return min(a, b) }
        let h = max(blend - abs(a - b), 0) / blend
        return min(a, b) - h * h * blend * 0.25
    }

    @inline(__always) private func distance(_ f: Flat, _ p: Vec3) -> Double {
        switch f.kind {
        case .capsule:
            let pa = p - f.a, ba = f.b - f.a
            let h = simd_clamp(simd_dot(pa, ba) / max(simd_dot(ba, ba), 1e-30), 0, 1)
            return simd_length(pa - ba * h) - f.r
        case .sphere:
            return simd_distance(p, f.a) - f.r
        case .cylinder:
            return Primitive.cylinder(f.a, f.b, f.r).distance(p)
        case .slab:
            return slabRefs[Int(f.slab)]._withUnsafeGuaranteedRef { s in
                s.distance(planar: s.planarDistance(Vec2(p.x, p.y)), z: p.z)
            }
        }
    }

    func distance(_ p: Vec3) -> Double {
        let i = Int(floor((p.x - origin.x) / cell)), j = Int(floor((p.y - origin.y) / cell))
        guard i >= 0, j >= 0, i < nx, j < ny else { return 1e9 }
        let b = i + nx * j
        let lo = Int(bucketStart[b]), hi = Int(bucketStart[b + 1])
        guard lo < hi else { return 1e9 }
        return prims.withUnsafeBufferPointer { prims in
            bucketItems.withUnsafeBufferPointer { items in
                var result = Double.infinity
                var groupMin = Double.infinity
                var currentGroup: Int32 = -1
                for k in lo..<hi {
                    let f = prims[Int(items[k])]
                    if f.group != currentGroup {
                        if currentGroup >= 0 { result = result.isInfinite ? groupMin : smin(result, groupMin) }
                        currentGroup = f.group
                        groupMin = .infinity
                    }
                    groupMin = min(groupMin, distance(f, p))
                }
                result = result.isInfinite ? groupMin : smin(result, groupMin)
                return result.isInfinite ? 1e9 : result
            }
        }
    }

    /// Point where the exact surface crosses the segment a→b (signs at the ends differ).
    func edgeCrossing(_ a: Vec3, _ b: Vec3, _ da: Double, _ db: Double) -> Vec3 {
        var lo = a, hi = b, dlo = da, dhi = db
        var p = a + (b - a) * (da / (da - db))
        for _ in 0..<6 {
            let d = distance(p)
            if abs(d) < 1e-7 { break }
            if (d < 0) == (dlo < 0) { lo = p; dlo = d } else { hi = p; dhi = d }
            let t = dlo / (dlo - dhi)
            p = lo + (hi - lo) * (t.isFinite ? simd_clamp(t, 0.05, 0.95) : 0.5)
        }
        return p
    }

    func gradient(_ p: Vec3, eps: Double) -> Vec3 {
        let dx = distance(p + Vec3(eps, 0, 0)) - distance(p - Vec3(eps, 0, 0))
        let dy = distance(p + Vec3(0, eps, 0)) - distance(p - Vec3(0, eps, 0))
        let dz = distance(p + Vec3(0, 0, eps)) - distance(p - Vec3(0, 0, eps))
        let g = Vec3(dx, dy, dz)
        let len = simd_length(g)
        return len > 1e-12 ? g / len : Vec3(0, 0, 1)
    }
}
