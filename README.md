# Tubeline

A free little Mac utility that turns stroked SVG icons into 3D tube models (USDZ) you can drop into Apple Motion.

Drag a pile of SVGs (or folders) onto the window. Every stroke becomes a round tube, as thick as the stroke, and the result is saved as a `.usdz` next to the original or in a folder you choose. A live 3D preview shows exactly what will be exported, with triangle count and real-world size.

## How it turns lines into solids

Tubeline does not sweep separate tubes and stitch them together. It describes the whole icon as one solid (a signed distance field built from every stroke, cap, joint and fill) and extracts a single watertight surface from it with dual contouring. That's why the awkward cases come out clean:

| Artwork | Result |
| --- | --- |
| Lines that cross or overlap | Fused into one surface. **Crisp** keeps a sharp seam; **Soft**/**Round** add a fillet. |
| `stroke-linecap` butt / round / square | Flat end at the point / half-sphere / flat end extended by half the width. |
| `stroke-linejoin` (any) | Corners are rounded, like a tube bent around them. |
| `stroke-dasharray`, `stroke-dashoffset` | Each dash is its own tube with the path's caps. Zero-length dashes with round caps become dots. |
| Closed shape with outline **and** fill | A solid disc whose rim matches the outline tube (no torus). |
| Fill with no outline (e.g. outlined text) | Extruded to a depth you choose, with optional edge rounding, or a rounded "pillow". |
| Implicit black fill (no `fill` attribute) | Ignored. Only fills the file declares count, so line icons don't turn into blobs. |

Also supported: `path` (all commands, arcs included), `line`, `polyline`, `polygon`, `rect` (rounded), `circle`, `ellipse`, groups, nested `transform`s, inline `style`, simple CSS class rules (Illustrator exports), `display="none"`. `<text>`, `<image>` and `<use>` are skipped and reported. Convert text to outlines first.

## Settings

- **Thickness**: tube diameter as a multiple of the stroke width.
- **Facets**: roughly how many sides go around each tube (default 40). The preview shows the triangle count.
- **Ends**: use the SVG's caps, or force round or flat.
- **Intersections**: Crisp, Soft or Round, plus a blend slider.
- **Filled shapes**: include or ignore; extrusion depth (pt) and edge rounding for fill-only shapes.
- **Surface**: *Solid Color* (self-lit flat color that ignores scene lights) or *Shaded* (matte, responds to lights). Pick the color.
- **Scale**: *From Points* (default) maps artwork points to real size, 1 pt = 0.3528 mm (1/72 in). *Fixed Size* scales the frame's longest side to N cm.
- **Frame**: center on the SVG canvas (keeps a set of icons aligned) or on the artwork.

The output is a single mesh with smooth normals and one `UsdPreviewSurface` material, Y-up, centimeters (`metersPerUnit = 0.01`), with no lights or cameras. Files pass Apple's `usdchecker`.

## Building

Requires macOS 14+, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The Xcode project is generated, not committed.

```bash
cd app
xcodegen generate
open Tubeline.xcodeproj          # run the Tubeline scheme; ⌘U runs the tests
```

The geometry engine is the `TubelineCore` Swift package at the repo root, shared
by the app and a command-line tool:

```bash
swift run -c release tubeline Samples -o /tmp/tubeline --png
swift run tubeline --help
```

`Samples/` holds hand-made test SVGs covering the edge cases. Put your own icons
in `Samples/User/` (gitignored).

### Releasing a notarized build

`scripts/release.sh` archives, signs with Developer ID, notarizes, staples, and
writes `dist/Tubeline-<version>.zip`. See the script header for one-time setup.

## Layout

```
Package.swift           TubelineCore engine + tubeline CLI
Sources/TubelineCore/   SVG parsing, dashing, distance-field meshing, USDZ writing, preview scene
Sources/tubeline/       Command-line tool
app/                    Xcode app (project.yml), sandboxed SwiftUI app, unit tests
Samples/                Test SVGs (Samples/User/ is yours, gitignored)
docs/                   Research, release and testing notes
```

## License

MIT © Tent Studios, LLC. Made by Jeff Alldridge.
