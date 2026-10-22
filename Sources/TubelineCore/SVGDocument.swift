import Foundation

public enum LineCap: String, Sendable, Codable, CaseIterable {
    case butt, round, square
}

/// A stroked centerline, already in SVG user space (after transforms).
public struct StrokePath: Sendable {
    public var points: [Vec2]
    public var closed: Bool
    public var width: Double
    public var cap: LineCap
    /// Index of the SVG element this came from.
    public var element: Int
}

/// A filled area made of one or more closed contours (holes included).
/// `strokeWidth` is set when the same element is also stroked; the fill then
/// becomes a solid slab as thick as that stroke.
public struct FillRegion: Sendable {
    public var contours: [[Vec2]]
    public var evenOdd: Bool
    public var strokeWidth: Double?
    /// Index of the SVG element this came from.
    public var element: Int
}

public struct SVGDocument: Sendable {
    public var strokes: [StrokePath] = []
    public var fills: [FillRegion] = []
    /// The viewBox (or width/height) frame, if the file declared one.
    public var canvas: (origin: Vec2, size: Vec2)?
    /// How many points one SVG user unit is. Design tools treat px and pt as equal,
    /// so this is 1 unless width/height scale the viewBox or use physical units.
    public var pointsPerUnit = 1.0
    /// Physical print points per user unit under SVG's 96 px per inch convention.
    public var physicalPointsPerUnit = 0.75
    /// Elements that were skipped because they are not supported (e.g. `<text>`, `<image>`).
    public var skipped: [String] = []

    public var isEmpty: Bool { strokes.isEmpty && fills.isEmpty }
}

public enum SVGError: LocalizedError {
    case unreadable(String)
    case noGeometry

    public var errorDescription: String? {
        switch self {
        case .unreadable(let why): return "Could not read SVG: \(why)"
        case .noGeometry: return "The SVG has no stroked or filled shapes."
        }
    }
}

/// Parses the subset of SVG that line icons use: shapes, paths, groups,
/// transforms, presentation attributes, inline styles and simple CSS rules.
public final class SVGParser: NSObject, XMLParserDelegate {
    struct State {
        var ctm = Affine.identity
        var props: [String: String] = [:]
        var ignored = false
    }

    private var stack: [State] = [State()]
    private var doc = SVGDocument()
    private var cssRules: [(selector: String, decls: [String: String])] = []
    private var styleText: String?
    private var sawRoot = false
    private let tolerance: Double
    private var parseError: Error?
    private var elementCount = 0

    /// `tolerance` is the maximum curve-flattening error in SVG user units.
    public init(tolerance: Double = 0.01) {
        self.tolerance = tolerance
    }

    public static func parse(url: URL, tolerance: Double = 0.01) throws -> SVGDocument {
        let data = try Data(contentsOf: url)
        return try parse(data: data, tolerance: tolerance)
    }

    public static func parse(data: Data, tolerance: Double = 0.01) throws -> SVGDocument {
        let p = SVGParser(tolerance: tolerance)
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.shouldResolveExternalEntities = false
        if !xml.parse() {
            throw SVGError.unreadable(xml.parserError?.localizedDescription ?? "invalid XML")
        }
        if let e = p.parseError { throw e }
        guard p.sawRoot else { throw SVGError.unreadable("no <svg> element") }
        return p.doc
    }

