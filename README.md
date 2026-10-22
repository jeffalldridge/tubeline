# Tubeline

[![CI](https://github.com/jeffalldridge/tubeline/actions/workflows/ci.yml/badge.svg)](https://github.com/jeffalldridge/tubeline/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%C2%B7%20Apple%20silicon-lightgrey)

Tubeline is a free Mac app that turns stroked SVG icons into 3D tube models. It saves them as USDZ files for Apple Motion and other motion graphics apps that import USDZ.

Drop SVG files or folders onto the window, adjust the batch settings, and preview an icon. Each stroke becomes a round tube as thick as the stroke. Choose where to save the models in the output bar, then click Export. Existing files are kept; exports receive numbered names when needed.

Batch settings apply to every icon. Choose Selected Icon to customize individual values while the rest continue to follow the batch. Show Form lights the preview to help inspect its geometry without changing the exported material. Fit, Front, and Reset View control the camera.

Front uses an orthographic view so the model reads as the flat SVG. Fit keeps the current angle, and Reset View restores the three-quarter perspective. Their shortcuts are Command-0, Command-1, and Command-2, respectively. Exported geometry lies in the XY plane, with its front toward +Z and no baked rotation. Preview cameras are never exported; the receiving app controls its own projection.

## Download

Download the latest build from [Releases](https://github.com/jeffalldridge/tubeline/releases/latest), open the DMG, and drag Tubeline to your Applications folder. You need an Apple silicon Mac running macOS 14 or later. Each release also includes a `tubeline` command-line tool. Both are signed by Tent Studios and notarized by Apple.

## How It Works

Tubeline models the icon with a single signed distance field built from its strokes, caps, joints, and fills, then extracts a closed surface with dual contouring. Overlapping volumes fuse; disconnected marks remain separate closed components in the same mesh. Before export, the engine checks for boundary edges, non-manifold edges and vertices, collapsed or duplicate triangles, and inconsistent winding. Conversion stops with an error if these checks fail.

It simplifies the surface by collapsing edges and sampling the distance to the exact shape across the changed triangles. Long straight runs and flat faces need fewer triangles, while curves and seams retain more detail. The preview reports the resulting triangle count and dimensions.

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

Clipping, masks, filters, nested SVG viewports, and non-scaling strokes are unsupported and produce warnings. Nonuniform scale and shear approximate stroke thickness and also produce warnings. Check Conversion Warnings before using affected artwork. Re-add an SVG or click Refresh SVG after saving changes in your drawing app.

## Settings

- **Thickness:** tube diameter as a multiple of the stroke width.
- **Detail:** the target curve detail (default 32), under Advanced. This controls meshing density, rather than an exact count of polygon sides. Higher values make heavier meshes.
- **Optimize Mesh:** simplifies the model (on by default). Turn it off to keep the dense mesh.
- **Ends:** the SVG's own line caps, or always round or always flat.
- **Intersections:** Crisp, Soft, or Round, with a slider to fine-tune the blend.
- **Filled Shapes:** include or ignore fills, and set the extrusion depth (in points) and edge rounding for shapes that have no outline.
- **Surface:** Solid Color, a flat color that ignores scene lighting, or Shaded, a matte finish that responds to lights. Either can be any color.
- **Scale:** Artwork Points (the default) treats artwork coordinates as design points, with one point equal to 1/72 inch (0.3528 mm). SVG Physical Size honors declared SVG dimensions and the standard ninety-six CSS pixels per inch. Fit Size scales the frame's longest side to a length in centimeters.
- **Frame:** center the model on the SVG canvas, which keeps a set of icons aligned, or on the artwork itself.
- **Output Scale:** a whole-number multiplier applied after sizing, with 1×, 10×, and 100× presets. This makes small icons practical in 3D apps that use larger working dimensions. It can follow the batch or be customized for one icon.

Each file contains a single mesh with smooth normals and one `UsdPreviewSurface` material. Models are Y-up and measured in centimeters (`metersPerUnit = 0.01`), with no lights or cameras, and they pass Apple's `usdchecker`.

App Settings lets you save the current batch settings as defaults for future sessions. Automatic export is off for new installations; you can enable it there after choosing your settings and destination. Files added or refreshed during an automatic export wait for the current batch. Cancel Export clears that queue, keeps completed files, and stops remaining work. A conversion already meshing finishes its current stage before cancellation takes effect.

### Sizing in Motion

SVG user coordinates, CSS pixels, and print points are distinct. Physical SVG sizing follows `72 pt = 96 px = 1 in`, including the viewport-to-viewBox scale. Artwork Points preserves Tubeline's design-point convention for icon work. For example, a 48 pt canvas side becomes approximately 1.693 cm at the default conversion.

For a larger working size, choose Output Scale 100×. A 24 pt canvas side then becomes approximately 84.67 cm, and a 48 pt canvas side becomes approximately 169.33 cm. The preview reports the final geometry dimensions, which may be smaller than the canvas frame. Output Scale changes the dimensions without increasing the triangle count.

Motion's Automatic Unit Size normalizes imported objects to approximately 500 project pixels. Original uses a one-to-one units-to-pixels translation, and Custom lets you choose the inherent size. Physical USDZ dimensions alone do not specify a screen size in Motion. See [Apple's sizing controls](https://support.apple.com/guide/motion/modify-a-3d-objects-inherent-size-orientation-motn0e41f019/mac) and the [SVG coordinate specification](https://www.w3.org/TR/SVG2/coords.html).

## Building from Source

You need an Apple silicon Mac with macOS 14 or later, Xcode 26 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `app/project.yml` and isn't checked in.

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

The CLI also keeps existing files and disambiguates duplicate names. Pass `--replace` to replace existing outputs explicitly. Use `--physical` for SVG physical dimensions, `--pt` for an artwork-point conversion, or `--size` for a fixed frame size. Add `--scale 100` to multiply the final dimensions by one hundred.

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
