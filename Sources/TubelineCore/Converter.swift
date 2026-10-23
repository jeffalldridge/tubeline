import Foundation
import simd

public struct ConversionOptions: Codable, Equatable, Sendable {
    public enum Sizing: String, Codable, CaseIterable, Sendable {
        /// Artwork points map to a physical size (`millimetersPerPoint`).
        case points
        /// Honor SVG physical dimensions and CSS pixels (96 px per inch).
        case physical
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
    /// Integer multiplier applied after sizing, for both USDZ and GLB. The default is 10×: at true
    /// print size (1×) icons import into After Effects far too small, and Motion's default
    /// Automatic size normalizes imports regardless, so 10× works well in both.
    public var outputScale = 10
    /// Simplify the mesh: long straight runs and flat faces collapse to a few large triangles,
    /// keeping the surface within one facet's sag of the exact shape.
    public var optimize = true
    /// Surface color as #RRGGBB.
    public var color = "#FFFFFF"
    public var surface = Surface.solid

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case thickness, facets, fillet, caps, includeFills, fillStyle, extrudeDepth, extrudeRounding, framing, sizing, millimetersPerPoint, size, outputScale, optimize, color, surface
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        thickness = try values.decodeIfPresent(Double.self, forKey: .thickness) ?? thickness
        facets = try values.decodeIfPresent(Double.self, forKey: .facets) ?? facets
        fillet = try values.decodeIfPresent(Double.self, forKey: .fillet) ?? fillet
        caps = try values.decodeIfPresent(Caps.self, forKey: .caps) ?? caps
        includeFills = try values.decodeIfPresent(Bool.self, forKey: .includeFills) ?? includeFills
        fillStyle = try values.decodeIfPresent(FillStyle.self, forKey: .fillStyle) ?? fillStyle
        extrudeDepth = try values.decodeIfPresent(Double.self, forKey: .extrudeDepth) ?? extrudeDepth
        extrudeRounding = try values.decodeIfPresent(Double.self, forKey: .extrudeRounding) ?? extrudeRounding
        framing = try values.decodeIfPresent(Framing.self, forKey: .framing) ?? framing
        sizing = try values.decodeIfPresent(Sizing.self, forKey: .sizing) ?? sizing
        millimetersPerPoint = try values.decodeIfPresent(Double.self, forKey: .millimetersPerPoint) ?? millimetersPerPoint
        size = try values.decodeIfPresent(Double.self, forKey: .size) ?? size
        outputScale = try values.decodeIfPresent(Int.self, forKey: .outputScale) ?? outputScale
        optimize = try values.decodeIfPresent(Bool.self, forKey: .optimize) ?? optimize
        color = try values.decodeIfPresent(String.self, forKey: .color) ?? color
        surface = try values.decodeIfPresent(Surface.self, forKey: .surface) ?? surface
    }
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
    case invalidOptions
    case invalidMesh(String)
    case resolutionLimit
    public var errorDescription: String? {
        switch self {
        case .emptyMesh: return "No geometry was produced."
        case .invalidOptions: return "The conversion settings contain an invalid size or quality value."
        case .invalidMesh(let reason): return "The generated surface is not a valid closed mesh: \(reason)"
        case .resolutionLimit: return "The artwork is too large or detailed to preserve its thinnest features. Increase the smallest stroke width or reduce the artwork's extent."
        }
    }
}

public enum Converter {
    /// File formats Tubeline writes, chosen by each output file's extension.
    public enum Format: String, Codable, CaseIterable, Sendable {
        case usdz, glb

        public init?(url: URL) { self.init(rawValue: url.pathExtension.lowercased()) }
    }

    /// Converts an SVG file to a USDZ or GLB file, chosen by the output's extension.
    @discardableResult
    public static func convert(svg: URL, to output: URL, options: ConversionOptions) throws -> ConversionReport {
        try convert(svg: svg, to: [output], options: options)
    }

