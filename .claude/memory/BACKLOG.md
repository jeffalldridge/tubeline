# Tubeline Backlog

The public roadmap is ROADMAP.md plus GitHub issues labeled `roadmap` (issues #2–#7). Keep them in sync with this list.

## Next Session First

- [x] Jeff confirms earlier USDZ output works well in Motion.
- [ ] Verify 0.2.0 in Motion and Cinema 4D, including Front orientation and integer scale.
- [ ] GLB export for After Effects, with USDZ staying the default (issue #2). Planned after the 0.2 workflow release.

## Testing in Motion Graphics Apps (Issue #3)

- [ ] Does point-based sizing (1 pt = 1/72 inch) give a sensible size in Motion?
- [ ] Does Solid Color render flat in Motion, and does Shaded respond to lights?
- [ ] How does performance hold up with dozens of icons in one project?
- [ ] Spot-check other apps that import USDZ, such as Reality Composer Pro, Keynote, and Blender.
- [x] Ran Jeff's first icon set (`Samples/User/SVG Icons Outlines`, 156 icons): no failures (October 22, 2026).

## Geometry

- [ ] Reduce manifold fallback cost (issue #4). Strict validation now rejects invalid dual contours and uses a validated tetrahedral fallback. Forty-two of 162 corpus icons use a denser path; median 146,382 triangles and 5.619 s in this group. Optimize extraction and simplification without weakening validation.
- [ ] Miter and bevel joins (issue #5); corners are always round today.
- [ ] Support `<use>` and `<symbol>` (issue #6).
- [ ] An optional crisp low-poly mode with analytic sweeps (issue #7).
- [ ] Welded points with face-varying normals in USD.
- [ ] Thin strokes are heavy: 1 pt strokes on a 48 × 48 canvas average about 44,000 triangles and 0.7 s per icon, because triangle count grows with line length divided by tube thickness. Consider a lower facet count for thin tubes, or a coarser simplification bound when tubes are small on screen.

## Polish and Shipping

- [x] Original icon glyph rendered by Tubeline replaced the SF Symbol (October 22, 2026).
- [x] Notarized 0.1.0 and 0.2.0 releases with DMG, CLI, and checksums (October 22, 2026).
- [x] GitHub compiled and tested the exact 0.2.0 release commit (`0fba569`), run `39860251368`.
- [x] Post-release batch queue fixes and validator optimization on `codex/mesh-optimization`; sixty-one app tests, forty-four core tests, and all 162 corpus outputs unchanged.
- [ ] Add release signing secrets to the repository so tags can release from CI.
- [ ] Merge or close Dependabot's `actions/checkout` update (pull request #1).
- [x] Settings window, camera keyboard shortcuts, accessibility labels, and a SwiftUI review.
- [ ] Full VoiceOver and localization acceptance.
- [ ] Trademark check for the name.
