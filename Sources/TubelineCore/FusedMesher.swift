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

    /// Signed distance from `p` to the filled area's outline in the plane (negative inside).
    func planarDistance(_ p: Vec2) -> Double {
        var winding = 0
        var best = Double.infinity
        for (a, b) in edges {
            let ba = b - a, pa = p - a
            let h = simd_clamp(simd_dot(pa, ba) / max(simd_dot(ba, ba), 1e-30), 0, 1)
            best = min(best, simd_length_squared(pa - ba * h))
            // Winding number via upward/downward crossings of a ray towards +x.
            if a.y <= p.y {
                if b.y > p.y && cross(ba, pa) > 0 { winding += 1 }
            } else if b.y <= p.y && cross(ba, pa) < 0 {
                winding -= 1
            }
        }
        let inside = evenOdd ? (winding & 1) != 0 : winding != 0
        return inside ? -best.squareRoot() : best.squareRoot()
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

/// Builds a single watertight mesh from the union of all groups by sampling a signed
/// distance field on a grid and extracting the zero surface with naive surface nets,
/// then snapping each vertex onto the exact analytic surface.
struct FusedMesher {
    var groups: [PrimitiveGroup]
    /// Grid spacing in output units.
    var voxel: Double
    /// Smooth-union radius between groups (0 = crisp intersection).
    var blend: Double

    func smin(_ a: Double, _ b: Double) -> Double {
        guard blend > 0 else { return min(a, b) }
        let h = max(blend - abs(a - b), 0) / blend
        return min(a, b) - h * h * blend * 0.25
    }

    func build() -> Mesh {
        var total = Box3()
        for g in groups { total.include(g.bounds) }
        guard !total.isEmpty else { return Mesh() }

        let h = voxel
        let pad = 2 * h + blend
        let origin = total.min - Vec3(repeating: pad)
        let span = total.size + Vec3(repeating: 2 * pad)
        let nx = Int(ceil(span.x / h)) + 1, ny = Int(ceil(span.y / h)) + 1, nz = Int(ceil(span.z / h)) + 1
        let far = Float(1e9)
        var field = [Float](repeating: far, count: nx * ny * nz)

        func gridRange(_ lo: Double, _ hi: Double, _ o: Double, _ n: Int) -> ClosedRange<Int> {
            let a = max(0, Int(floor((lo - o) / h)))
            let b = min(n - 1, Int(ceil((hi - o) / h)))
            return a...max(a, b)
        }

        // 1. Sample: per group take the min of its primitives near their bounds, then blend into the field.
        for group in groups {
            let gb = group.bounds.expanded(by: pad)
            let ri = gridRange(gb.min.x, gb.max.x, origin.x, nx)
            let rj = gridRange(gb.min.y, gb.max.y, origin.y, ny)
            let rk = gridRange(gb.min.z, gb.max.z, origin.z, nz)
            let lx = ri.count, ly = rj.count
            var local = [Float](repeating: far, count: lx * ly * rk.count)

            for prim in group.primitives {
                let pb = prim.bounds.expanded(by: pad)
                let pi = gridRange(pb.min.x, pb.max.x, origin.x, nx).clamped(to: ri)
                let pj = gridRange(pb.min.y, pb.max.y, origin.y, ny).clamped(to: rj)
                let pk = gridRange(pb.min.z, pb.max.z, origin.z, nz).clamped(to: rk)
                if case let .slab(s) = prim {
                    // The planar distance is shared by every z sample in a column.
                    for j in pj {
                        for i in pi {
                            let dxy = s.planarDistance(Vec2(origin.x + Double(i) * h, origin.y + Double(j) * h))
                            for k in pk {
                                let d = Float(s.distance(planar: dxy, z: origin.z + Double(k) * h))
                                let li = (i - ri.lowerBound) + lx * ((j - rj.lowerBound) + ly * (k - rk.lowerBound))
                                if d < local[li] { local[li] = d }
                            }
                        }
                    }
                    continue
                }
                for k in pk {
                    for j in pj {
                        for i in pi {
                            let p = origin + Vec3(Double(i), Double(j), Double(k)) * h
                            let d = Float(prim.distance(p))
                            let li = (i - ri.lowerBound) + lx * ((j - rj.lowerBound) + ly * (k - rk.lowerBound))
                            if d < local[li] { local[li] = d }
                        }
                    }
                }
            }
            for k in rk {
                for j in rj {
                    for i in ri {
                        let li = (i - ri.lowerBound) + lx * ((j - rj.lowerBound) + ly * (k - rk.lowerBound))
                        let gi = i + nx * (j + ny * k)
                        let a = field[gi], b = local[li]
                        field[gi] = (a >= far || b >= far) ? min(a, b) : Float(smin(Double(a), Double(b)))
                    }
                }
            }
        }

        // 2. Surface nets: one vertex per cell that straddles the surface.
        let lookup = SpatialLookup(groups: groups, cell: max(4 * h, total.size.z), pad: pad)
        let cx = nx - 1, cy = ny - 1, cz = nz - 1
        var cellVertex = [Int32](repeating: -1, count: cx * cy * cz)
        var mesh = Mesh()
        var creases = Set<Int>()
        let corners: [SIMD3<Int>] = [[0,0,0],[1,0,0],[0,1,0],[1,1,0],[0,0,1],[1,0,1],[0,1,1],[1,1,1]]
        let cubeEdges: [(Int, Int)] = [(0,1),(2,3),(4,5),(6,7),(0,2),(1,3),(4,6),(5,7),(0,4),(1,5),(2,6),(3,7)]

        for k in 0..<cz {
            for j in 0..<cy {
                for i in 0..<cx {
                    // A distance field can't change sign within a cell when a corner is farther than the cell diagonal.
                    if abs(field[i + nx * (j + ny * k)]) > Float(1.8 * h) { continue }
                    var v = [Float](repeating: 0, count: 8)
                    var mask = 0
                    for c in 0..<8 {
                        let o = corners[c]
                        v[c] = field[(i + o.x) + nx * ((j + o.y) + ny * (k + o.z))]
                        if v[c] < 0 { mask |= 1 << c }
                    }
                    guard mask != 0 && mask != 255 else { continue }
                    // Dual contouring: find where each crossing edge meets the exact surface and its
                    // normal there, then place the vertex where those tangent planes agree. This puts
                    // vertices on creases, so hard intersections and flat cap rims stay sharp.
                    let cellMin = origin + Vec3(Double(i), Double(j), Double(k)) * h
                    var mass = Vec3.zero
                    var ata = simd_double3x3(0)
                    var atb = Vec3.zero
                    var nsum = Vec3.zero
                    var normals: [Vec3] = []
                    var count = 0.0
                    for (a, b) in cubeEdges where (v[a] < 0) != (v[b] < 0) {
                        let pa = cellMin + SIMD3<Double>(corners[a]) * h
                        let pb = cellMin + SIMD3<Double>(corners[b]) * h
                        let q = lookup.edgeCrossing(pa, pb, Double(v[a]), Double(v[b]), smin: smin)
                        let n = lookup.gradient(q, eps: h * 0.02, smin: smin)
                        ata += simd_double3x3(rows: [n * n.x, n * n.y, n * n.z])
                        atb += n * simd_dot(n, q)
                        mass += q
                        nsum += n
                        normals.append(n)
                        count += 1
                    }
                    mass /= count
                    var p = mass + solveQEF(ata, atb - ata * mass)
                    let lo = cellMin - Vec3(repeating: 0.25 * h), hi = cellMin + Vec3(repeating: 1.25 * h)
                    if any(p .< lo) || any(p .> hi) { p = mass }
                    let nrm = simd_length(nsum) > 1e-9 ? simd_normalize(nsum) : lookup.gradient(p, eps: h * 0.05, smin: smin)
                    // A crease cell sees surface normals pointing in clearly different directions.
                    if normals.contains(where: { simd_dot($0, nrm) < 0.9 }) { creases.insert(mesh.positions.count) }
                    cellVertex[i + cx * (j + cy * k)] = Int32(mesh.positions.count)
                    mesh.positions.append(SIMD3<Float>(p))
                    mesh.normals.append(SIMD3<Float>(nrm))
                }
            }
        }

        // 3. Faces: every grid edge that crosses the surface becomes a quad joining the 4 cells around it.
        func cellIndex(_ i: Int, _ j: Int, _ k: Int) -> Int32 {
            guard i >= 0, j >= 0, k >= 0, i < cx, j < cy, k < cz else { return -1 }
            return cellVertex[i + cx * (j + cy * k)]
        }
        func emitQuad(_ q: [Int32]) {
            guard !q.contains(-1) else { return }
            var idx = q.map { Int($0) }
            let P = idx.map { mesh.positions[$0] }
            let faceN = simd_cross(P[1] - P[0], P[2] - P[0]) + simd_cross(P[2] - P[0], P[3] - P[0])
            let avgN = idx.reduce(SIMD3<Float>.zero) { $0 + mesh.normals[$1] }
            if simd_dot(faceN, avgN) < 0 { idx.reverse() }
            let Q = idx.map { mesh.positions[$0] }
            // Split along the shorter diagonal.
            if simd_distance_squared(Q[0], Q[2]) <= simd_distance_squared(Q[1], Q[3]) {
                mesh.indices += [idx[0], idx[1], idx[2], idx[0], idx[2], idx[3]].map(UInt32.init)
            } else {
                mesh.indices += [idx[0], idx[1], idx[3], idx[1], idx[2], idx[3]].map(UInt32.init)
            }
        }
        for k in 0..<nz {
            for j in 0..<ny {
                for i in 0..<nx {
                    let s0 = field[i + nx * (j + ny * k)] < 0
                    if i + 1 < nx, s0 != (field[(i + 1) + nx * (j + ny * k)] < 0) {
                        emitQuad([cellIndex(i, j - 1, k - 1), cellIndex(i, j, k - 1), cellIndex(i, j, k), cellIndex(i, j - 1, k)])
                    }
                    if j + 1 < ny, s0 != (field[i + nx * ((j + 1) + ny * k)] < 0) {
                        emitQuad([cellIndex(i - 1, j, k - 1), cellIndex(i, j, k - 1), cellIndex(i, j, k), cellIndex(i - 1, j, k)])
                    }
                    if k + 1 < nz, s0 != (field[i + nx * (j + ny * (k + 1))] < 0) {
                        emitQuad([cellIndex(i - 1, j - 1, k), cellIndex(i, j - 1, k), cellIndex(i, j, k), cellIndex(i - 1, j, k)])
                    }
                }
            }
        }
        splitCreaseNormals(&mesh, creases: creases, lookup: lookup)
        return mesh
    }

    /// Gives crease vertices a separate copy per triangle, shaded with the normal of the surface
    /// that triangle lies on, so hard edges render hard instead of smeared.
    private func splitCreaseNormals(_ mesh: inout Mesh, creases: Set<Int>, lookup: SpatialLookup) {
        guard !creases.isEmpty else { return }
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let tri = (0..<3).map { Int(mesh.indices[t + $0]) }
            guard tri.contains(where: creases.contains) else { continue }
            let c = tri.reduce(SIMD3<Float>.zero) { $0 + mesh.positions[$1] } / 3
            let n = SIMD3<Float>(lookup.gradient(Vec3(c), eps: voxel * 0.02, smin: smin))
            for k in 0..<3 where creases.contains(tri[k]) {
                mesh.indices[t + k] = UInt32(mesh.positions.count)
                mesh.positions.append(mesh.positions[tri[k]])
                mesh.normals.append(n)
            }
        }
    }
}

