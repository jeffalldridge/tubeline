# Changelog

All notable changes to Tubeline. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
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
