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

/// Builds a single watertight mesh from the union of all groups by sampling a signed
/// distance field on a grid and extracting the zero surface with naive surface nets,
/// then snapping each vertex onto the exact analytic surface.
struct FusedMesher {
    var groups: [PrimitiveGroup]
    /// Grid spacing in output units.
    var voxel: Double
    /// Smooth-union radius between groups (0 = crisp intersection).
    var blend: Double
    /// Maximum distance between the simplified mesh and the exact surface; 0 skips simplification.
    var tolerance: Double = 0

    func smin(_ a: Double, _ b: Double) -> Double {
        guard blend > 0 else { return min(a, b) }
        let h = max(blend - abs(a - b), 0) / blend
        return min(a, b) - h * h * blend * 0.25
    }

    func build() -> Mesh {
        var clock = Date()
        func lap(_ name: String) {
            if ProcessInfo.processInfo.environment["TL_PROFILE"] != nil {
                print(String(format: "  %@: %.3fs", name, Date().timeIntervalSince(clock)))
            }
            clock = Date()
        }
        var total = Box3()
        for g in groups { total.include(g.bounds) }
        guard !total.isEmpty else { return Mesh() }

        let h = voxel
        let pad = 2 * h + blend
        for g in groups {
            for case let .slab(s) in g.primitives {
                let rounding: Double = switch s.profile {
                case .rounded(let r): r
                case .extruded(let hd, _): hd
                }
                s.prepare(band: rounding + 2 * pad + tolerance)
            }
        }
        let origin = total.min - Vec3(repeating: pad)
        let span = total.size + Vec3(repeating: 2 * pad)
        let nx = Int(ceil(span.x / h)) + 1, ny = Int(ceil(span.y / h)) + 1, nz = Int(ceil(span.z / h)) + 1
        let far = Float(1e9)
        var field = [Float](repeating: far, count: nx * ny * nz)


        // 1. Sample the exact distance on the grid, rows in parallel. The same lookup later snaps
        // vertices and checks simplification, so every stage sees one consistent surface.
        let lookup = SpatialLookup(groups: groups, cell: 2 * h, pad: pad + tolerance, blend: blend)
        field.withUnsafeMutableBufferPointer { field in
            DispatchQueue.concurrentPerform(iterations: ny * nz) { row in
                let j = row % ny, k = row / ny
                let y = origin.y + Double(j) * h, z = origin.z + Double(k) * h
                let base = nx * (j + ny * k)
                for i in 0..<nx {
                    let d = lookup.distance(Vec3(origin.x + Double(i) * h, y, z))
                    field[base + i] = d >= 1e9 ? far : Float(d)
                }
            }
        }
        lap("sample \(nx)×\(ny)×\(nz)")
        // 2. Surface nets: one vertex per cell that straddles the surface.
        lap("lookup")
        let cx = nx - 1, cy = ny - 1, cz = nz - 1
        var cellVertex = [Int32](repeating: -1, count: cx * cy * cz)
        var mesh = Mesh()
        var creases = Set<Int>()
        let corners: [SIMD3<Int>] = [[0,0,0],[1,0,0],[0,1,0],[1,1,0],[0,0,1],[1,0,1],[0,1,1],[1,1,1]]
        let cubeEdges: [(Int, Int)] = [(0,1),(2,3),(4,5),(6,7),(0,2),(1,3),(4,6),(5,7),(0,4),(1,5),(2,6),(3,7)]

        // Cells are independent, so rows are contoured in parallel and merged in order afterwards.
        struct CellVertex { var cell: Int; var p: Vec3; var n: Vec3; var crease: Bool }
        var rows = [[CellVertex]](repeating: [], count: cy)
        field.withUnsafeBufferPointer { field in
            rows.withUnsafeMutableBufferPointer { rows in
                DispatchQueue.concurrentPerform(iterations: cy) { j in
                    var out: [CellVertex] = []
                    var v = [Float](repeating: 0, count: 8)
                    var normals: [Vec3] = []
                    normals.reserveCapacity(12)
                    for k in 0..<cz {
                        for i in 0..<cx {
                            // A distance field can't change sign within a cell when a corner is farther than the cell diagonal.
                            if abs(field[i + nx * (j + ny * k)]) > Float(1.8 * h) { continue }
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
                            normals.removeAll(keepingCapacity: true)
                            for (a, b) in cubeEdges where (v[a] < 0) != (v[b] < 0) {
                                let pa = cellMin + SIMD3<Double>(corners[a]) * h
                                let pb = cellMin + SIMD3<Double>(corners[b]) * h
                                let q = lookup.edgeCrossing(pa, pb, Double(v[a]), Double(v[b]))
                                let n = lookup.gradient(q, eps: h * 0.02)
                                ata += simd_double3x3(rows: [n * n.x, n * n.y, n * n.z])
                                atb += n * simd_dot(n, q)
                                mass += q
                                nsum += n
                                normals.append(n)
                            }
                            mass /= Double(normals.count)
                            var p = mass + solveQEF(ata, atb - ata * mass)
                            let lo = cellMin - Vec3(repeating: 0.25 * h), hi = cellMin + Vec3(repeating: 1.25 * h)
                            if any(p .< lo) || any(p .> hi) { p = mass }
                            let nrm = simd_length(nsum) > 1e-9 ? simd_normalize(nsum) : lookup.gradient(p, eps: h * 0.05)
                            // A crease cell sees surface normals pointing in clearly different directions.
                            let crease = normals.contains { simd_dot($0, nrm) < 0.9 }
                            out.append(CellVertex(cell: i + cx * (j + cy * k), p: p, n: nrm, crease: crease))
                        }
                    }
                    rows[j] = out
                }
            }
        }
        for row in rows {
            for cv in row {
                if cv.crease { creases.insert(mesh.positions.count) }
                cellVertex[cv.cell] = Int32(mesh.positions.count)
                mesh.positions.append(SIMD3<Float>(cv.p))
                mesh.normals.append(SIMD3<Float>(cv.n))
            }
        }

        lap("dual contour")
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
        lap("faces \(mesh.triangleCount) tris")
        if tolerance > 0 {
            mesh = simplify(mesh, creases: creases, lookup: lookup)
            lap("simplify")
        } else {
            splitCreaseNormals(&mesh, creases: creases, lookup: lookup)
        }
        mesh.optimizeForGPU()
        return mesh
    }