    /// Converts an SVG file once and writes the same mesh to every output (for example, a .usdz
    /// and a .glb). Returns statistics about the result.
    @discardableResult
    public static func convert(svg: URL, to outputs: [URL], options: ConversionOptions) throws -> ConversionReport {
        let start = Date()
        try Task.checkCancellation()
        let doc = try SVGParser.parse(url: svg, tolerance: 0.005)
        let mesh = try buildMesh(doc, options: options)
        let b = mesh.bounds
        var profiler = Profiler()
        for output in outputs {
            try Task.checkCancellation()
            let name = output.deletingPathExtension().lastPathComponent
            switch Format(url: output) ?? .usdz {
            case .usdz:
                try USDZWriter.write(mesh: mesh, name: name, color: parseHex(options.color), surface: options.surface, to: output)
            case .glb:
                try GLBWriter.write(mesh: mesh, name: name, color: parseHex(options.color), surface: options.surface, to: output)
            }
            profiler.lap("write \(output.pathExtension.uppercased())")
        }
        return ConversionReport(strokes: doc.strokes.count, fills: options.includeFills ? doc.fills.count : 0,
                                vertices: mesh.positions.count, triangles: mesh.triangleCount, dimensions: b.size,
                                skipped: Array(Set(doc.skipped + mesh.warnings)).sorted(), seconds: Date().timeIntervalSince(start))
    }

    public static func buildMesh(_ doc: SVGDocument, options: ConversionOptions) throws -> Mesh {
        try Task.checkCancellation()
        let positive = [options.thickness, options.facets, options.size, options.millimetersPerPoint, options.extrudeDepth]
        guard positive.allSatisfy({ $0.isFinite && $0 > 0 }),
              options.fillet.isFinite, options.fillet >= 0, options.fillet <= 1,
              options.extrudeRounding.isFinite, (6...256).contains(options.facets),
              (1...10_000).contains(options.outputScale) else { throw ConversionError.invalidOptions }
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
        guard [frame.origin.x, frame.origin.y, frame.size.x, frame.size.y,
               doc.pointsPerUnit, doc.physicalPointsPerUnit].allSatisfy(\.isFinite),
              frame.size.x > 0, frame.size.y > 0,
              doc.pointsPerUnit > 0, doc.physicalPointsPerUnit > 0 else {
            throw SVGError.unreadable("coordinates or units are outside the supported range")
        }
        let outputScale: Double
        switch options.sizing {
        case .points: outputScale = doc.pointsPerUnit * options.millimetersPerPoint / 10
        case .physical: outputScale = doc.physicalPointsPerUnit * 2.54 / 72
        case .fixed: outputScale = options.size / max(frame.size.x, frame.size.y)
        }
        let widths = doc.strokes.map(\.width).sorted()
        let typicalWidth = widths.isEmpty ? max(frame.size.x, frame.size.y) / 12 : widths[widths.count / 2]
        var featureRadii = widths.map { $0 * options.thickness / 2 }
        let depthPointsPerUnit = options.sizing == .physical ? doc.physicalPointsPerUnit : doc.pointsPerUnit
        for fill in fills {
            let radius = fill.strokeWidth == nil && options.fillStyle == .extruded
                ? options.extrudeDepth / depthPointsPerUnit / 2
                : (fill.strokeWidth ?? typicalWidth) * options.thickness / 2
            if radius > 0 { featureRadii.append(radius) }
        }
        guard let unit = featureRadii.filter({ $0.isFinite && $0 > 0 }).min() else { throw SVGError.noGeometry }
        // Numerical thresholds and Float storage operate in tube radii. Physical output sizing
        // happens only after contouring, so changing centimeters cannot change the topology.
        let scale = 1 / unit
        guard scale.isFinite, outputScale.isFinite, outputScale > 0 else {
            throw SVGError.unreadable("coordinates or units are outside the supported range")
        }
        let center = frame.origin + frame.size / 2
        func map(_ p: Vec2) -> Vec3 { Vec3((p.x - center.x) * scale, -(p.y - center.y) * scale, 0) }

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
                r = options.extrudeDepth / depthPointsPerUnit / 2 * scale
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
            let startPlane = TubeClip(origin: pts[0], outward: simd_normalize(pts[0] - pts[1]))
            let endPlane = TubeClip(origin: pts[pts.count - 1], outward: simd_normalize(pts[pts.count - 1] - pts[pts.count - 2]))
            // Keep each cap plane until the centerline has cleared it by a radius. Clipping
            // only the first cylinder lets neighboring short segments round off the cap.
            // Once clear, returning parts of a loop retain their own geometry.
            var startLast = pts.count - 2
            for i in 0..<(pts.count - 1) where startPlane.distance(pts[i + 1]) <= -r {
                startLast = i; break
            }
            var endFirst = 0
            for i in stride(from: pts.count - 2, through: 0, by: -1) where endPlane.distance(pts[i]) <= -r {
                endFirst = i; break
            }
            for i in 0..<(pts.count - 1) {
                let start: TubeClip? = i <= startLast ? startPlane : nil
                let end: TubeClip? = i >= endFirst ? endPlane : nil
                if start == nil && end == nil {
                    groups[g].primitives.append(.capsule(pts[i], pts[i + 1], r))
                } else {
                    groups[g].primitives.append(.clippedCapsule(pts[i], pts[i + 1], r, start, end))
                }
            }
        }

