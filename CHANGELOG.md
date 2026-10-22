# Changelog

All notable changes to Tubeline are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- Replaced three sample icons that reused path data from the Lucide icon set with original drawings.

### Changed

- The command-line tool now stops with a clear message for unknown options, misspelled choices, and out-of-range numbers instead of silently ignoring them, and it has a `--version` option.
- Rewrote the documentation in American English following the *Chicago Manual of Style*.

## [0.1.0] - 2026-10-22

The first public release.

### Added

- Converts stroked SVG icons into 3D tubes as thick as their strokes. Each icon becomes a single closed solid, so lines that cross or overlap fuse cleanly.
- Crisp, Soft, and Round intersections, with a slider to adjust the blend.
- Butt, round, and square caps from the SVG, or ends that are always round or always flat; dashed and dotted lines; transforms, arcs, and the CSS class rules that Illustrator exports.
- Filled shapes with an outline become solid discs. Filled shapes without one, such as outlined text, are extruded to a depth you choose, with optional rounded edges.
- Lightweight meshes: a typical 24 pt icon comes out at 5,000–10,000 triangles, and shading uses normals from the exact surface so tubes look round. Converting an icon takes a fraction of a second on Apple silicon.
- Solid Color or Shaded materials in any color, a facets setting with a live triangle count, and sizing based on artwork points (one point equals 1/72 inch) or a fixed size.
- A Mac app with drag-and-drop batch export, a 3D preview you can rotate, and sandboxed saving next to the original files with folder permissions that are remembered.
- The `tubeline` command-line tool for batch conversion, with optional PNG previews.
- Exported files contain one mesh and one material in binary USD, measured in centimeters with Y up, and pass Apple's `usdchecker --arkit`.

[Unreleased]: https://github.com/jeffalldridge/tubeline/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jeffalldridge/tubeline/releases/tag/v0.1.0