/// Least-squares solve of A·x = b for a symmetric 3×3 A, ignoring near-zero eigen-directions
/// (flat regions constrain only one axis; the mass point fills in the rest).
func solveQEF(_ a: simd_double3x3, _ b: Vec3) -> Vec3 {
    // Jacobi eigen-decomposition.
    var m = a
    var v = matrix_identity_double3x3
    for _ in 0..<12 {
        for (p, q) in [(0, 1), (0, 2), (1, 2)] {
            let apq = m[q][p]
            guard abs(apq) > 1e-14 else { continue }
            let theta = (m[q][q] - m[p][p]) / (2 * apq)
            let t = (theta >= 0 ? 1 : -1) / (abs(theta) + (theta * theta + 1).squareRoot())
            let c = 1 / (t * t + 1).squareRoot(), s = t * c
            var r = matrix_identity_double3x3
            r[p][p] = c; r[q][q] = c; r[q][p] = s; r[p][q] = -s
            m = r.transpose * m * r
            v = v * r
        }
    }
    let eig = Vec3(m[0][0], m[1][1], m[2][2])
    let maxE = max(eig.x, eig.y, eig.z)
    guard maxE > 1e-12 else { return .zero }
    var inv = simd_double3x3(0)
    for k in 0..<3 where eig[k] > 0.1 * maxE {
        inv[k][k] = 1 / eig[k]
    }
    return v * inv * v.transpose * b
}

