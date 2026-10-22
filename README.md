# Tubeline

[![CI](https://github.com/jeffalldridge/tubeline/actions/workflows/ci.yml/badge.svg)](https://github.com/jeffalldridge/tubeline/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%C2%B7%20Apple%20silicon-lightgrey)

Tubeline is a free Mac app that turns stroked SVG icons into 3D tube models. It saves them as USDZ files for Apple Motion and other motion graphics apps that import USDZ.

Drop SVG files or folders onto the window. Each stroke becomes a round tube as thick as the stroke, and the model is saved next to the original or in a folder you choose. A 3D preview shows exactly what will be exported, along with its triangle count and real-world size.

## Download

Download the latest build from [Releases](https://github.com/jeffalldridge/tubeline/releases/latest), open the DMG, and drag Tubeline to your Applications folder. You need an Apple silicon Mac running macOS 14 or later. Each release also includes a `tubeline` command-line tool. Both are signed by Tent Studios and notarized by Apple.

## How It Works

Tubeline doesn't build each tube separately and stitch them together. It models the whole icon as a single solid, using a signed distance field built from every stroke, cap, joint, and fill, and then extracts one closed surface from it with dual contouring. That's why overlaps and crossings come out clean.

It then simplifies the surface by collapsing edges, checking each change against the exact shape. Long straight runs and flat faces end up as a few large triangles, while curves and seams keep their detail. A typical 24 pt line icon comes out at 5,000–10,000 triangles, light enough to animate dozens at a time.

| In the SVG | In the model |
| --- | --- |
| Lines that cross or overlap | One fused surface. Crisp keeps a sharp seam; Soft and Round add a fillet. |
| `stroke-linecap`: butt, round, square | A flat end at the endpoint, a half sphere, or a flat end extended by half the stroke width |
| `stroke-linejoin` (any value) | A rounded corner, as if the tube were bent |
| `stroke-dasharray` and `stroke-dashoffset` | A separate tube for each dash, with the path's caps. Zero-length dashes with round caps become dots. |
| A closed shape with both an outline and a fill | A solid disc whose edge matches the outline tube |
| A fill with no outline (e.g., outlined text) | An extrusion at the depth you choose, with optional rounded edges, or a rounded slab |
| A shape with no `fill` attribute | No fill. SVG's default black fill is ignored so line icons don't turn into solid blobs. |

Tubeline also reads every `path` command (including arcs), `line`, `polyline`, `polygon`, `rect` (with rounded corners), `circle`, `ellipse`, groups, nested transforms, inline styles, simple CSS class rules like those Illustrator exports, and `display="none"`. It skips `<text>`, `<image>`, and `<use>` and tells you when it does; convert text to outlines before importing.

## Settings

- **Thickness:** tube diameter as a multiple of the stroke width.
- **Facets:** the number of sides around each tube (default 32). Shading uses normals from the exact surface, so tubes look round even with fewer facets. The preview shows the triangle count as you adjust it.
- **Optimize Mesh:** simplifies the model (on by default). Turn it off to keep the dense mesh.
- **Ends:** the SVG's own line caps, or always round or always flat.
- **Intersections:** Crisp, Soft, or Round, with a slider to fine-tune the blend.
- **Filled Shapes:** include or ignore fills, and set the extrusion depth (in points) and edge rounding for shapes that have no outline.
- **Surface:** Solid Color, a flat color that ignores scene lighting, or Shaded, a matte finish that responds to lights. Either can be any color.
- **Scale:** From Points (the default) treats one artwork point as 1/72 inch (0.3528 mm). Fixed Size scales the longest side to a length you set in centimeters.
- **Frame:** center the model on the SVG canvas, which keeps a set of icons aligned, or on the artwork itself.

Each file contains a single mesh with smooth normals and one `UsdPreviewSurface` material. Models are Y-up and measured in centimeters (`metersPerUnit = 0.01`), with no lights or cameras, and they pass Apple's `usdchecker`.

## Building from Source

You need an Apple silicon Mac with macOS 14 or later, Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `app/project.yml` and isn't checked in.

```bash
cd app
xcodegen generate
open Tubeline.xcodeproj          # Run the Tubeline scheme; ⌘U runs the tests.
```

The project signs with the Tent Studios team. To build it yourself, choose your own team under Signing & Capabilities, or run the tests unsigned as described in [Contributing to Tubeline](CONTRIBUTING.md).

The geometry engine is the `TubelineCore` Swift package at the root of the repository. The app and the command-line tool both use it:

```bash
swift run -c release tubeline Samples -o /tmp/tubeline --png
swift run tubeline --help
```

The `Samples` folder holds test SVGs that cover the edge cases. Put your own icons in `Samples/User`, which Git ignores.

To make a notarized release, run `scripts/release.sh --publish`. It runs the tests, builds and signs the app with a Developer ID certificate, notarizes and staples the app and the DMG, notarizes the command-line tool, and creates the GitHub release. See [Releasing Tubeline](docs/release/RELEASING.md) for details.

## Repository Layout

```
Package.swift           TubelineCore engine and tubeline command-line tool
Sources/TubelineCore/   SVG parsing, dashes, meshing, USDZ writing, preview scene
Sources/tubeline/       Command-line tool
app/                    Mac app (project.yml, SwiftUI sources, unit tests)
Samples/                Test SVGs (Samples/User is yours and ignored by Git)
docs/                   Research, release, and testing notes
```

## Roadmap

GLB export for After Effects and other apps is next, and USDZ will stay the default. See the [roadmap](ROADMAP.md) for what's planned.

## Contributing

Bug reports and pull requests are welcome; see [Contributing to Tubeline](CONTRIBUTING.md). The most helpful bug report is an SVG that doesn't convert the way you expected.

## License

MIT License. Copyright © 2026 Tent Studios, LLC. Made by Jeff Alldridge.
