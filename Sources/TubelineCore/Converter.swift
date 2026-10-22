import Foundation
import simd

public struct ConversionOptions: Codable, Equatable, Sendable {
    public enum Sizing: String, Codable, CaseIterable, Sendable {
        /// Artwork points map to a physical size (`millimetersPerPoint`).
        case points
        /// The frame's longest side becomes `size` centimeters.
        case fixed
    }

    public enum Framing: String, Codable, CaseIterable, Sendable {
        /// Scale and center using the SVG's viewBox, so every icon in a set lines up.
        case canvas
        /// Scale and center using the drawn geometry only.
        case content
    }

    public enum Surface: String, Codable, CaseIterable, Sendable {
        /// Flat, self-lit color: reads as a solid silhouette whatever the scene lighting.
        case solid
        /// Plain matte material that responds to the scene's lights.
        case shaded
    }

    public enum FillStyle: String, Codable, CaseIterable, Sendable {
        /// Slab with a fully rounded rim, as thick as the icon's typical stroke.
        case rounded
        /// Straight extrusion with `extrudeDepth`, for solid artwork like outlined text.
        case extruded
    }

    /// Line ends: as written in the SVG, or always round or always flat.
    public enum Caps: String, Codable, CaseIterable, Sendable {
        case svg, round, flat
    }

    /// Tube diameter as a multiple of the SVG stroke width.
    public var thickness = 1.0
    /// Number of flat sides around each tube. More is smoother and heavier.
    public var facets = 32.0
    /// Rounded blend where separate strokes meet, as a fraction of the tube radius (0 = crisp).
    public var fillet = 0.0
    public var caps = Caps.svg
    /// Turn shapes with a declared fill into solids.
    public var includeFills = true
    /// How fills that have no outline of their own are shaped.
    public var fillStyle = FillStyle.extruded
    /// Extrusion depth in artwork points.
    public var extrudeDepth = 4.0
    /// Rounding of extruded edges, as a fraction of half the depth.
    public var extrudeRounding = 0.1
    public var framing = Framing.canvas
    public var sizing = Sizing.points
    /// Physical size of one point. The default is the print standard, 1/72 inch.
    public var millimetersPerPoint = 25.4 / 72
    /// Length of the longest side of the frame in centimeters, for `.fixed` sizing.
    public var size = 10.0
    /// Simplify the mesh: long straight runs and flat faces collapse to a few large triangles,
    /// keeping the surface within one facet's sag of the exact shape.
    public var optimize = true
    /// Surface color as #RRGGBB.
    public var color = "#FFFFFF"
    public var surface = Surface.solid

    public init() {}
}

public struct ConversionReport: Sendable {
    public var strokes: Int
    public var fills: Int
    public var vertices: Int
    public var triangles: Int
    /// Model width, height, and depth in centimeters.
    public var dimensions: Vec3
    public var skipped: [String]
    public var seconds: Double
}

public enum ConversionError: LocalizedError {
    case emptyMesh
    public var errorDescription: String? { "No geometry was produced." }
}

public enum Converter {
    /// Converts an SVG file to a USDZ file. Returns statistics about the result.
    @discardableResult
    public static func convert(svg: URL, to output: URL, options: ConversionOptions) throws -> ConversionReport {
        let start = Date()
        let doc = try SVGParser.parse(url: svg, tolerance: 0.005)
        let mesh = try buildMesh(doc, options: options)
        let b = mesh.bounds
        var profiler = Profiler()
        defer { profiler.lap("write USDZ") }
        try USDZWriter.write(mesh: mesh, name: output.deletingPathExtension().lastPathComponent,
                             color: parseHex(options.color), surface: options.surface, to: output)
        return ConversionReport(strokes: doc.strokes.count, fills: options.includeFills ? doc.fills.count : 0,
                                vertices: mesh.positions.count, triangles: mesh.triangleCount, dimensions: b.size,
                                skipped: Array(Set(doc.skipped)).sorted(), seconds: Date().timeIntervalSince(start))
    }