/// Uniform 2D bucket grid (icons are flat) for evaluating the exact distance near a point.
struct SpatialLookup {
    let groups: [PrimitiveGroup]
    let cell: Double
    let origin: Vec2
    let nx: Int, ny: Int
    /// Per bucket: (group, primitive) pairs, sorted by group.
    var buckets: [[(Int, Int)]]

    init(groups: [PrimitiveGroup], cell: Double, pad: Double) {
        self.groups = groups
        self.cell = cell
        var total = Box3()
        for g in groups { total.include(g.bounds) }
        let o = Vec2(total.min.x, total.min.y) - Vec2(repeating: pad + cell)
        origin = o
        nx = Int(ceil((total.size.x + 2 * (pad + cell)) / cell)) + 1
        ny = Int(ceil((total.size.y + 2 * (pad + cell)) / cell)) + 1
        var b = [[(Int, Int)]](repeating: [], count: nx * ny)
        for (gi, g) in groups.enumerated() {
            for (pi, p) in g.primitives.enumerated() {
                let pb = p.bounds.expanded(by: pad)
                let i0 = max(0, Int(floor((pb.min.x - o.x) / cell))), i1 = min(nx - 1, Int(floor((pb.max.x - o.x) / cell)))
                let j0 = max(0, Int(floor((pb.min.y - o.y) / cell))), j1 = min(ny - 1, Int(floor((pb.max.y - o.y) / cell)))
                guard i0 <= i1, j0 <= j1 else { continue }
                for j in j0...j1 { for i in i0...i1 { b[i + nx * j].append((gi, pi)) } }
            }
        }
        buckets = b
    }

