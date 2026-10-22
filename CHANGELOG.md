# Changelog

All notable changes to Tubeline. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0] - 2026-10-22

First public release.

### Added
- **SVG → 3D tubes.** Every stroke becomes a round tube as thick as the stroke; the whole
  icon is one fused, watertight solid (signed distance field + dual contouring), so
  crossings are clean.
- **Intersections:** Crisp, Soft or Round, with a blend slider.
- **Stroke details:** caps from the SVG (butt, round, square) or forced round/flat;
  dashes and dotted lines; transforms, arcs, CSS classes (Illustrator exports).
- **Fills:** outlined fills become solid discs; fill-only artwork such as outlined text
  is extruded (depth in points, edge rounding).
- **Light, fast meshes:** quadric simplification checked against the exact surface keeps
  a typical 24 pt icon around 5–10k triangles; normals come from the exact surface so
  tubes shade round. Conversion takes a fraction of a second on Apple silicon.
- **Looks and size:** Solid Color (self-lit) or Shaded material in any color; facets
  control with live triangle count; point-based sizing (1 pt = 1/72 in) or fixed size.
- **Mac app:** drag-and-drop batch export, live orbitable 3D preview, sandboxed
  "save next to original" with remembered folder grants.
- **Command line:** `tubeline` for batch conversion, with `--png` preview renders.
- Output: single-mesh, single-material USDZ (binary USD, centimeters, Y-up) that
  passes Apple's `usdchecker --arkit`.

[Unreleased]: https://github.com/jeffalldridge/tubeline/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jeffalldridge/tubeline/releases/tag/v0.1.0
