import Foundation
import simd

/// One solid piece of the icon in output space (z = 0 is the icon plane).
enum Primitive {
    /// Segment with round ends.
    case capsule(Vec3, Vec3, Double)
    /// Segment with flat ends.
    case cylinder(Vec3, Vec3, Double)
    case sphere(Vec3, Double)
    /// Filled planar region, either rounded like an outline or straight-extruded.
    case slab(SlabRegion)

    var bounds: Box3 {
        switch self {
        case let .capsule(a, b, r), let .cylinder(a, b, r):
            var box = Box3(); box.include(a); box.include(b)
            return box.expanded(by: r)
        case let .sphere(c, r):
            return Box3(min: c - Vec3(repeating: r), max: c + Vec3(repeating: r))
        case let .slab(s):
            return s.bounds
        }
    }

    func distance(_ p: Vec3) -> Double {
        switch self {
        case let .capsule(a, b, r):
            let pa = p - a, ba = b - a
            let h = simd_clamp(simd_dot(pa, ba) / max(simd_dot(ba, ba), 1e-30), 0, 1)
            return simd_length(pa - ba * h) - r
        case let .cylinder(a, b, r):
            // Exact capped-cylinder distance (Inigo Quilez).
            let ba = b - a, pa = p - a
            let baba = simd_dot(ba, ba), paba = simd_dot(pa, ba)
            guard baba > 1e-30 else { return simd_length(pa) - r }
            let x = simd_length(pa * baba - ba * paba) - r * baba
            let y = abs(paba - baba * 0.5) - baba * 0.5
            let x2 = x * x, y2 = y * y * baba
            let d = max(x, y) < 0 ? -min(x2, y2) : ((x > 0 ? x2 : 0) + (y > 0 ? y2 : 0))
            return (d < 0 ? -1 : 1) * sqrt(abs(d)) / baba
        case let .sphere(c, r):
            return simd_distance(p, c) - r
        case let .slab(s):
            return s.distance(planar: s.planarDistance(Vec2(p.x, p.y)), z: p.z)
        }
    }
}

final class SlabRegion {
    enum Profile {
        /// The area grown by a ball: flat faces with a fully rounded rim, as thick as an outline tube.
        case rounded(radius: Double)
        /// Straight extrusion of the area, with optionally rounded edges.
        case extruded(halfDepth: Double, edgeRadius: Double)
    }

    let edges: [(Vec2, Vec2)]
    let evenOdd: Bool
    let profile: Profile
    let bounds: Box3

    init(contours: [[Vec2]], evenOdd: Bool, profile: Profile) {
        var e: [(Vec2, Vec2)] = []
        var b = Box3()
        for c in contours where c.count >= 3 {
            for i in 0..<c.count {
                e.append((c[i], c[(i + 1) % c.count]))
                b.include(Vec3(c[i].x, c[i].y, 0))
            }
        }
        edges = e
        self.evenOdd = evenOdd
        self.profile = profile
        switch profile {
        case .rounded(let r):
            bounds = b.expanded(by: r)
        case .extruded(let hd, _):
            b.min.z = -hd; b.max.z = hd
            bounds = b
        }
    }

    /// 3D distance given the signed planar distance (negative inside) and height above the plane.
    func distance(planar d: Double, z: Double) -> Double {
        switch profile {
        case .rounded(let r):
            let dxy = max(d, 0)
            return (dxy * dxy + z * z).squareRoot() - r
        case .extruded(let hd, let er):
            let e = min(er, hd)
            let w = Vec2(d + e, abs(z) - hd + e)
            return min(max(w.x, w.y), 0) + simd_length(simd_max(w, .zero)) - e
        }
    }

    // Acceleration: outline edges bucketed on a 2D grid (for distance) and by horizontal band
    // (for the winding number). Distances only need to be exact within `band` of the outline;
    // farther away a clamped value gives identical surfaces.
    private var band = Double.infinity
    private var cell = 1.0
    private var origin = Vec2.zero
    private var gx = 0, gy = 0
    private var grid: [[Int32]] = []
    private var rows: [[Int32]] = []