    func distance(_ p: Vec3, smin: (Double, Double) -> Double) -> Double {
        let i = Int(floor((p.x - origin.x) / cell)), j = Int(floor((p.y - origin.y) / cell))
        guard i >= 0, j >= 0, i < nx, j < ny else { return 1e9 }
        var result = Double.infinity
        var groupMin = Double.infinity
        var currentGroup = -1
        for (g, pi) in buckets[i + nx * j] {
            if g != currentGroup {
                if currentGroup >= 0 { result = result.isInfinite ? groupMin : smin(result, groupMin) }
                currentGroup = g
                groupMin = .infinity
            }
            groupMin = min(groupMin, groups[g].primitives[pi].distance(p))
        }
        if currentGroup >= 0 { result = result.isInfinite ? groupMin : smin(result, groupMin) }
        return result.isInfinite ? 1e9 : result
    }

    /// Point where the exact surface crosses the segment a→b (signs at the ends differ).
    func edgeCrossing(_ a: Vec3, _ b: Vec3, _ da: Double, _ db: Double, smin: (Double, Double) -> Double) -> Vec3 {
        var lo = a, hi = b, dlo = da, dhi = db
        var p = a + (b - a) * (da / (da - db))
        for _ in 0..<6 {
            let d = distance(p, smin: smin)
            if abs(d) < 1e-7 { break }
            if (d < 0) == (dlo < 0) { lo = p; dlo = d } else { hi = p; dhi = d }
            let t = dlo / (dlo - dhi)
            p = lo + (hi - lo) * (t.isFinite ? simd_clamp(t, 0.05, 0.95) : 0.5)
        }
        return p
    }

    func gradient(_ p: Vec3, eps: Double, smin: (Double, Double) -> Double) -> Vec3 {
        let dx = distance(p + Vec3(eps, 0, 0), smin: smin) - distance(p - Vec3(eps, 0, 0), smin: smin)
        let dy = distance(p + Vec3(0, eps, 0), smin: smin) - distance(p - Vec3(0, eps, 0), smin: smin)
        let dz = distance(p + Vec3(0, 0, eps), smin: smin) - distance(p - Vec3(0, 0, eps), smin: smin)
        let g = Vec3(dx, dy, dz)
        let len = simd_length(g)
        return len > 1e-12 ? g / len : Vec3(0, 0, 1)
    }
}
