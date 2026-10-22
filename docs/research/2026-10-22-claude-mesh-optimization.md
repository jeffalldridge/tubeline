# Mesh optimization research — lighter geometry, faster meshing

Source: Claude research agent, 2026-10-22, grounded in `Sources/TubelineCore/FusedMesher.swift`
and `Converter.swift` as of commit 984e50a. Triangle and speed figures are estimates.

## Starting point

- Uniform grid at `voxel = 2π·minRadius/facets` (facets = 40): a 24 pt heart is ~45–56k
  triangles, a busy icon ~165k, converted in 0.15–1 s.
- Density is the same everywhere — straight tube runs and flat slab faces are tessellated as
  finely as tight curves.
- Hot-path waste: each crossing grid edge is root-found and gradient-sampled by up to 4 cells
  (≈4× redundant), gradients use 6 SDF calls, sampling is single-threaded over whole
  primitive bounding boxes, and there are heap allocations per cell/quad.
- Crease normals are done by duplicating points, so the exported topology is not welded.

## Options compared

| | Analytic tubes + Manifold union | **SDF + DC + QEM (chosen)** | Adaptive/octree DC |
|---|---|---|---|
| Intersections | Exact crisp; no true fillets | Crisp or filleted, unchanged | Same as now |
| Watertight | Yes (Manifold guarantees) | Yes, with link-condition checks | Needs Manifold-DC variant |
| Tris (24 pt heart) | ~3–6k | ~4–10k | ~10–20k |
| Effort | High (sweeps, frames, joins, C++ dep) | Low–medium | High |

Adaptive DC is a poor fit: cubic cells can't be much larger than the tube radius, so straight
runs only coarsen 3–6×. QEM happily produces long thin triangles along the tube axis — exactly
the redundancy we have.

## Recommended plan (priority order)

1. **QEM edge-collapse decimation after DC** (Garland–Heckbert 1997) on the welded mesh,
   before crease splitting. Error bound in world units from the facet setting:
   `ε = r·(1 − cos(π/facets))` (the sagitta of one facet). Reject collapses that flip a face
   normal or fail the link condition (keeps the mesh manifold). Then recompute every vertex
   normal from the exact SDF gradient — exact normals let a coarse tube shade perfectly round,
   so decimation can be aggressive. Expected 5–12× fewer triangles.
   - Library route: meshoptimizer (MIT, C++ with C header; `meshopt_simplify` with
     `meshopt_SimplifyErrorAbsolute`). Pure-Swift route: ~400 lines (quadrics, min-heap with
     lazy invalidation, 3×3 solve with endpoint/midpoint fallback).
2. **Speed pass:** cache edge crossings/normals per grid edge, analytic gradients for capsule /
   sphere / cylinder, `DispatchQueue.concurrentPerform` over slabs, narrow-band (brick) sampling,
   no per-cell allocations. With exact normals + QEM the grid can also sample coarser.
3. **USD cleanup:** welded points with indexed `faceVarying` `primvars:normals` (hard edges
   without breaking watertightness); author `normals` *or* `primvars:normals`, not both; keep
   `subdivisionScheme = "none"`, `extent`, `metersPerUnit`, consistent winding; keep usdc.
4. Optional later: a "crisp low-poly" mode with analytic sweeps + Manifold `BatchBoolean`
   (Apache-2.0) if step 1 isn't light enough.
5. Skip adaptive DC.

## Licenses

meshoptimizer — MIT · probabilistic-quadrics — MIT · Manifold — Apache-2.0 ·
OpenMesh — BSD-3 · CGAL — GPL/commercial (avoid).

## Sources

- meshoptimizer: https://github.com/zeux/meshoptimizer
- Manifold: https://github.com/elalish/manifold
- Garland & Heckbert 1997: https://www.cs.princeton.edu/courses/archive/fall06/cos526/papers/garland97.pdf
- Garland & Heckbert 1998 (attributes): https://mgarland.org/files/papers/quadric2.pdf
- Ju et al. 2002, Dual Contouring: https://people.engr.tamu.edu/schaefer/research/dualcontour.pdf
- Schaefer, Ju & Warren 2007, Manifold DC: https://people.engr.tamu.edu/schaefer/research/dualsimp_tvcg.pdf
- Trettner & Kobbelt 2020, probabilistic quadrics: https://diglib.eg.org/handle/10.1111/cgf13933
- NVIDIA USD mesh normals requirements: https://docs.omniverse.nvidia.com/kit/docs/asset-requirements/latest/capabilities/geometry/requirements/usdgeom-mesh-normals-exist.html