    /// Builds the lookup grids. `band` must cover the slab's rounding plus the meshing margin.
    func prepare(band: Double) {
        guard !edges.isEmpty, band.isFinite, band > 0 else { return }
        self.band = band
        let lo = Vec2(bounds.min.x, bounds.min.y) - band, hi = Vec2(bounds.max.x, bounds.max.y) + band
        cell = band
        origin = lo
        gx = max(1, Int(ceil((hi.x - lo.x) / cell)))
        gy = max(1, Int(ceil((hi.y - lo.y) / cell)))
        grid = [[Int32]](repeating: [], count: gx * gy)
        rows = [[Int32]](repeating: [], count: gy)
        for (e, (a, b)) in edges.enumerated() {
            let i0 = cellX(min(a.x, b.x)), i1 = cellX(max(a.x, b.x))
            let j0 = cellY(min(a.y, b.y)), j1 = cellY(max(a.y, b.y))
            for j in j0...j1 {
                rows[j].append(Int32(e))
                for i in i0...i1 { grid[i + gx * j].append(Int32(e)) }
            }
        }
    }

    private func cellX(_ x: Double) -> Int { min(gx - 1, max(0, Int(floor((x - origin.x) / cell)))) }
    private func cellY(_ y: Double) -> Int { min(gy - 1, max(0, Int(floor((y - origin.y) / cell)))) }

    /// Signed distance from `p` to the filled area's outline in the plane (negative inside),
    /// exact within `band` and clamped to ±band beyond it.
    func planarDistance(_ p: Vec2) -> Double {
        guard !grid.isEmpty else { return bruteForceDistance(p) }
        let ci = Int(floor((p.x - origin.x) / cell)), cj = Int(floor((p.y - origin.y) / cell))
        // Winding number from the edges crossing this point's horizontal band only.
        var winding = 0
        if cj >= 0 && cj < gy {
            for e in rows[cj] { winding += crossing(edges[Int(e)], p) }
        }
        let inside = evenOdd ? (winding & 1) != 0 : winding != 0
        var best = band * band
        for j in max(0, cj - 1)...min(gy - 1, cj + 1) where cj + 1 >= 0 && cj - 1 < gy {
            for i in max(0, ci - 1)...min(gx - 1, ci + 1) where ci + 1 >= 0 && ci - 1 < gx {
                for e in grid[i + gx * j] {
                    let (a, b) = edges[Int(e)]
                    let ba = b - a, pa = p - a
                    let h = simd_clamp(simd_dot(pa, ba) / max(simd_dot(ba, ba), 1e-30), 0, 1)
                    best = min(best, simd_length_squared(pa - ba * h))
                }
            }
        }
        let d = best.squareRoot()
        return inside ? -d : d
    }

    private func bruteForceDistance(_ p: Vec2) -> Double {
        var winding = 0
        var best = Double.infinity
        for edge in edges {
            let (a, b) = edge
            let ba = b - a, pa = p - a
            let h = simd_clamp(simd_dot(pa, ba) / max(simd_dot(ba, ba), 1e-30), 0, 1)
            best = min(best, simd_length_squared(pa - ba * h))
            winding += crossing(edge, p)
        }
        let inside = evenOdd ? (winding & 1) != 0 : winding != 0
        return inside ? -best.squareRoot() : best.squareRoot()
    }

    /// Signed crossing of a ray from `p` towards +x (winding number contribution).
    @inline(__always) private func crossing(_ edge: (Vec2, Vec2), _ p: Vec2) -> Int {
        let (a, b) = edge
        let ba = b - a, pa = p - a
        if a.y <= p.y {
            if b.y > p.y && cross(ba, pa) > 0 { return 1 }
        } else if b.y <= p.y && cross(ba, pa) < 0 {
            return -1
        }
        return 0
    }

    private func cross(_ u: Vec2, _ v: Vec2) -> Double { u.x * v.y - u.y * v.x }
}

/// A set of primitives whose union is one solid; fillets blend between groups only,
/// so consecutive segments of the same line never bulge at their joints.
struct PrimitiveGroup {
    var primitives: [Primitive] = []
    var bounds: Box3 {
        var b = Box3()
        for p in primitives { b.include(p.bounds) }
        return b
    }
}