    // MARK: XMLParserDelegate

    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                       qualifiedName: String?, attributes attrs: [String: String]) {
        let tag = localName(name)
        if tag == "svg", sawRoot {
            doc.skipped.append("Nested <svg> viewport is unsupported; appearance may differ")
        }
        var state = stack.last!
        let containers: Set<String> = ["defs", "clipPath", "mask", "symbol", "marker", "pattern",
                                       "linearGradient", "radialGradient", "filter", "metadata", "title", "desc"]
        if containers.contains(tag) { state.ignored = true }

        // Presentation attributes < CSS rules < style attribute.
        var props = state.props
        props.removeValue(forKey: "display")
        let unsupported: Set<String> = ["clip-path", "mask", "filter", "vector-effect"]
        for (k, v) in attrs where Self.inheritable.contains(k) || k == "display" || unsupported.contains(k) { props[k] = v }
        for rule in cssRules where matches(rule.selector, tag: tag, attrs: attrs) {
            props.merge(rule.decls) { $1 }
        }
        if let style = attrs["style"] { props.merge(Self.parseDecls(style)) { $1 } }
        for feature in unsupported.sorted() {
            if let value = props[feature], value != "none" {
                doc.skipped.append("Unsupported \(feature) on <\(tag)>; appearance may differ")
            }
        }
        if props["transform"] != nil {
            doc.skipped.append("CSS transform on <\(tag)> is unsupported; appearance may differ")
        }
        state.props = props
        if props["display"] == "none" || props["visibility"] == "hidden" { state.ignored = true }
        if let t = attrs["transform"] { state.ctm = state.ctm.concatenating(Self.parseTransform(t)) }
        let ctm = state.ctm
        let xLength = hypot(ctm.a, ctm.b), yLength = hypot(ctm.c, ctm.d)
        let metricScale = max(xLength, yLength, 1e-12)
        if abs(xLength - yLength) > metricScale * 1e-8 || abs(ctm.a * ctm.c + ctm.b * ctm.d) > metricScale * metricScale * 1e-8 {
            doc.skipped.append("Nonuniform scale or shear on <\(tag)> approximates stroke widths")
        }

        if tag == "svg" && !sawRoot {
            sawRoot = true
            readCanvas(attrs)
        }
        if tag == "style" { styleText = "" }

        stack.append(state)
        if !state.ignored { emitShape(tag: tag, attrs: attrs, state: state) }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        styleText?.append(string)
    }

    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        styleText?.append(String(decoding: CDATABlock, as: UTF8.self))
    }

    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if localName(name) == "style", let css = styleText {
            cssRules += Self.parseCSS(css)
            styleText = nil
        }
        if stack.count > 1 { stack.removeLast() }
    }

    // MARK: Shapes

    private static let inheritable: Set<String> = [
        "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-opacity",
        "stroke-dasharray", "stroke-dashoffset",
        "fill", "fill-rule", "fill-opacity", "opacity", "visibility",
    ]

    private func emitShape(tag: String, attrs: [String: String], state: State) {
        let tol = tolerance / max(state.ctm.scaleFactor, 1e-9)
        func num(_ k: String, _ def: Double = 0) -> Double { Self.userLength(attrs[k]) ?? def }
        let geometryLengths = ["x", "y", "x1", "y1", "x2", "y2", "cx", "cy", "r", "rx", "ry", "width", "height"]
        for key in geometryLengths {
            if let value = attrs[key], Self.userLength(value) == nil {
                doc.skipped.append("Unsupported \(key) length on <\(tag)>; appearance may differ")
            }
        }

        var polys: [Polyline2D]
        switch tag {
        case "path":
            polys = PathDataParser.parse(attrs["d"] ?? "", tolerance: tol)
        case "line":
            polys = [Polyline2D(points: [Vec2(num("x1"), num("y1")), Vec2(num("x2"), num("y2"))], closed: false)]
        case "polyline", "polygon":
            let n = Self.numberList(attrs["points"] ?? "")
            var pts: [Vec2] = []
            for i in stride(from: 0, to: n.count - 1, by: 2) { pts.append(Vec2(n[i], n[i + 1])) }
            guard pts.count >= 2 else { return }
            polys = [Polyline2D(points: pts, closed: tag == "polygon" && pts.count > 2)]
        case "rect":
            polys = rect(x: num("x"), y: num("y"), w: num("width"), h: num("height"),
                         rx: Self.userLength(attrs["rx"]), ry: Self.userLength(attrs["ry"]), tol: tol)
        case "circle":
            let r = num("r")
            polys = ellipse(c: Vec2(num("cx"), num("cy")), rx: r, ry: r, tol: tol)
        case "ellipse":
            polys = ellipse(c: Vec2(num("cx"), num("cy")), rx: num("rx"), ry: num("ry"), tol: tol)
        case "text", "image", "use", "foreignObject":
            doc.skipped.append("<\(tag)>")
            return
        default:
            return
        }
        polys = polys.map { Polyline2D(points: $0.points.map(state.ctm.apply), closed: $0.closed) }
        guard !polys.isEmpty else { return }
        let element = elementCount
        elementCount += 1

        let p = state.props
        let opacity = (Double(p["opacity"] ?? "") ?? 1)
        let strokeOn = Self.isPaint(p["stroke"]) && opacity * (Double(p["stroke-opacity"] ?? "") ?? 1) > 0
        // SVG's default fill is black, but in icon files an implicit fill is almost always
        // an accident, so only an explicitly declared fill counts.
        let fillOn = Self.isPaint(p["fill"]) && opacity * (Double(p["fill-opacity"] ?? "") ?? 1) > 0
        if let width = p["stroke-width"], Self.userLength(width) == nil {
            doc.skipped.append("Unsupported stroke-width on <\(tag)>; appearance may differ")
        }
        let strokeWidth = (Self.userLength(p["stroke-width"]) ?? 1) * state.ctm.scaleFactor

        // A file with no paint declared anywhere is treated as plain centerlines.
        let implicitStroke = p["stroke"] == nil && p["fill"] == nil

        if strokeOn || implicitStroke, strokeWidth > 0 {
            let cap = LineCap(rawValue: p["stroke-linecap"] ?? "butt") ?? .butt
            let k = state.ctm.scaleFactor
            let rawDashes = p["stroke-dasharray"] ?? "none"
            let dashLengths = rawDashes == "none" ? [] : Self.lengthList(rawDashes)
            if dashLengths == nil { doc.skipped.append("Unsupported stroke-dasharray on <\(tag)>; appearance may differ") }
            let dashes = (dashLengths ?? []).map { $0 * k }
            let dashOffset = (Self.userLength(p["stroke-dashoffset"]) ?? 0) * k
            for poly in Dasher.split(polys, pattern: dashes, offset: dashOffset) {
                doc.strokes.append(StrokePath(points: poly.points, closed: poly.closed, width: strokeWidth, cap: cap, element: element))
            }
        }
        if fillOn {
            let contours = polys.map(\.points).filter { $0.count >= 3 }
            if !contours.isEmpty {
                doc.fills.append(FillRegion(contours: contours, evenOdd: p["fill-rule"] == "evenodd",
                                            strokeWidth: strokeOn ? strokeWidth : nil, element: element))
            }
        }
    }

    private func rect(x: Double, y: Double, w: Double, h: Double, rx rxIn: Double?, ry ryIn: Double?, tol: Double) -> [Polyline2D] {
        guard w > 0, h > 0 else { return [] }
        var rx = rxIn ?? ryIn ?? 0, ry = ryIn ?? rxIn ?? 0
        rx = min(max(rx, 0), w / 2); ry = min(max(ry, 0), h / 2)
        if rx == 0 || ry == 0 {
            return [Polyline2D(points: [Vec2(x, y), Vec2(x + w, y), Vec2(x + w, y + h), Vec2(x, y + h)], closed: true)]
        }
        let b = PathBuilder(tolerance: tol)
        b.moveTo(Vec2(x + rx, y))
        b.lineTo(Vec2(x + w - rx, y))
        b.arcTo(rx: rx, ry: ry, rotation: 0, largeArc: false, sweep: true, Vec2(x + w, y + ry))
        b.lineTo(Vec2(x + w, y + h - ry))
        b.arcTo(rx: rx, ry: ry, rotation: 0, largeArc: false, sweep: true, Vec2(x + w - rx, y + h))
        b.lineTo(Vec2(x + rx, y + h))
        b.arcTo(rx: rx, ry: ry, rotation: 0, largeArc: false, sweep: true, Vec2(x, y + h - ry))
        b.lineTo(Vec2(x, y + ry))
        b.arcTo(rx: rx, ry: ry, rotation: 0, largeArc: false, sweep: true, Vec2(x + rx, y))
        b.close()
        return b.finish()
    }

    private func ellipse(c: Vec2, rx: Double, ry: Double, tol: Double) -> [Polyline2D] {
        guard rx > 0, ry > 0 else { return [] }
        let n = max(PathBuilder(tolerance: tol).arcSegmentCount(radius: max(rx, ry), sweep: 2 * .pi), 12)
        let pts = (0..<n).map { i -> Vec2 in
            let t = 2 * Double.pi * Double(i) / Double(n)
            return Vec2(c.x + rx * cos(t), c.y + ry * sin(t))
        }
        return [Polyline2D(points: pts, closed: true)]
    }

    private func readCanvas(_ attrs: [String: String]) {
        let vb = Self.numberList(attrs["viewBox"] ?? "")
        if vb.count == 4, vb[2] > 0, vb[3] > 0 {
            doc.canvas = (Vec2(vb[0], vb[1]), Vec2(vb[2], vb[3]))
            let sx = Self.cssPixels(attrs["width"]).map { $0 / vb[2] }
            let sy = Self.cssPixels(attrs["height"]).map { $0 / vb[3] }
            let aspect = attrs["preserveAspectRatio"] ?? "xMidYMid meet"
            if let sx, let sy {
                doc.physicalPointsPerUnit = (aspect.contains("slice") ? max(sx, sy) : min(sx, sy)) * 0.75
                if aspect.contains("none") && abs(sx - sy) > max(sx, sy) * 1e-8 {
                    doc.skipped.append("Nonuniform SVG viewport is unsupported; appearance may differ")
                }
            } else {
                doc.physicalPointsPerUnit = (sx ?? sy ?? 1) * 0.75
            }
            if aspect != "xMidYMid meet" && aspect != "xMidYMid" {
                doc.skipped.append("Custom SVG viewport alignment is unsupported; appearance may differ")
            }
            if let w = Self.points(attrs["width"]) {
                doc.pointsPerUnit = w / vb[2]
            } else if let h = Self.points(attrs["height"]) {
                doc.pointsPerUnit = h / vb[3]
            }
        } else if let w = Self.cssPixels(attrs["width"]), let h = Self.cssPixels(attrs["height"]), w > 0, h > 0,
                  !(attrs["width"] ?? "").hasSuffix("%") {
            doc.canvas = (.zero, Vec2(w, h))
        }
    }

    // MARK: Attribute helpers

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    private func matches(_ selector: String, tag: String, attrs: [String: String]) -> Bool {
        if selector == "*" { return true }
        if selector.hasPrefix(".") {
            let classes = (attrs["class"] ?? "").split(separator: " ").map(String.init)
            return classes.contains(String(selector.dropFirst()))
        }
        if selector.hasPrefix("#") { return attrs["id"] == String(selector.dropFirst()) }
        return selector == tag
    }

    static func isPaint(_ v: String?) -> Bool {
        guard let v = v?.trimmingCharacters(in: .whitespaces).lowercased(), !v.isEmpty else { return false }
        return v != "none" && v != "transparent"
    }

    static func length(_ s: String?) -> Double? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        var sc = PathDataParser.Scanner(Array(s.utf8))
        return sc.number()
    }

    /// A width/height attribute in points, treating px as pt like design tools do.
    static func points(_ s: String?) -> Double? {
        guard let s = s?.trimmingCharacters(in: .whitespaces).lowercased(), let v = length(s), v > 0 else { return nil }
        if s.hasSuffix("%") || s.hasSuffix("em") || s.hasSuffix("ex") { return nil }
        if s.hasSuffix("in") { return v * 72 }
        if s.hasSuffix("cm") { return v * 72 / 2.54 }
        if s.hasSuffix("mm") { return v * 72 / 25.4 }
        if s.hasSuffix("pc") { return v * 12 }
        return v
    }

    /// SVG geometry lengths resolve to CSS user units before viewport scaling.
    static func userLength(_ s: String?) -> Double? {
        guard let s = s?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
        var scanner = PathDataParser.Scanner(Array(s.utf8))
        guard let value = scanner.number() else { return nil }
        let suffix = String(decoding: scanner.c[scanner.i...], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        let factor: Double
        switch suffix {
        case "", "px": factor = 1
        case "in": factor = 96
        case "cm": factor = 96 / 2.54
        case "mm": factor = 96 / 25.4
        case "q": factor = 96 / 101.6
        case "pt": factor = 96 / 72
        case "pc": factor = 16
        default: return nil
        }
        let resolved = value * factor
        return resolved.isFinite ? resolved : nil
    }

    static func cssPixels(_ s: String?) -> Double? {
        guard let value = userLength(s), value.isFinite, value > 0 else { return nil }
        return value
    }

    static func lengthList(_ s: String) -> [Double]? {
        let tokens = s.split { $0 == "," || $0.isWhitespace }
        var values: [Double] = []
        for token in tokens {
            guard let value = userLength(String(token)) else { return nil }
            values.append(value)
        }
        return values
    }

    static func numberList(_ s: String) -> [Double] {
        var sc = PathDataParser.Scanner(Array(s.utf8))
        var out: [Double] = []
        while let n = sc.number() { out.append(n) }
        return out
    }

    static func parseDecls(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for decl in s.split(separator: ";") {
            let kv = decl.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let k = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let v = kv[1].replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            out[k] = v
        }
        return out
    }

    static func parseCSS(_ css: String) -> [(String, [String: String])] {
        var out: [(String, [String: String])] = []
        var text = css
        while let r = text.range(of: "/*"), let e = text.range(of: "*/", range: r.upperBound..<text.endIndex) {
            text.removeSubrange(r.lowerBound..<e.upperBound)
        }
        for block in text.split(separator: "}") {
            let parts = block.split(separator: "{", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let decls = parseDecls(String(parts[1]))
            for sel in parts[0].split(separator: ",") {
                out.append((sel.trimmingCharacters(in: .whitespacesAndNewlines), decls))
            }
        }
        return out
    }

    static func parseTransform(_ s: String) -> Affine {
        var m = Affine.identity
        var rest = Substring(s)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let name = rest[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " ,\t\n\r"))
            let v = numberList(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
            func arg(_ i: Int, _ def: Double = 0) -> Double { i < v.count ? v[i] : def }
            let t: Affine
            switch name {
            case "matrix" where v.count == 6: t = Affine(v[0], v[1], v[2], v[3], v[4], v[5])
            case "translate": t = .translate(arg(0), arg(1))
            case "scale": t = .scale(arg(0, 1), arg(1, arg(0, 1)))
            case "rotate":
                let r = Affine.rotate(degrees: arg(0))
                t = v.count >= 3
                    ? Affine.translate(v[1], v[2]).concatenating(r).concatenating(.translate(-v[1], -v[2]))
                    : r
            case "skewX": t = Affine(1, 0, tan(arg(0) * .pi / 180), 1, 0, 0)
            case "skewY": t = Affine(1, tan(arg(0) * .pi / 180), 0, 1, 0, 0)
            default: continue
            }
            m = m.concatenating(t)
        }
        return m
    }
}
