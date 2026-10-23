import Foundation
import simd

/// Exact distance to the whole icon near a point, for snapping vertices and checking
/// simplification. Data is flattened into plain arrays (no nested arrays, no class references
/// on the hot path) because it is queried millions of times from many threads at once.
struct SpatialLookup {
    private struct Flat {
        enum Kind: UInt8 { case capsule, cylinder, sphere, slab, clippedCapsule }
        var kind: Kind
        var group: Int32
        var slab: Int32
        var a: Vec3
        var b: Vec3
        var r: Double
        var startClip: TubeClip? = nil
        var endClip: TubeClip? = nil
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
                case let .clippedCapsule(a, b, r, start, end):
                    flat.append(Flat(kind: .clippedCapsule, group: Int32(gi), slab: -1, a: a, b: b, r: r, startClip: start, endClip: end))
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

    @inline(__always) private func distance(_ f: Flat, _ p: Vec3) -> Double {
        switch f.kind {
        case .capsule:
            let pa = p - f.a, ba = f.b - f.a
            let h = simd_clamp(simd_dot(pa, ba) / max(simd_dot(ba, ba), 1e-30), 0, 1)
            return simd_length(pa - ba * h) - f.r
        case .clippedCapsule:
            let pa = p - f.a, ba = f.b - f.a
            let t = simd_clamp(simd_dot(pa, ba) / max(simd_dot(ba, ba), 1e-30), 0, 1)
            var d = simd_length(pa - ba * t) - f.r
            if let start = f.startClip { d = max(d, start.distance(p)) }
            if let end = f.endClip { d = max(d, end.distance(p)) }
            return d
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
                // Without blending the union is simply the nearest primitive. This is the default
                // and the hot path, so it stays free of allocations.
                if blend <= 0 {
                    var d = Double.infinity
                    for k in lo..<hi { d = min(d, distance(prims[Int(items[k])], p)) }
                    return d.isInfinite ? 1e9 : d
                }
                // Each group's distance is the min over its primitives in this bucket (which are
                // stored grouped). The union is the nearest group, lowered by the strongest fillet
                // it forms with any other group nearby.
                var groupDistance: [Double] = []
                var groupRange: [Range<Int>] = []
                var currentGroup: Int32 = -1
                for k in lo..<hi {
                    let f = prims[Int(items[k])]
                    let d = distance(f, p)
                    if f.group != currentGroup {
                        currentGroup = f.group
                        groupDistance.append(d)
                        groupRange.append(k..<k + 1)
                    } else {
                        groupDistance[groupDistance.count - 1] = min(groupDistance[groupDistance.count - 1], d)
                        groupRange[groupRange.count - 1] = groupRange[groupRange.count - 1].lowerBound..<k + 1
                    }
                }
                guard let nearest = groupDistance.indices.min(by: { groupDistance[$0] < groupDistance[$1] }) else { return 1e9 }
                let result = groupDistance[nearest]
                guard blend > 0 else { return result }

                func groupAt(_ g: Int, _ x: Vec3) -> Double {
                    var d = Double.infinity
                    for k in groupRange[g] { d = min(d, distance(prims[Int(items[k])], x)) }
                    return d
                }
                /// Unit surface direction of group `g` near `p`. Using the whole stroke, not just its
                /// nearest segment, keeps the direction smooth along curves and polylines.
                func direction(_ g: Int) -> Vec3 {
                    let e = cell * 0.01
                    let grad = Vec3(groupAt(g, p + Vec3(e, 0, 0)) - groupAt(g, p - Vec3(e, 0, 0)),
                                    groupAt(g, p + Vec3(0, e, 0)) - groupAt(g, p - Vec3(0, e, 0)),
                                    groupAt(g, p + Vec3(0, 0, e)) - groupAt(g, p - Vec3(0, 0, e)))
                    let length = simd_length(grad)
                    return length > 1e-12 ? grad / length : Vec3(0, 0, 1)
                }

                // A plain smooth union also inflates places where one stroke sits inside or against
                // another with parallel surfaces: the top of a T, where the upright's rounded end
                // touches the bar's top from inside, or the front of any crossing, where both tubes
                // face the viewer. Those aren't joints, so the fillet fades out as the two surfaces
                // become parallel and is full where they meet at a real angle, such as the
                // underside of a T. The fade is gradual so the fillet narrows smoothly.
                // Every pair of nearby groups forms its own smooth union, and the surface is the
                // minimum of them all. That is symmetric in the groups, so the field stays
                // continuous where three or more strokes meet and the nearest one changes.
                let nearby = groupDistance.indices.filter { groupDistance[$0] - result < blend }
                guard nearby.count > 1 else { return result }
                let directions = nearby.map(direction)
                var union = result
                for a in 0..<nearby.count {
                    for b in (a + 1)..<nearby.count {
                        let da = groupDistance[nearby[a]], db = groupDistance[nearby[b]]
                        let c = simd_dot(directions[a], directions[b])
                        let t = simd_clamp((0.9 - c) / 0.8, 0, 1)  // none above ~26°, full past ~96°
                        let k = blend * t * t * (3 - 2 * t)
                        guard k > 0 else { continue }
                        let h = max(k - abs(da - db), 0) / k
                        union = min(union, min(da, db) - h * h * k * 0.25)
                    }
                }
                return union
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
