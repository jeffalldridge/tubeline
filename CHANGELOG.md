# Changelog

All notable changes to Tubeline are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- Fill-only artwork that omits SVG’s default black fill extrudes without an invented outline. Zero-width strokes no longer suppress a fill’s extrusion depth. Explicitly stroked line icons retain their existing fill handling.
- Invalid numeric edits show field-specific guidance without changing applied settings. Saved defaults reject invalid values, and untouched fields preserve calibration precision.
- Preview accessibility reports unavailable content accurately and identifies same-name icons by source folder and path.
- Concurrent CLI exports publish without replacing another process's file. A late preview-image collision preserves the existing PNG and reports partial success.
- Removing a completed or failed row no longer cancels the remaining batch.
- Automatic export queues SVGs added or refreshed during an active batch, uses current settings when each request starts, and clears queued requests on Cancel.

### Changed

- View menu commands provide camera controls and discrete orbit actions. Export cancellation supports Escape and Command-period, and icon removal is available from the menu and list keyboard handling.
- The window supports a smaller minimum size, long destination names have bounded width, and single-icon exports avoid a redundant selected-item button. Camera inertia respects Reduce Motion.
- Detail and Optimize Mesh appear first in the main settings panel, with Low, Balanced, and High detail presets. Intersection blending and fill depth are exposed in their regular sections; only unit calibration remains collapsed.
- App Settings directly edits saved defaults for mesh detail, optimization, thickness, and output scale without changing an active batch.

- Meshing retries skip additional diagnostics after a mesh is already known to be invalid. Complete validation reports and acceptance rules are unchanged.
- Release preflight checks the built app's copyright, category, encryption declaration, and privacy-manifest syntax.
- Orientation tests now detect vertical mirroring in both the generated mesh and reloaded USDZ.

## [0.2.0] - 2026-10-22

### Added

- Batch settings with per-field overrides for selected icons, plus saved app defaults.
- A persistent output bar with visible export actions, destination selection, progress, cancellation, and retry for failed items.
- SVG Physical Size in the app and `--physical` in the CLI, resolving CSS pixels separately from print points.
- Integer Output Scale with 1×, 10×, and 100× presets in the app and `--scale` in the CLI for larger working dimensions.
- Closed-mesh validation for edge incidence, winding, vertex neighborhoods, degenerate triangles, and duplicate faces.
- Preview camera controls and framing that accounts for narrow viewports.
- Warnings for unsupported SVG appearance features and approximated stroke transforms.
- Regression tests for export state, filename collisions, settings inheritance, cancellation, path fidelity, topology, units, and material color.

### Fixed

- Camera commands reconnect the displayed camera after orbiting. Fit preserves the viewing angle; Front and Reset View restore explicit orientations.
- Batch exports preserve existing outputs and assign distinct names to same-name inputs. The CLI supports explicit replacement with `--replace`.
- Exports retain the settings snapshot that produced them, so intervening edits leave the result marked outdated.
- Failed or loading previews no longer display a previously selected icon.
- Flat caps retain their endpoint when straight paths contain short segments, and collinear curves preserve backtracking.
- Meshing uses a normalized internal scale to avoid topology changes caused by physical output sizing.
- Exported material colors convert sRGB picker values to linear shader values.
- Replaced three sample icons that reused path data from the Lucide icon set with original drawings.

### Changed

- Adding files previews them before export by default. Automatic export remains available in App Settings.
- Re-adding an existing SVG refreshes it; overlapping file and folder inputs are deduplicated.
- Preview and export conversions share a bounded worker, and unpublished results are staged before final output.
- The app calls the approximate meshing control Detail and places it with other advanced settings.
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

[Unreleased]: https://github.com/jeffalldridge/tubeline/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/jeffalldridge/tubeline/releases/tag/v0.2.0
[0.1.0]: https://github.com/jeffalldridge/tubeline/releases/tag/v0.1.0