    /// Collapses the dense grid mesh down to what the shape needs, then rebuilds normals from
    /// the exact surface so a lighter tube still shades perfectly round.
    private func simplify(_ dense: Mesh, creases: Set<Int>, lookup: SpatialLookup) -> Mesh {
        var tris: [SIMD3<Int32>] = []
        tris.reserveCapacity(dense.triangleCount)
        for t in stride(from: 0, to: dense.indices.count, by: 3) {
            let tri = SIMD3<Int32>(Int32(dense.indices[t]), Int32(dense.indices[t + 1]), Int32(dense.indices[t + 2]))
            if tri.x != tri.y && tri.y != tri.z && tri.x != tri.z { tris.append(tri) }
        }
        let crease = (0..<dense.positions.count).map { creases.contains($0) }
        let positions = dense.positions.map { Vec3($0) }
        let distance: (Vec3) -> Double = { lookup.distance($0) }
        let profile = ProcessInfo.processInfo.environment["TL_PROFILE"] != nil
        let t0 = Date()

        // Pass 1: simplify tiles in parallel, with vertices on tile borders locked so neighbors
        // stay stitched. Pass 2 then simplifies the whole mesh, mostly just the seams.
        let (tp, tt, tc) = simplifyTiles(positions: positions, triangles: tris, crease: crease, distance: distance)
        if profile { print(String(format: "  tiles: %.3fs → %d tris", Date().timeIntervalSince(t0), tt.count)) }
        var d = Decimator(positions: tp, triangles: tt, crease: tc, maxError: tolerance, distance: distance)
        d.run()
        if profile { print(String(format: "  decimate: %.3fs", Date().timeIntervalSince(t0))) }
        let (pos, out, _, _) = d.output()

        var mesh = Mesh()
        mesh.positions = pos.map { SIMD3<Float>($0) }
        mesh.normals = pos.map { SIMD3<Float>(lookup.gradient($0, eps: voxel * 0.02)) }
        mesh.indices = out.flatMap { [UInt32($0.x), UInt32($0.y), UInt32($0.z)] }
        splitCreaseNormals(&mesh, creases: nil, lookup: lookup)
        return mesh
    }

