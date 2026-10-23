import Foundation
import simd

/// Builds one closed mesh from the union of all groups: samples the signed distance on a grid,
/// extracts the surface with dual contouring (vertices land on creases, so seams stay sharp),
/// simplifies it against the exact surface, and shades it with exact normals.
struct FusedMesher {
    var groups: [PrimitiveGroup]
    /// Grid spacing in output units.
    var voxel: Double
    /// Smooth-union radius between groups (0 = crisp intersection).
    var blend: Double
    /// Maximum distance between the simplified mesh and the exact surface; 0 skips simplification.
    var tolerance: Double = 0
    /// Testing hook: treat the dual contour as invalid so the tetrahedral fallback runs.
    var forceTetrahedralFallback = false

    /// Cube corners, numbered x + 2y + 4z.
    static let corners: [SIMD3<Int>] = [[0,0,0],[1,0,0],[0,1,0],[1,1,0],[0,0,1],[1,0,1],[0,1,1],[1,1,1]]
    /// Cube edges as corner pairs: x edges 0–3, y edges 4–7, z edges 8–11.
    static let cubeEdges: [(Int, Int)] = [(0,1),(2,3),(4,5),(6,7),(0,2),(1,3),(4,6),(5,7),(0,4),(1,5),(2,6),(3,7)]
    /// Each cube face as four corners in cyclic order, with the edge between each corner and the next.
    static let faces: [(corners: [Int], edges: [Int])] = {
        func edge(_ a: Int, _ b: Int) -> Int {
            cubeEdges.firstIndex { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) }!
        }
        let cycles = [[0, 2, 6, 4], [1, 3, 7, 5], [0, 1, 5, 4], [2, 3, 7, 6], [0, 1, 3, 2], [4, 5, 7, 6]]
        return cycles.map { c in (c, (0..<4).map { edge(c[$0], c[($0 + 1) % 4]) }) }
    }()

    /// Groups a cell's crossing edges into separate sheets of surface. Two crossings on a face
    /// belong to the same sheet. A face with four crossings is ambiguous; it's resolved from that
    /// face's own corner values (the asymptotic decider), so both cells sharing the face agree and
    /// the result is manifold. Returns a 4-bit sheet number per cube edge and the sheet count.
    static func sheets(values v: [Float]) -> (edgeSheet: UInt64, count: Int) {
        var parent = Array(0..<12)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }
        func crosses(_ e: Int) -> Bool { (v[cubeEdges[e].0] < 0) != (v[cubeEdges[e].1] < 0) }

        for face in faces {
            let crossing = face.edges.filter(crosses)
            if crossing.count == 2 {
                union(crossing[0], crossing[1])
            } else if crossing.count == 4 {
                let c = face.corners.map { Double(v[$0]) }
                let denominator = c[0] + c[2] - c[1] - c[3]
                let saddle = abs(denominator) > 1e-12 ? (c[0] * c[2] - c[1] * c[3]) / denominator : c.reduce(0, +) / 4
                // Corners whose sign differs from the saddle are cut off on their own; pair the
                // two edges around each of them. Edge n runs from corner n to corner n + 1.
                let isolated = (c[0] < 0) != (saddle < 0) ? [0, 2] : [1, 3]
                for corner in isolated {
                    union(face.edges[(corner + 3) % 4], face.edges[corner])
                }
            }
        }
        var label = [Int](repeating: -1, count: 12)
        var count = 0
        var packed: UInt64 = 0
        for e in 0..<12 where crosses(e) {
            let root = find(e)
            if label[root] < 0 { label[root] = count; count += 1 }
            packed |= UInt64(label[root]) << (4 * UInt64(e))
        }
        return (packed, count)
    }

    func build() -> Mesh {
        var profiler = Profiler()
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
        profiler.lap("sample \(nx)×\(ny)×\(nz) grid")

        // 2. Dual contouring with one vertex per separate sheet of surface in each cell.
        // A single vertex per cell pinches two sheets together where strokes nearly touch,
        // which makes the mesh non-manifold (dual marching cubes; Nielson 2004).
        let cx = nx - 1, cy = ny - 1, cz = nz - 1
        var mesh = Mesh()
        var creases = Set<Int>()
        let corners = Self.corners, cubeEdges = Self.cubeEdges

        // Cells are independent, so rows are contoured in parallel and merged in order afterwards.
        struct Sheet { var p: Vec3; var mass: Vec3; var n: Vec3; var crease: Bool }
        struct ActiveCell { var cell: Int; var edgeSheet: UInt64; var sheets: [Sheet] }
        var rows = [[ActiveCell]](repeating: [], count: cy)
        field.withUnsafeBufferPointer { field in
            rows.withUnsafeMutableBufferPointer { rows in
                DispatchQueue.concurrentPerform(iterations: cy) { j in
                    var out: [ActiveCell] = []
                    var v = [Float](repeating: 0, count: 8)
                    var normals: [Vec3] = []
                    normals.reserveCapacity(12)
                    for k in 0..<cz {
                        for i in 0..<cx {
                            // Check every corner's sign. (Skipping cells whose first corner is far from
                            // the surface is only safe for a true distance field; blended fields can
                            // change faster than that and would leave pinholes.)
                            var mask = 0
                            for c in 0..<8 {
                                let o = corners[c]
                                v[c] = field[(i + o.x) + nx * ((j + o.y) + ny * (k + o.z))]
                                if v[c] < 0 { mask |= 1 << c }
                            }
                            guard mask != 0 && mask != 255 else { continue }
                            let (edgeSheet, sheetCount) = Self.sheets(values: v)
                            // Dual contouring: for each sheet, find where its crossing edges meet the exact
                            // surface and the normals there, then place the vertex where those tangent planes
                            // agree. This puts vertices on creases, so hard intersections stay sharp.
                            let cellMin = origin + Vec3(Double(i), Double(j), Double(k)) * h
                            var sheets: [Sheet] = []
                            for sheet in 0..<sheetCount {
                                var mass = Vec3.zero
                                var ata = simd_double3x3(0)
                                var atb = Vec3.zero
                                var nsum = Vec3.zero
                                normals.removeAll(keepingCapacity: true)
                                for (e, (a, b)) in cubeEdges.enumerated() where (v[a] < 0) != (v[b] < 0) {
                                    guard Int((edgeSheet >> (4 * UInt64(e))) & 0xF) == sheet else { continue }
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
                                // Two sheets in one cell must not share a vertex position, or the welded
                                // mesh pinches again. Their mass points are always distinct.
                                if sheets.contains(where: { simd_distance($0.p, p) < 0.05 * h }) { p = mass }
                                let nrm = simd_length(nsum) > 1e-9 ? simd_normalize(nsum) : lookup.gradient(p, eps: h * 0.05)
                                // A crease cell sees surface normals pointing in clearly different directions.
                                let crease = normals.contains { simd_dot($0, nrm) < 0.9 }
                                sheets.append(Sheet(p: p, mass: mass, n: nrm, crease: crease))
                            }
                            out.append(ActiveCell(cell: i + cx * (j + cy * k), edgeSheet: edgeSheet, sheets: sheets))
                        }
                    }
                    rows[j] = out
                }
            }
        }
        // Each active cell records its first vertex; edgeSheet picks the sheet for a cube edge.
        var cellSlot = [Int32](repeating: -1, count: cx * cy * cz)
        var slotFirst: [Int32] = [], slotEdgeSheet: [UInt64] = []
        // Where planes meet at a sharp corner, neighboring cells can solve to the very same point.
        // Two vertices in one place weld together and pinch the mesh, so a later duplicate moves
        // to its own sheet's mass point, which lies within its cell.
        var used = Set<SIMD3<Float>>()
        for row in rows {
            for cell in row {
                cellSlot[cell.cell] = Int32(slotFirst.count)
                slotFirst.append(Int32(mesh.positions.count))
                slotEdgeSheet.append(cell.edgeSheet)
                for sheet in cell.sheets {
                    if sheet.crease { creases.insert(mesh.positions.count) }
                    var position = SIMD3<Float>(sheet.p)
                    if !used.insert(position).inserted {
                        let k = cell.cell / (cx * cy), j = (cell.cell / cx) % cy, i = cell.cell % cx
                        let cellMin = origin + Vec3(Double(i), Double(j), Double(k)) * h
                        position = SIMD3<Float>(simd_clamp(sheet.mass, cellMin + 0.05 * h, cellMin + 0.95 * h))
                        used.insert(position)
                    }
                    mesh.positions.append(position)
                    mesh.normals.append(SIMD3<Float>(sheet.n))
                }
            }
        }
        rows = []

        profiler.lap("dual contouring")

        // 3. Faces: every grid edge that crosses the surface becomes a quad joining, in each of the
        // four cells around it, the vertex of the sheet that edge belongs to.
        func vertex(_ i: Int, _ j: Int, _ k: Int, edge: Int) -> Int32 {
            guard i >= 0, j >= 0, k >= 0, i < cx, j < cy, k < cz else { return -1 }
            let slot = cellSlot[i + cx * (j + cy * k)]
            guard slot >= 0 else { return -1 }
            return slotFirst[Int(slot)] + Int32((slotEdgeSheet[Int(slot)] >> (4 * UInt64(edge))) & 0xF)
        }
        /// `q` lists the four vertices counterclockwise around the grid edge's positive axis
        /// direction. The quad faces from the edge's inside end toward its outside end, which is
        /// exact and consistent between neighbors (unlike guessing from vertex normals).
        func emitQuad(_ q: [Int32], facesPositive: Bool) {
            guard !q.contains(-1) else { return }
            var idx = q.map { Int($0) }
            if !facesPositive { idx.reverse() }
            let Q = idx.map { mesh.positions[$0] }
            // Split along the shorter diagonal.
            if simd_distance_squared(Q[0], Q[2]) <= simd_distance_squared(Q[1], Q[3]) {
                mesh.indices += [idx[0], idx[1], idx[2], idx[0], idx[2], idx[3]].map(UInt32.init)
            } else {
                mesh.indices += [idx[0], idx[1], idx[3], idx[1], idx[2], idx[3]].map(UInt32.init)
            }
        }
        // Cube edge numbers follow `cubeEdges`: x edges 0–3, y edges 4–7, z edges 8–11, each ordered
        // by the cell's offset along the other two axes.
        for k in 0..<nz {
            for j in 0..<ny {
                for i in 0..<nx {
                    // s0: the edge's lower end is inside, so the surface faces the positive axis.
                    let s0 = field[i + nx * (j + ny * k)] < 0
                    if i + 1 < nx, s0 != (field[(i + 1) + nx * (j + ny * k)] < 0) {
                        // Around +x (y right, z up).
                        emitQuad([vertex(i, j - 1, k - 1, edge: 3), vertex(i, j, k - 1, edge: 2),
                                  vertex(i, j, k, edge: 0), vertex(i, j - 1, k, edge: 1)], facesPositive: s0)
                    }
                    if j + 1 < ny, s0 != (field[i + nx * ((j + 1) + ny * k)] < 0) {
                        // Around +y (z right, x up).
                        emitQuad([vertex(i - 1, j, k - 1, edge: 7), vertex(i - 1, j, k, edge: 5),
                                  vertex(i, j, k, edge: 4), vertex(i, j, k - 1, edge: 6)], facesPositive: s0)
                    }
                    if k + 1 < nz, s0 != (field[i + nx * (j + ny * (k + 1))] < 0) {
                        // Around +z (x right, y up).
                        emitQuad([vertex(i - 1, j - 1, k, edge: 11), vertex(i, j - 1, k, edge: 10),
                                  vertex(i, j, k, edge: 8), vertex(i - 1, j, k, edge: 9)], facesPositive: s0)
                    }
                }
            }
        }
        profiler.lap("faces (\(mesh.triangleCount) triangles)")

        // 4. Simplify and shade, then order for the GPU.
        let denseContour = mesh
        if tolerance > 0 {
            mesh = simplify(mesh, creases: creases, lookup: lookup)
            profiler.lap("simplify and shade (\(mesh.triangleCount) triangles)")
        } else {
            splitCreaseNormals(&mesh, creases: creases, lookup: lookup)
        }
        let simplifiedValid = !forceTetrahedralFallback && mesh.validation(checkAllFailures: false).isValid
        profiler.lap("validate")
        if Profiler.enabled && !simplifiedValid {
            print("  simplified: \(mesh.validation().summary)\n  dense: \(denseContour.validation().summary)")
        }
        if !simplifiedValid {
            let denseValid = !forceTetrahedralFallback && denseContour.validation(checkAllFailures: false).isValid
            profiler.lap("validate dense contour")
            if denseValid {
                // A valid contour is preferable to changing the surface extractor when
                // only simplification caused the failure.
                mesh = denseContour
                splitCreaseNormals(&mesh, creases: creases, lookup: lookup)
            } else {
                // Ambiguous cells can contain separate sheets. Tetrahedra resolve them
                // consistently across the same sampled union.
                mesh = tetrahedralSurface(field: field, nx: nx, ny: ny, nz: nz, origin: origin, lookup: lookup)
                profiler.lap("tetrahedral surface (\(mesh.triangleCount) triangles)")
                if tolerance > 0 {
                    let dense = mesh
                    let simplified = simplify(dense, creases: [], lookup: lookup)
                    profiler.lap("simplify tetrahedral surface (\(simplified.triangleCount) triangles)")
                    let valid = simplified.validation(checkAllFailures: false).isValid
                    profiler.lap("validate")
                    if valid { mesh = simplified } else {
                        mesh = dense
                        splitCreaseNormals(&mesh, creases: nil, lookup: lookup)
                    }
                } else {
                    splitCreaseNormals(&mesh, creases: nil, lookup: lookup)
                }
            }
            mesh.warnings.append("Complex intersections required a denser mesh to keep the surface closed. Reduce Detail if you need fewer triangles.")
            profiler.lap("manifold fallback (\(mesh.triangleCount) triangles)")
        }
        mesh.optimizeForGPU()
        return mesh
    }

    /// Freudenthal's six tetrahedra share the same face diagonals in neighboring cells.
    /// Each crossing belongs to a global grid edge, including the tetrahedral diagonals.
    private func tetrahedralSurface(field: [Float], nx: Int, ny: Int, nz: Int,
                                    origin: Vec3, lookup: SpatialLookup) -> Mesh {
        let corners: [SIMD3<Int>] = [[0,0,0],[1,0,0],[0,1,0],[1,1,0],[0,0,1],[1,0,1],[0,1,1],[1,1,1]]
        let tetrahedra = [[0,1,3,7], [0,3,2,7], [0,2,6,7], [0,6,4,7], [0,4,5,7], [0,5,1,7]]
        // Keep crossings away from exactly zero-valued lattice vertices. The displacement
        // is much smaller than one facet's sag, and avoids coincident Float vertices.
        let iso = voxel * voxel * 0.01
        var mesh = Mesh()
        var vertexForEdge: [SIMD2<Int>: UInt32] = [:]
        func vertex(_ a: Int, _ b: Int, _ positions: [Vec3], _ grid: [Int], _ values: [Double]) -> UInt32 {
            let key = SIMD2(min(grid[a], grid[b]), max(grid[a], grid[b]))
            if let found = vertexForEdge[key] { return found }
            // Preserve the piecewise-linear field's topology. Snapping these crossings
            // independently to the exact SDF can collapse distinct tetrahedral edges at
            // a crease, reintroducing the degeneracies this fallback must avoid.
            // Keep a small separation from shared lattice corners. Otherwise an almost
            // zero sample creates sliver triangles that collapse after Float export.
            let t = simd_clamp(values[a] / (values[a] - values[b]), 0.001, 0.999)
            let p = positions[a] + (positions[b] - positions[a]) * t
            let id = UInt32(mesh.positions.count)
            vertexForEdge[key] = id
            mesh.positions.append(SIMD3<Float>(p))
            mesh.normals.append(SIMD3<Float>(lookup.gradient(p, eps: voxel * 0.02)))
            return id
        }
        func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32, outward: Vec3) {
            let p = Vec3(mesh.positions[Int(a)]), q = Vec3(mesh.positions[Int(b)]), r = Vec3(mesh.positions[Int(c)])
            if simd_dot(simd_cross(q - p, r - p), outward) < 0 {
                mesh.indices += [a, c, b]
            } else { mesh.indices += [a, b, c] }
        }
        for k in 0..<(nz - 1) {
            for j in 0..<(ny - 1) {
                for i in 0..<(nx - 1) {
                    // Every corner's sign, checked without allocating; see the note in contouring.
                    var below = 0
                    for c in corners where Double(field[(i + c.x) + nx * ((j + c.y) + ny * (k + c.z))]) - iso < 0 { below += 1 }
                    if below == 0 || below == 8 { continue }
                    let grid = corners.map { (i + $0.x) + nx * ((j + $0.y) + ny * (k + $0.z)) }
                    let values = grid.map { Double(field[$0]) - iso }
                    if values.allSatisfy({ $0 < 0 }) || values.allSatisfy({ $0 >= 0 }) { continue }
                    let positions = corners.map { origin + Vec3(Double(i + $0.x), Double(j + $0.y), Double(k + $0.z)) * voxel }
                    for tet in tetrahedra {
                        let inside = tet.filter { values[$0] < 0 }, outside = tet.filter { values[$0] >= 0 }
                        if inside.isEmpty || outside.isEmpty { continue }
                        let inward = inside.reduce(Vec3.zero) { $0 + positions[$1] } / Double(inside.count)
                        let outward = outside.reduce(Vec3.zero) { $0 + positions[$1] } / Double(outside.count) - inward
                        if inside.count == 1 {
                            let v = outside.map { vertex(inside[0], $0, positions, grid, values) }
                            triangle(v[0], v[1], v[2], outward: outward)
                        } else if outside.count == 1 {
                            let v = inside.map { vertex(outside[0], $0, positions, grid, values) }
                            triangle(v[0], v[1], v[2], outward: outward)
                        } else {
                            let a = vertex(inside[0], outside[0], positions, grid, values)
                            let b = vertex(inside[0], outside[1], positions, grid, values)
                            let c = vertex(inside[1], outside[1], positions, grid, values)
                            let d = vertex(inside[1], outside[0], positions, grid, values)
                            let pa = Vec3(mesh.positions[Int(a)]), pb = Vec3(mesh.positions[Int(b)]), pc = Vec3(mesh.positions[Int(c)])
                            if simd_dot(simd_cross(pb - pa, pc - pa), outward) < 0 {
                                mesh.indices += [a, c, b, a, d, c]
                            } else {
                                mesh.indices += [a, b, c, a, c, d]
                            }
                        }
                    }
                }
            }
        }
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
        var profiler = Profiler()

        // Pass 1: simplify tiles in parallel, with vertices on tile borders locked so neighbors
        // stay stitched. Pass 2 then simplifies the whole mesh, mostly just the seams.
        let (tp, tt, tc) = simplifyTiles(positions: positions, triangles: tris, crease: crease, distance: distance)
        profiler.lap("  simplify tiles (\(tt.count) triangles)")
        var d = Decimator(positions: tp, triangles: tt, crease: tc, maxError: tolerance, distance: distance)
        d.run()
        profiler.lap("  simplify seams")
        let (pos, out, _, _) = d.output()

        var mesh = Mesh()
        mesh.positions = pos.map { SIMD3<Float>($0) }
        // A quarter-cell step averages rapid curvature changes (where fillets fade out) the way the
        // dense contour does, instead of turning them into bright specks.
        mesh.normals = pos.map { SIMD3<Float>(lookup.gradient($0, eps: voxel * 0.25)) }
        mesh.indices = out.flatMap { [UInt32($0.x), UInt32($0.y), UInt32($0.z)] }
        // Blended surfaces are meant to be soft, and their tight curvature where fillets fade out
        // would be misread as creases and split into hard shards. Only crisp unions split.
        if blend == 0 { splitCreaseNormals(&mesh, creases: nil, lookup: lookup) }
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
                // Step a short way into the triangle so the gradient picks this side of a crease.
                // Keep the step small: a real crease jumps right away, while a tight fillet only
                // curves gradually and must not be split into hard facets.
                let toward = Vec3(c) - p
                let len = simd_length(toward)
                let probe = len > 1e-12 ? p + toward / len * min(len * 0.5, voxel * 0.1) : p
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
