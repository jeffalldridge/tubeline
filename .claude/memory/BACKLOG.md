# Tubeline Backlog

The public roadmap is ROADMAP.md plus GitHub issues labeled `roadmap` (issues #2–#7). Keep them in sync with this list.

## Next Session First

- [ ] Jeff tests exported icons in Motion (issue #3). This is the biggest open question.
- [ ] GLB export for After Effects, with USDZ staying the default (issue #2). This is the 0.2 headline.

## Testing in Motion Graphics Apps (Issue #3)

- [ ] Does point-based sizing (1 pt = 1/72 inch) give a sensible size in Motion?
- [ ] Does Solid Color render flat in Motion, and does Shaded respond to lights?
- [ ] How does performance hold up with dozens of icons in one project?
- [ ] Spot-check other apps that import USDZ, such as Reality Composer Pro, Keynote, and Blender.
- [ ] Run Jeff's own icon sets from `Samples/User` and log any failures.

## Geometry

- [ ] Manifold dual contouring (issue #4). Where strokes cross, a few edges are shared by four triangles. The mesh is still closed and the effect is invisible, but on an X crossing a circle it affects about 5 percent of edges. Fix it with several vertices per cell (Schaefer, Ju, and Warren 2007) or by splitting non-manifold edges after contouring.
- [ ] Miter and bevel joins (issue #5); corners are always round today.
- [ ] Support `<use>` and `<symbol>` (issue #6).
- [ ] An optional crisp low-poly mode with analytic sweeps (issue #7).
- [ ] Welded points with face-varying normals in USD.

## Polish and Shipping

- [x] Original icon glyph rendered by Tubeline replaced the SF Symbol (October 22, 2026).
- [x] Notarized 0.1.0 release with DMG, CLI, and checksums (October 22, 2026).
- [ ] Add release signing secrets to the repository so tags can release from CI.
- [ ] Merge or close Dependabot's `actions/checkout` update (pull request #1).
- [ ] Settings window, keyboard shortcuts, accessibility labels, and a swiftui-pro review.
- [ ] Trademark check for the name.