    private func simplifyTiles(positions: [Vec3], triangles: [SIMD3<Int32>], crease: [Bool],
                               distance: @escaping (Vec3) -> Double) -> ([Vec3], [SIMD3<Int32>], [Bool]) {
        let grid = triangles.count > 20_000 ? 6 : 1
        guard grid > 1 else { return (positions, triangles, crease) }
        var lo = Vec2(repeating: .infinity), hi = Vec2(repeating: -.infinity)
        for p in positions { lo = simd_min(lo, Vec2(p.x, p.y)); hi = simd_max(hi, Vec2(p.x, p.y)) }
        let span = simd_max(hi - lo, Vec2(repeating: 1e-9))

        // Assign each triangle to a tile by centroid; a vertex used by two tiles is a border vertex.
        var tileOf = [Int](repeating: 0, count: triangles.count)
        var vertexTile = [Int](repeating: -1, count: positions.count)
        var border = [Bool](repeating: false, count: positions.count)
        for (t, tri) in triangles.enumerated() {
            let c = (positions[Int(tri.x)] + positions[Int(tri.y)] + positions[Int(tri.z)]) / 3
            let tx = min(grid - 1, Int((c.x - lo.x) / span.x * Double(grid)))
            let ty = min(grid - 1, Int((c.y - lo.y) / span.y * Double(grid)))
            let tile = tx + grid * ty
            tileOf[t] = tile
            for k in 0..<3 {
                let v = Int(tri[k])
                if vertexTile[v] == -1 { vertexTile[v] = tile } else if vertexTile[v] != tile { border[v] = true }
            }
        }

        struct TileResult { var positions: [Vec3] = []; var triangles: [SIMD3<Int32>] = []; var crease: [Bool] = []; var global: [Int] = [] }
        var results = [TileResult](repeating: TileResult(), count: grid * grid)
        var tileTris = [[Int]](repeating: [], count: grid * grid)
        for (t, tile) in tileOf.enumerated() { tileTris[tile].append(t) }

        results.withUnsafeMutableBufferPointer { results in
            DispatchQueue.concurrentPerform(iterations: grid * grid) { tile in
                var local: [Int: Int32] = [:]
                var globalOf: [Int] = []
                var lt: [SIMD3<Int32>] = []
                for t in tileTris[tile] {
                    var out = SIMD3<Int32>()
                    for k in 0..<3 {
                        let v = Int(triangles[t][k])
                        if let l = local[v] { out[k] = l } else {
                            let l = Int32(globalOf.count)
                            local[v] = l
                            globalOf.append(v)
                            out[k] = l
                        }
                    }
                    lt.append(out)
                }
                guard !lt.isEmpty else { return }
                var d = Decimator(positions: globalOf.map { positions[$0] }, triangles: lt,
                                  crease: globalOf.map { crease[$0] }, locked: globalOf.map { border[$0] },
                                  maxError: tolerance, distance: distance)
                d.run()
                let (p, tr, cr, src) = d.output()
                results[tile] = TileResult(positions: p, triangles: tr, crease: cr, global: src.map { globalOf[$0] })
            }
        }

        // Merge: border vertices are shared by global index; interior vertices are new.
        var pos: [Vec3] = [], cr: [Bool] = [], tris: [SIMD3<Int32>] = []
        var borderIndex: [Int: Int32] = [:]
        for r in results {
            var remap = [Int32](repeating: 0, count: r.positions.count)
            for i in r.positions.indices {
                let g = r.global[i]
                if border[g], let existing = borderIndex[g] {
                    remap[i] = existing
                    continue
                }
                remap[i] = Int32(pos.count)
                if border[g] { borderIndex[g] = Int32(pos.count) }
                pos.append(r.positions[i]); cr.append(r.crease[i])
            }
            for t in r.triangles { tris.append(SIMD3(remap[Int(t.x)], remap[Int(t.y)], remap[Int(t.z)])) }
        }
        return (pos, tris, cr)
    }

    /// Gives vertices on a crease a separate copy per side, shaded with the normal of the surface
    /// that side lies on, so hard edges render hard instead of smeared. When `creases` is nil every
    /// vertex is tested by probing the exact surface a short step into each adjacent triangle.
    private func splitCreaseNormals(_ mesh: inout Mesh, creases: Set<Int>?, lookup: SpatialLookup) {
        let eps = voxel * 0.02
        var copies: [Int: [(normal: SIMD3<Float>, index: UInt32)]] = [:]
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let tri = (0..<3).map { Int(mesh.indices[t + $0]) }
            if let creases, !tri.contains(where: creases.contains) { continue }
            let c = tri.reduce(SIMD3<Float>.zero) { $0 + mesh.positions[$1] } / 3
            for k in 0..<3 {
                let v = tri[k]
                if let creases, !creases.contains(v) { continue }
                let p = Vec3(mesh.positions[v])
                // Step a little way into the triangle so the gradient picks this side of a crease.
                let toward = Vec3(c) - p
                let len = simd_length(toward)
                let probe = len > 1e-12 ? p + toward / len * min(len * 0.5, voxel * 0.5) : p
                let n = SIMD3<Float>(lookup.gradient(probe, eps: eps))
                // Smooth here: keep the shared vertex and its exact normal.
                if simd_dot(n, mesh.normals[v]) > 0.97 { continue }
                if let existing = copies[v]?.first(where: { simd_dot($0.normal, n) > 0.97 }) {
                    mesh.indices[t + k] = existing.index
                    continue
                }
                let idx = UInt32(mesh.positions.count)
                mesh.positions.append(mesh.positions[v])
                mesh.normals.append(n)
                copies[v, default: []].append((n, idx))
                mesh.indices[t + k] = idx
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