    public static func buildMesh(_ doc: SVGDocument, options: ConversionOptions) throws -> Mesh {
        let fills = options.includeFills ? doc.fills : []
        guard !doc.strokes.isEmpty || !fills.isEmpty else { throw SVGError.noGeometry }

        // Frame: the region of SVG space that is centered on the origin (and, for fixed sizing,
        // scaled to `size` centimeters).
        let frame: (origin: Vec2, size: Vec2)
        if options.framing == .canvas, let c = doc.canvas {
            frame = c
        } else {
            var lo = Vec2(repeating: .infinity), hi = Vec2(repeating: -.infinity)
            for s in doc.strokes {
                for p in s.points {
                    lo = simd_min(lo, p - s.width / 2); hi = simd_max(hi, p + s.width / 2)
                }
            }
            for f in fills { for c in f.contours { for p in c { lo = simd_min(lo, p); hi = simd_max(hi, p) } } }
            frame = (lo, simd_max(hi - lo, Vec2(repeating: 1e-6)))
        }
        let scale = options.sizing == .points
            ? doc.pointsPerUnit * options.millimetersPerPoint / 10
            : options.size / max(frame.size.x, frame.size.y)
        let center = frame.origin + frame.size / 2
        func map(_ p: Vec2) -> Vec3 { Vec3((p.x - center.x) * scale, -(p.y - center.y) * scale, 0) }

        let widths = doc.strokes.map(\.width).sorted()
        let typicalWidth = widths.isEmpty ? max(frame.size.x, frame.size.y) / 12 : widths[widths.count / 2]

        // Strokes outlining a fill belong to the fill's group so blending never bulges the rim.
        let filledElements = Set(fills.filter { $0.strokeWidth != nil }.map(\.element))
        var groups: [PrimitiveGroup] = []
        var elementGroup: [Int: Int] = [:]
        func groupIndex(forElement e: Int?) -> Int {
            if let e, let g = elementGroup[e] { return g }
            groups.append(PrimitiveGroup())
            if let e { elementGroup[e] = groups.count - 1 }
            return groups.count - 1
        }

        var minRadius = Double.infinity
        var radii: [Double] = []

        for f in fills {
            let contours = f.contours.map { $0.map { p -> Vec2 in let m = map(p); return Vec2(m.x, m.y) } }
            let profile: SlabRegion.Profile
            let r: Double
            if f.strokeWidth == nil && options.fillStyle == .extruded {
                r = options.extrudeDepth / doc.pointsPerUnit / 2 * scale
                profile = .extruded(halfDepth: r, edgeRadius: r * min(max(options.extrudeRounding, 0), 1))
            } else {
                r = (f.strokeWidth ?? typicalWidth) / 2 * options.thickness * scale
                profile = .rounded(radius: r)
            }
            guard r > 0 else { continue }
            let g = groupIndex(forElement: f.element)
            groups[g].primitives.append(.slab(SlabRegion(contours: contours, evenOdd: f.evenOdd, profile: profile)))
            minRadius = min(minRadius, r); radii.append(r)
        }

        for s in doc.strokes {
            let r = s.width / 2 * options.thickness * scale
            guard r > 0 else { continue }
            let cap: LineCap = switch options.caps {
            case .svg: s.cap
            case .round: .round
            case .flat: .butt
            }
            var pts = s.points.map(map)
            let g = groupIndex(forElement: filledElements.contains(s.element) ? s.element : nil)
            minRadius = min(minRadius, r); radii.append(r)

            if pts.count == 1 {
                if cap != .butt { groups[g].primitives.append(.sphere(pts[0], r)) }
                continue
            }
            if s.closed {
                for i in 0..<pts.count { groups[g].primitives.append(.capsule(pts[i], pts[(i + 1) % pts.count], r)) }
                continue
            }
            if cap == .round {
                for i in 0..<(pts.count - 1) { groups[g].primitives.append(.capsule(pts[i], pts[i + 1], r)) }
                continue
            }
            if cap == .square {
                pts[0] += simd_normalize(pts[0] - pts[1]) * r
                let n = pts.count
                pts[n - 1] += simd_normalize(pts[n - 1] - pts[n - 2]) * r
            }
            // Flat ends: the first and last segments are flat cylinders; interior joints stay round.
            let last = pts.count - 2
            for i in 0...last {
                if i == 0 || i == last {
                    groups[g].primitives.append(.cylinder(pts[i], pts[i + 1], r))
                } else {
                    groups[g].primitives.append(.capsule(pts[i], pts[i + 1], r))
                }
            }
            for i in 1..<(pts.count - 1) { groups[g].primitives.append(.sphere(pts[i], r)) }
        }

        groups.removeAll { $0.primitives.isEmpty }
        guard !groups.isEmpty, minRadius.isFinite else { throw SVGError.noGeometry }

        // Grid resolution: enough samples across the thinnest tube, capped to keep memory bounded.
        // Facets around a tube ≈ its circumference divided by the grid spacing. When optimizing,
        // sample finer than the target so simplification has room to work: the dense mesh then
        // deviates about half a facet's sag, and collapsing stops at one full sag.
        let oversample = options.optimize ? 1.4 : 1
        var voxel = 2 * Double.pi * minRadius / (max(options.facets, 6) * oversample)
        var total = Box3()
        for g in groups { total.include(g.bounds) }
        let maxSamples = 24_000_000.0
        let size = total.size + Vec3(repeating: 4 * voxel)
        let samples = (size.x / voxel) * (size.y / voxel) * (size.z / voxel)
        if samples > maxSamples { voxel *= cbrt(samples / maxSamples) }

        radii.sort()
        let blend = options.fillet * radii[radii.count / 2]
        // One facet's sag on the thinnest tube: the deviation the facet count already accepts.
        let tolerance = options.optimize ? minRadius * (1 - cos(.pi / max(options.facets, 6))) : 0
        let mesh = FusedMesher(groups: groups, voxel: voxel, blend: blend, tolerance: tolerance).build()
        guard mesh.triangleCount > 0 else { throw ConversionError.emptyMesh }
        return mesh
    }

    /// True for "#RGB" or "#RRGGBB" (the "#" is optional).
    public static func isValidHex(_ s: String) -> Bool {
        var hex = s.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        return (hex.count == 3 || hex.count == 6) && hex.allSatisfy(\.isHexDigit)
    }

    /// Parses "#RGB" or "#RRGGBB" into 0–1 components; anything else gives white.
    public static func parseHex(_ s: String) -> SIMD3<Double> {
        var hex = s.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return SIMD3(1, 1, 1) }
        return SIMD3(Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF)) / 255
    }
}
