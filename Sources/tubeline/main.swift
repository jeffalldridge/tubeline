import Foundation
import TubelineCore

let version = "0.1.0"

let usage = """
Usage: tubeline [options] <file.svg | folder> ...

Turns stroked SVG icons into 3D tube models (USDZ) for Apple Motion and other
motion graphics apps that import USDZ.

Output:
  -o, --output <folder>     Save models here (default: next to each SVG)
  --png                     Also save a preview image next to each model
  --png-size <pixels>       Size of the preview image (default 1024)
  --png-transparent         Transparent background, viewed head-on (for icons)

Shape:
  --thickness <n>           Tube diameter as a multiple of the stroke width (default 1)
  --facets <n>              Sides around each tube, 6 to 256 (default 32)
  --caps <svg|round|flat>   Line ends: as in the SVG, or always round or flat (default svg)
  --fillet <n>              Rounding where strokes meet, 0 (crisp) to 1 (default 0)
  --no-optimize             Keep the dense mesh instead of simplifying it
  --no-fills                Ignore filled shapes
  --fill-style <extruded|rounded>
                            Shape of fills that have no outline (default extruded)
  --depth <points>          Extrusion depth for those fills (default 4)
  --edge-rounding <n>       Rounding of extruded edges, 0 to 1 (default 0.1)

Size:
  --pt <mm>                 Size of one artwork point (default 0.3528, which is 1/72 inch)
  --size <cm>               Instead, scale the longest side to this many centimeters
  --framing <canvas|content>
                            Center on the SVG canvas or on the artwork (default canvas)

Look:
  --surface <solid|shaded>  Flat color that ignores lights, or matte shading (default solid)
  --color <#RRGGBB>         Surface color (default #FFFFFF)

  -h, --help                Show this help
  --version                 Show the version
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("tubeline: \(message)\nRun 'tubeline --help' for usage.\n".utf8))
    exit(2)
}

var options = ConversionOptions()
var inputs: [URL] = []
var outputDir: URL?
var renderPNG = false
var pngSize = 1024.0
var pngTransparent = false

var args = CommandLine.arguments.dropFirst()

func value(_ flag: String) -> String {
    guard let v = args.popFirst() else { fail("\(flag) needs a value") }
    return v
}

func number(_ flag: String, in range: ClosedRange<Double>? = nil) -> Double {
    let raw = value(flag)
    guard let n = Double(raw), n.isFinite else { fail("\(flag) expects a number, not '\(raw)'") }
    if let range, !range.contains(n) {
        fail("\(flag) must be between \(range.lowerBound.formatted()) and \(range.upperBound.formatted())")
    }
    return n
}

func choice<T: RawRepresentable & CaseIterable>(_ flag: String, _: T.Type) -> T where T.RawValue == String {
    let raw = value(flag)
    guard let v = T(rawValue: raw) else {
        fail("\(flag) must be one of: \(T.allCases.map(\.rawValue).joined(separator: ", "))")
    }
    return v
}

while let a = args.popFirst() {
    switch a {
    case "-h", "--help": print(usage); exit(0)
    case "--version": print("tubeline \(version)"); exit(0)
    case "-o", "--output": outputDir = URL(fileURLWithPath: value(a))
    case "--png": renderPNG = true
    case "--png-size": pngSize = number(a, in: 64...8192); renderPNG = true
    case "--png-transparent": pngTransparent = true; renderPNG = true
    case "--thickness": options.thickness = number(a, in: 0.05...10)
    case "--facets": options.facets = number(a, in: 6...256)
    case "--caps": options.caps = choice(a, ConversionOptions.Caps.self)
    case "--fillet": options.fillet = number(a, in: 0...1)
    case "--no-optimize": options.optimize = false
    case "--no-fills": options.includeFills = false
    case "--fill-style": options.fillStyle = choice(a, ConversionOptions.FillStyle.self)
    case "--depth": options.extrudeDepth = number(a, in: 0.01...1000)
    case "--edge-rounding": options.extrudeRounding = number(a, in: 0...1)
    case "--pt": options.millimetersPerPoint = number(a, in: 0.001...1000); options.sizing = .points
    case "--size": options.size = number(a, in: 0.001...100_000); options.sizing = .fixed
    case "--framing": options.framing = choice(a, ConversionOptions.Framing.self)
    case "--surface": options.surface = choice(a, ConversionOptions.Surface.self)
    case "--color":
        let c = value(a)
        guard Converter.isValidHex(c) else { fail("--color expects a hex color like #FFFFFF, not '\(c)'") }
        options.color = c
    default:
        if a.hasPrefix("-") { fail("unknown option '\(a)'") }
        inputs.append(URL(fileURLWithPath: a))
    }
}

if inputs.isEmpty {
    print(usage)
    exit(0)
}
let files = SVGFinder.collect(inputs)
if files.isEmpty { fail("no SVG files found in \(inputs.map(\.path).joined(separator: ", "))") }
if let outputDir {
    do {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    } catch {
        fail("can't create \(outputDir.path): \(error.localizedDescription)")
    }
}

var failures = 0
for svg in files {
    let out = (outputDir ?? svg.deletingLastPathComponent())
        .appendingPathComponent(svg.deletingPathExtension().lastPathComponent + ".usdz")
    do {
        let r = try Converter.convert(svg: svg, to: out, options: options)
        var line = String(format: "✓ %@ → %@ (%.2f × %.2f × %.2f cm, %@ triangles, %.2f s)",
                          svg.lastPathComponent, out.lastPathComponent,
                          r.dimensions.x, r.dimensions.y, r.dimensions.z, r.triangles.formatted(), r.seconds)
        if !r.skipped.isEmpty { line += "; skipped " + r.skipped.joined(separator: ", ") }
        print(line)
        if renderPNG {
            try PreviewScene.renderPNG(usdz: out, to: out.deletingPathExtension().appendingPathExtension("png"),
                                       size: CGSize(width: pngSize, height: pngSize),
                                       transparent: pngTransparent, tilt: pngTransparent ? 0 : 0.35)
        }
    } catch {
        failures += 1
        FileHandle.standardError.write(Data("✗ \(svg.lastPathComponent): \(error.localizedDescription)\n".utf8))
    }
}
exit(failures == 0 ? 0 : 1)
