# Tubeline — Session Memory

Rolling log of the last 10 sessions. Older entries move to `archive/`.

## Session — 2026-10-22 [Idea → working app → Tent Studios project]

**Worked on:** Built the whole tool in one session: SVG parser (paths, arcs,
transforms, CSS classes, dashes), SDF + dual contouring mesher with crisp
creases and fillets, fills (discs) and extrusions, USDZ writer, SwiftUI app with
SceneKit preview, CLI. Moved into the house layout (app/, sandbox, tests, docs).
Research on decimation saved to docs/research/.
Then Phase 3: QEM simplification against the exact SDF (6–14× fewer tris), parallel
meshing (3–7× faster), facets default 32, arm64-only, temp Icon Composer icon.
Published (Jeff's explicit request) as public MIT repo github.com/jeffalldridge/tubeline
with CI, contributing/security/conduct docs.
**State after:** 22 tests green; Motion import still untested.
**Next:** Jeff tests in Motion (Phase 2) + drops own icons in Samples/User; redraw icon
(SF Symbol license); manifold DC for crossing pinch edges.