        groups.removeAll { $0.primitives.isEmpty }
        guard !groups.isEmpty, minRadius.isFinite else { throw SVGError.noGeometry }

        // Grid resolution: enough samples across the thinnest tube, capped to keep memory bounded.
        // Facets around a tube ≈ its circumference divided by the grid spacing. When optimizing,
        // sample finer than the target so simplification has room to work: the dense mesh then
        // deviates about half a facet's sag, and collapsing stops at one full sag.
        let oversample = options.optimize ? 1.4 : 1
        var voxel = 2 * Double.pi * minRadius / (max(options.facets, 6) * oversample)
        let requestedVoxel = voxel
        var total = Box3()
        for g in groups { total.include(g.bounds) }
        guard [total.min.x, total.min.y, total.min.z, total.max.x, total.max.y, total.max.z,
               total.size.x, total.size.y, total.size.z].allSatisfy(\.isFinite) else {
            throw SVGError.unreadable("coordinates are outside the supported range")
        }
        try Task.checkCancellation()
        let maxSamples = 24_000_000.0
        radii.sort()
        let blend = options.fillet * radii[radii.count / 2]
        func sampleCount(_ h: Double) -> Double {
            let padding = 4 * h + 2 * blend
            let counts = (total.size + Vec3(repeating: padding)) / h
            return (ceil(counts.x) + 1) * (ceil(counts.y) + 1) * (ceil(counts.z) + 1)
        }
        // Include rounded-up dimensions and padding at the new spacing. A one-pass
        // cube-root estimate undercounts very flat or elongated artwork.
        for _ in 0..<64 {
            let count = sampleCount(voxel)
            guard count.isFinite else { throw ConversionError.resolutionLimit }
            if count <= maxSamples { break }
            voxel *= max(1.05, cbrt(count / maxSamples))
        }
        guard voxel.isFinite, sampleCount(voxel) <= maxSamples, voxel <= 2 * minRadius else {
            throw ConversionError.resolutionLimit
        }

        // One facet's sag on the thinnest tube: the deviation the facet count already accepts.
        let tolerance = options.optimize ? minRadius * (1 - cos(.pi / max(options.facets, 6))) : 0
        var mesh = FusedMesher(groups: groups, voxel: voxel, blend: blend, tolerance: tolerance).build()
        try Task.checkCancellation()
        guard mesh.triangleCount > 0 else { throw ConversionError.emptyMesh }
        let physicalScale = Float(outputScale * Double(options.outputScale) / scale)
        mesh.positions = mesh.positions.map { $0 * physicalScale }
        var validationProfiler = Profiler()
        let outputValidation = mesh.validation()
        validationProfiler.lap("final validation")
        guard outputValidation.isValid else { throw ConversionError.invalidMesh(outputValidation.summary) }
        if voxel > requestedVoxel * 1.0001 {
            mesh.warnings.append("The artwork exceeded the sampling limit. Small details may be less accurate. Reduce the artwork's extent or increase narrow stroke widths for finer detail.")
        }
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
