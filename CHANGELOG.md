# Changelog

All notable changes to Tubeline. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0] - 2026-10-22

First public release.

### Changed
- Meshes are 6–14× lighter at the same visual quality: quadric edge-collapse
  simplification, checked against the exact surface, collapses straight runs and
  flat faces (24 pt heart: 43,592 → ~6,800 triangles). Normals come from the exact
  surface, so lighter tubes still shade round; creases are detected geometrically.
- Conversion is 3–7× faster: parallel sampling, contouring and tiled
  simplification on all cores, flattened distance lookups.
- Facets now means the real number of sides around a tube; default 32.
- Triangles and vertices are written in GPU-friendly order (Morton curve, first-use).
- Apple silicon only (arm64).

### Added
- "Optimize mesh" toggle (on by default) and `--no-optimize` CLI flag.
- App icon: an original loop-the-loop tube glyph rendered by Tubeline itself
  (`scripts/render-icon.sh`), composed in Icon Composer.
- Notarized releases: `scripts/release.sh` builds a signed, notarized DMG and
  command-line tool; a tag-triggered workflow can do the same in CI.
- SVG → 3D tube conversion: strokes become round tubes; one fused, watertight
  solid per icon via a signed distance field and dual contouring.
- Crisp, Soft or Round intersections; caps from SVG or forced round/flat;
  dashes and dotted lines; outlined fills become discs; fill-only artwork is
  extruded (depth in points, edge rounding).
- Facets control with live triangle count; Solid Color (self-lit) or Shaded
  material; point-based sizing (1 pt = 1/72 in) or fixed size.
- SwiftUI app with drag-and-drop batch export, live orbitable 3D preview, and
  sandboxed "save next to original" with remembered folder grants.
- `tubeline` command-line tool with `--png` previews.
- Unit tests for parsing, dashing, meshing (watertightness), sizing and USDZ packaging.

[Unreleased]: https://github.com/jeffalldridge/tubeline/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jeffalldridge/tubeline/releases/tag/v0.1.0
