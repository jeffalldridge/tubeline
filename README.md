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

Requires macOS 14+ and Xcode 16+.

Open `Tubeline.xcodeproj` and run the **Tubeline** scheme. The geometry engine lives in the `TubelineCore` Swift package in this repo and is shared by the app and a command-line tool.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding or removing files, run `xcodegen generate`.

### Command line

```bash
swift run -c release tubeline ~/Icons -o ~/Icons/3D --png
```

Run `swift run tubeline --help` for every option. `--png` also writes a preview render.

### Releasing a notarized build

1. Create `Config/Local.xcconfig` with `DEVELOPMENT_TEAM = <your team ID>` (it's gitignored).
2. Store notary credentials once: `xcrun notarytool store-credentials tubeline-notary --apple-id <you> --team-id <team>`.
3. Run `Scripts/release.sh`. It archives, signs with Developer ID, notarizes, staples, and writes `dist/Tubeline-<version>.zip`.

## Layout

```
Sources/TubelineCore/   SVG parsing, dashing, distance-field meshing, USDZ writing, preview scene
Sources/TubelineApp/    SwiftUI app (drop zone, settings, SceneKit preview)
Sources/tubeline/       Command-line tool
App/                    Info.plist and asset catalog for the Xcode app target
Config/                 Signing settings
Scripts/release.sh      Archive, notarize, staple, zip
```

## License

MIT
