# Tubeline — Backlog

## NEXT SESSION FIRST
- [x] Phase 3: QEM decimation + exact normals + speed pass (2026-10-22)
- [ ] Jeff: test exported icons in Motion (Phase 2) — the next real unknown

## Phase 2 — Motion validation (Jeff)
- [ ] Import samples into Motion: does 1 pt = 1/72 in give a sensible size?
- [ ] Does Solid Color (emissive) render flat in Motion? Does Shaded pick up lights?
- [ ] Performance with dozens of icons in one project
- [ ] Run Jeff's own icon sets (Samples/User) and log failures

## Geometry
- [ ] Manifold dual contouring: crossing saddles produce a few pinch edges shared by
      4 triangles (closed, not a hole; invisible) — ~5% of edges on an X crossing a circle. Fix = multiple vertices per cell
      (Schaefer et al. 2007) or post-split of non-manifold edges.
- [ ] Welded points + faceVarying indexed primvars:normals in USD
- [ ] Miter/bevel joins (currently always round)
- [ ] `<use>`/`<symbol>` support; warn on `<text>` (already reported)
- [ ] Optional crisp low-poly mode (analytic sweeps + Manifold)

## Polish / ship
- [ ] **Redraw app icon** — current AppIcon.icon uses SF Symbol graph.3d, which the
      SF Symbols license forbids in app icons (release blocker)
- [x] Icon Composer icon + icns-strip postBuild script wired up (2026-10-22)
- [ ] Settings window, keyboard shortcuts, a11y labels, swiftui-pro review
- [ ] Name research (Phase 5)
