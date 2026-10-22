# Tubeline

[![CI](https://github.com/jeffalldridge/tubeline/actions/workflows/ci.yml/badge.svg)](https://github.com/jeffalldridge/tubeline/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%C2%B7%20Apple%20silicon-lightgrey)

A free little Mac utility that turns stroked SVG icons into 3D tube models (USDZ) for motion graphics apps — Apple Motion and any other tool that imports USDZ.

Drag a pile of SVGs (or folders) onto the window. Every stroke becomes a round tube, as thick as the stroke, and the result is saved as a `.usdz` next to the original or in a folder you choose. A live 3D preview shows exactly what will be exported, with triangle count and real-world size.

## Download

Get the latest notarized build from **[Releases](https://github.com/jeffalldridge/tubeline/releases/latest)**: open the DMG and drag Tubeline to Applications. Requires an Apple silicon Mac with macOS 14 or later. A notarized `tubeline` command-line tool is attached to each release too.

## How it turns lines into solids

Tubeline does not sweep separate tubes and stitch them together. It describes the whole icon as one solid (a signed distance field built from every stroke, cap, joint and fill) and extracts a single watertight surface from it with dual contouring. That's why the awkward cases come out clean.

The dense surface is then simplified with quadric edge collapses, each one checked against the exact shape, so long straight runs and flat faces become a few large triangles while curves and seams keep their detail. A typical 24 pt line icon comes out around 5–10k triangles, ready to animate by the dozen.

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
- **Facets**: how many sides go around each tube (default 32). Normals come from the exact surface, so tubes shade round even when light. The preview shows the triangle count.
- **Optimize mesh**: on by default; turn off to keep the dense grid mesh.
- **Ends**: use the SVG's caps, or force round or flat.
- **Intersections**: Crisp, Soft or Round, plus a blend slider.
- **Filled shapes**: include or ignore; extrusion depth (pt) and edge rounding for fill-only shapes.
- **Surface**: *Solid Color* (self-lit flat color that ignores scene lights) or *Shaded* (matte, responds to lights). Pick the color.
- **Scale**: *From Points* (default) maps artwork points to real size, 1 pt = 0.3528 mm (1/72 in). *Fixed Size* scales the frame's longest side to N cm.
- **Frame**: center on the SVG canvas (keeps a set of icons aligned) or on the artwork.

The output is a single mesh with smooth normals and one `UsdPreviewSurface` material, Y-up, centimeters (`metersPerUnit = 0.01`), with no lights or cameras. Files pass Apple's `usdchecker`.

## Building

Requires an Apple silicon Mac with macOS 14+, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
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

`scripts/release.sh --publish` tests, archives, signs with Developer ID, notarizes and
staples the app and DMG, notarizes the CLI, and creates the GitHub Release. See
[docs/release/RELEASING.md](docs/release/RELEASING.md).

## Layout

```
Package.swift           TubelineCore engine + tubeline CLI
Sources/TubelineCore/   SVG parsing, dashing, distance-field meshing, USDZ writing, preview scene
Sources/tubeline/       Command-line tool
app/                    Xcode app (project.yml), sandboxed SwiftUI app, unit tests
Samples/                Test SVGs (Samples/User/ is yours, gitignored)
docs/                   Research, release and testing notes
```

## Roadmap

Next up: **GLB export** for After Effects and other apps, with USDZ staying the default. See [ROADMAP.md](ROADMAP.md) for what's now, next and later.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). An SVG that converts badly is the most useful bug report you can file.

## License

MIT © Tent Studios, LLC. Made by Jeff Alldridge.
