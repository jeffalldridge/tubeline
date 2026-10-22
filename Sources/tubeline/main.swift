import Foundation
import TubelineCore

let usage = """
usage: tubeline [options] <file.svg | folder> ...

Turns stroked SVG icons into 3D tube models (.usdz) for Apple Motion.

options:
  -o, --output <dir>      Write results here (default: next to each SVG)
  --thickness <x>         Tube diameter as a multiple of the stroke width (default 1)
  --facets <n>            Sides around each tube, 12–96 (default 32)
  --fillet <x>            Rounding where strokes meet, 0–1 × tube radius (default 0 = crisp)
  --caps <c>              svg | round | flat (default svg)
  --no-optimize           Keep the dense grid mesh (no simplification)
  --no-fills              Ignore filled shapes
  --fill-style <s>        Fills without an outline: extruded | rounded (default extruded)
  --depth <pt>            Extrusion depth for those fills, in artwork points (default 4)
  --edge-rounding <x>     Rounding of extruded edges, 0–1 (default 0.1)
  --framing <f>           canvas | content (default canvas)
  --pt <mm>               Size of one artwork point in millimeters (default 0.3528, i.e. 1/72 in)
  --size <cm>             Instead, scale the frame's longest side to this many centimeters
  --color <#RRGGBB>       Surface color (default #FFFFFF)
  --surface <s>           solid (flat, self-lit color) | shaded (default solid)
  --png                   Also render a preview image next to each model
"""

var options = ConversionOptions()
var inputs: [URL] = []
var outputDir: URL?
var renderPNG = false

var args = CommandLine.arguments.dropFirst()
func value(_ flag: String) -> String {
    guard let v = args.popFirst() else {
        FileHandle.standardError.write(Data("missing value for \(flag)\n".utf8))
        exit(2)
    }
    return v
}
while let a = args.popFirst() {
    switch a {
    case "-h", "--help": print(usage); exit(0)
    case "-o", "--output": outputDir = URL(fileURLWithPath: value(a))
    case "--thickness": options.thickness = Double(value(a)) ?? 1
    case "--facets": options.facets = Double(value(a)) ?? 32
    case "--fillet": options.fillet = Double(value(a)) ?? 0
    case "--caps": options.caps = .init(rawValue: value(a)) ?? .svg
    case "--no-fills": options.includeFills = false
    case "--no-optimize": options.optimize = false
    case "--fill-style": options.fillStyle = .init(rawValue: value(a)) ?? .extruded
    case "--depth": options.extrudeDepth = Double(value(a)) ?? 4
    case "--edge-rounding": options.extrudeRounding = Double(value(a)) ?? 0.1
    case "--framing": options.framing = .init(rawValue: value(a)) ?? .canvas
    case "--pt": options.millimetersPerPoint = Double(value(a)) ?? 25.4 / 72; options.sizing = .points
    case "--size": options.size = Double(value(a)) ?? 10; options.sizing = .fixed
    case "--color": options.color = value(a)
    case "--surface": options.surface = .init(rawValue: value(a)) ?? .solid
    case "--png": renderPNG = true
    default: inputs.append(URL(fileURLWithPath: a))
    }
}

let files = SVGFinder.collect(inputs)
if files.isEmpty {
    print(usage)
    exit(inputs.isEmpty ? 0 : 1)
}
if let outputDir { try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true) }

var failures = 0
for svg in files {
    let out = (outputDir ?? svg.deletingLastPathComponent())
        .appendingPathComponent(svg.deletingPathExtension().lastPathComponent + ".usdz")
    do {
        let r = try Converter.convert(svg: svg, to: out, options: options)
        var line = String(format: "✓ %@ → %@  (%.2f × %.2f × %.2f cm, %d tris, %.2fs)", svg.lastPathComponent, out.lastPathComponent,
                          r.dimensions.x, r.dimensions.y, r.dimensions.z, r.triangles, r.seconds)
        if !r.skipped.isEmpty { line += "  skipped: " + r.skipped.joined(separator: ", ") }
        print(line)
        if renderPNG {
            try PreviewScene.renderPNG(usdz: out, to: out.deletingPathExtension().appendingPathExtension("png"))
        }
    } catch {
        failures += 1
        print("✗ \(svg.lastPathComponent): \(error.localizedDescription)")
    }
}
exit(failures == 0 ? 0 : 1)
