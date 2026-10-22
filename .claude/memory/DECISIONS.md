# Tubeline — Decisions

Architectural and product decisions with rationale. Newest first.

## 2026-10-22 — Free and open source (Jeff)
MIT license, public repo, Tent Studios as publisher. Overrides the house
default of proprietary/paid: Tubeline is a community freebie for motion designers.

## 2026-10-22 — Decimate with QEM, skip adaptive DC (research)
Uniform DC is 5–12× denser than needed on straight runs. QEM edge collapse on
the welded DC mesh, bounded by one facet's sagitta, plus exact SDF normals is
the biggest win for the least code. Adaptive DC can't coarsen along thin tubes.
Analytic sweeps + Manifold kept as a possible "low-poly crisp" mode later.
See docs/research/2026-10-22-claude-mesh-optimization.md.

## 2026-10-22 — Sizing is point-based (Jeff)
Artwork is drawn in points: 1 SVG unit = 1 pt (px treated as pt, like design
tools), 1 pt = 1/72 in by default. USD output in centimeters
(metersPerUnit 0.01), matching Apple's tools. Extrusion depth is in points too.

## 2026-10-22 — Solid Color is the default surface (Jeff)
Emissive-only UsdPreviewSurface so icons read as flat color whatever Motion's
lighting; Shaded (matte diffuse) is the alternative.

## 2026-10-22 — One SDF solid instead of swept tubes
Swept tubes overlap and leave interior faces; the SDF union gives clean crisp
or filleted intersections, fills and extrusions in one model. Dual contouring
(QEF vertices) keeps crisp seams and flat-cap rims sharp; crease vertices get
split normals.

## 2026-10-22 — Only explicit fills count
SVG's implicit black fill would turn line icons into blobs, so only declared
fills are solid. Outlined fills become discs as thick as the outline (no torus);
fill-only shapes extrude.
