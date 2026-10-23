import Foundation
import Darwin
import TubelineCore

let version = "0.3.1"

let usage = """
Usage: tubeline [options] <file.svg | folder> ...

Turns stroked SVG icons into 3D tube models for motion graphics apps: USDZ for
Apple Motion, or GLB for After Effects, Cinema 4D, and Blender.

Output:
  -o, --output <folder>     Save models here (default: next to each SVG)
  --format <usdz|glb|both>  File format: USDZ for Apple Motion and Apple apps, GLB for
                            After Effects, Cinema 4D, and Blender (default usdz)
  --replace                 Replace existing exports (default: keep both)
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
  --physical                Honor SVG dimensions and standard SVG pixel units
  --size <cm>               Instead, fit the longest frame side in centimeters before output scale
  --scale <integer>         Multiply exported dimensions, 1 to 10000 (default 10; 1 is true print size)
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
var replaceExisting = false
var formats: [Converter.Format] = [.usdz]

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
    case "--replace": replaceExisting = true
    case "--format":
        switch value(a) {
        case "usdz": formats = [.usdz]
        case "glb": formats = [.glb]
        case "both": formats = [.usdz, .glb]
        default: fail("--format must be one of: usdz, glb, both")
        }
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
    case "--physical": options.sizing = .physical
    case "--size": options.size = number(a, in: 0.001...100_000); options.sizing = .fixed
    case "--scale":
        let scale = number(a, in: 1...10_000)
        guard scale == scale.rounded() else { fail("--scale expects a whole number") }
        options.outputScale = Int(scale)
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
for input in inputs where !FileManager.default.fileExists(atPath: input.path) {
    fail("input does not exist: \(input.path)")
}
var seenInputs = Set<URL>()
let files = SVGFinder.collect(inputs).filter { seenInputs.insert($0.standardizedFileURL).inserted }
if files.isEmpty { fail("no SVG files found in \(inputs.map(\.path).joined(separator: ", "))") }
if let outputDir {
    do {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    } catch {
        fail("can't create \(outputDir.path): \(error.localizedDescription)")
    }
}

// Reserve the whole batch before writing so identical names never replace one another,
// even when replacement of older exports was explicitly requested. Each icon reserves one
// name (stem) for all of its files: every chosen format, plus the preview image.
var reservedPaths = Set<String>()
func pathKey(_ url: URL) -> String { url.standardizedFileURL.path.lowercased() }
func targets(_ stem: URL) -> [URL] {
    formats.map { stem.appendingPathExtension($0.rawValue) } + (renderPNG ? [stem.appendingPathExtension("png")] : [])
}
let exports = files.map { svg -> (URL, URL) in
    let dir = outputDir ?? svg.deletingLastPathComponent()
    let name = svg.deletingPathExtension().lastPathComponent
    var suffix = 1
    while true {
        let stem = dir.appendingPathComponent(suffix == 1 ? name : "\(name) \(suffix)")
        let collides = targets(stem).contains {
            reservedPaths.contains(pathKey($0)) || (!replaceExisting && FileManager.default.fileExists(atPath: $0.path))
        }
        if !collides {
            for target in targets(stem) { reservedPaths.insert(pathKey(target)) }
            return (svg, stem)
        }
        suffix += 1
    }
}

func publishFile(_ staged: URL, to destination: URL) throws {
    // The kernel must reject an occupied name; a preflight check cannot protect
    // against another process publishing after the check.
    let flags = replaceExisting ? 0 : UInt32(RENAME_EXCL)
    guard renamex_np(staged.path, destination.path, flags) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                      userInfo: [NSFilePathErrorKey: destination.path])
    }
}

/// Publishes every staged model under one stem, moving to the next free stem if another
/// process takes a name first. Returns the published model files.
func publishModels(_ staged: [URL], proposed: URL) throws -> [URL] {
    var stem = proposed
    var suffix = 2
    while true {
        let reservedByAnotherJob = stem != proposed && targets(stem).contains { reservedPaths.contains(pathKey($0)) }
        let png = stem.appendingPathExtension("png")
        if !reservedByAnotherJob && (replaceExisting || !renderPNG || !FileManager.default.fileExists(atPath: png.path)) {
            var published: [URL] = []
            do {
                for file in staged {
                    let destination = stem.appendingPathExtension(file.pathExtension)
                    try publishFile(file, to: destination)
                    published.append(destination)
                }
                for target in targets(stem) { reservedPaths.insert(pathKey(target)) }
                return published
            } catch {
                let error = error as NSError
                guard !replaceExisting, error.domain == NSPOSIXErrorDomain, error.code == Int(EEXIST) else { throw error }
                // Another process took one of the names. Take back what this attempt published
                // so the icon's files stay together under the next free name.
                for (file, destination) in zip(staged, published) { _ = renamex_np(destination.path, file.path, 0) }
            }
        }
        stem = proposed.deletingLastPathComponent()
            .appendingPathComponent("\(proposed.lastPathComponent) \(suffix)")
        suffix += 1
    }
}

var failures = 0
for (svg, stem) in exports {
    let stagingDirectory = stem.deletingLastPathComponent()
        .appendingPathComponent(".Tubeline-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: stagingDirectory) }
    do {
        // A sibling directory keeps publication on the same volume, where rename is atomic.
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        let stagedModels = formats.map {
            stagingDirectory.appendingPathComponent(stem.lastPathComponent).appendingPathExtension($0.rawValue)
        }
        // Previews render through SceneKit, which reads USDZ, so a GLB-only export still
        // writes a private USDZ copy for the image.
        let previewSource = stagingDirectory.appendingPathComponent("preview.usdz")
        let needsPreviewSource = renderPNG && !formats.contains(.usdz)
        let r = try Converter.convert(svg: svg, to: stagedModels + (needsPreviewSource ? [previewSource] : []),
                                      options: options)
        let published = try publishModels(stagedModels, proposed: stem)
        let paths = published.map(\.path).joined(separator: ", ")
        var line = String(format: "✓ %@ → %@ (%.2f × %.2f × %.2f cm, %@ triangles, %.2f s)",
                          svg.lastPathComponent, paths,
                          r.dimensions.x, r.dimensions.y, r.dimensions.z, r.triangles.formatted(), r.seconds)
        if !r.skipped.isEmpty { line += "; warnings: " + r.skipped.joined(separator: ", ") }
        if renderPNG {
            let modelStem = published[0].deletingPathExtension()
            do {
                let stagedPNG = stagingDirectory.appendingPathComponent("preview.png")
                let source = published.first { $0.pathExtension == "usdz" } ?? previewSource
                try PreviewScene.renderPNG(usdz: source, to: stagedPNG,
                                           size: CGSize(width: pngSize, height: pngSize),
                                           transparent: pngTransparent, tilt: pngTransparent ? 0 : 0.35)
                try publishFile(stagedPNG, to: modelStem.appendingPathExtension("png"))
            } catch {
                failures += 1
                FileHandle.standardError.write(Data("\(svg.lastPathComponent): model saved to \(paths), but the preview image failed: \(error.localizedDescription)\n".utf8))
                continue
            }
        }
        print(line)
    } catch {
        failures += 1
        FileHandle.standardError.write(Data("✗ \(svg.lastPathComponent): \(error.localizedDescription)\n".utf8))
    }
}
exit(failures == 0 ? 0 : 1)
