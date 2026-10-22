# Mesh Optimization Research: Lighter Geometry and Faster Meshing

*Prepared October 22, 2026, by a Claude research agent, based on `Sources/TubelineCore/FusedMesher.swift` and `Converter.swift` at commit 984e50a. Triangle counts and timings in the recommendations are estimates; measured results are at the end.*

## Starting Point

- The mesher sampled a uniform grid with spacing `2π × minRadius / facets`, with facets set to 40. A 24 pt heart came out at 45,000–56,000 triangles and a busy icon at about 165,000, taking 0.15–1 second to convert.
- Density was the same everywhere, so straight runs and flat faces were as finely divided as tight curves.
- The slowest code repeated work. Each grid edge crossing the surface was solved by up to four cells, every gradient took six distance evaluations, sampling ran on one thread across each primitive's whole bounding box, and the inner loops allocated memory.
- Crease normals were made by duplicating points, so the exported topology wasn't welded.

## Options Compared

| | Analytic tubes plus a Manifold union | Distance field, dual contouring, and quadric simplification (chosen) | Adaptive (octree) dual contouring |
| --- | --- | --- | --- |
| Intersections | Exact and crisp, but no true fillets | Crisp or filleted, as today | Same as today |
| Closed mesh | Yes; Manifold guarantees it | Yes, with link-condition checks | Needs the manifold variant |
| Triangles for a 24 pt heart | About 3,000–6,000 | About 4,000–10,000 | About 10,000–20,000 |
| Effort | High: sweeps, frames, joins, a C++ dependency | Low to medium | High |

Adaptive contouring is a poor fit because its cubic cells can't be much larger than the tube's radius, so straight runs coarsen only three to six times. Quadric simplification readily makes long, thin triangles along a tube's axis, which is exactly where the extra triangles were.

## Recommendations, in Priority Order

1. **Simplify after contouring with quadric edge collapse** (Garland and Heckbert 1997), on the welded mesh and before splitting creases. Bound the error in model units by the sag of one facet, `ε = r × (1 − cos(π / facets))`. Reject collapses that flip a face or break the link condition, which keeps the mesh manifold. Afterward, recompute every normal from the exact distance-field gradient; exact normals let a coarse tube shade as perfectly round, so simplification can be aggressive. Expected result: five to twelve times fewer triangles.
   - Library option: meshoptimizer (MIT; C++ with a C header), using `meshopt_simplify` with `meshopt_SimplifyErrorAbsolute`.
   - Swift option: about four hundred lines covering quadrics, a min-heap with lazy invalidation, and a 3 × 3 solve with endpoint and midpoint fallbacks.
2. **Speed it up.** Cache edge crossings and normals per grid edge, compute gradients analytically for capsules, spheres, and cylinders, run sampling in parallel with `DispatchQueue.concurrentPerform`, sample only near the surface, and remove allocations from inner loops. With exact normals and simplification, the grid can also be coarser.
3. **Clean up the USD.** Use welded points with indexed face-varying `primvars:normals`, which keeps hard edges without breaking the closed topology. Author either `normals` or `primvars:normals`, not both. Keep `subdivisionScheme = "none"`, `extent`, `metersPerUnit`, consistent winding, and binary USD.
4. **Later, if needed,** add a crisp low-poly mode with analytic sweeps and Manifold's `BatchBoolean` (Apache 2.0).
5. **Skip adaptive contouring.**

## What We Built

Tubeline 0.1.0 implemented recommendations 1 and 2 in Swift, without libraries. Each collapse is also checked against the exact distance field: the new vertex and points across every changed triangle must stay within one facet's sag. Measured results with facets at 32:

| Sample | Before | After |
| --- | --- | --- |
| Heart | 43,592 triangles, 0.22 s | 6,826 triangles, 0.15 s |
| Camera | 56,228 triangles, 0.24 s | 8,696 triangles, 0.17 s |
| Illustrator-style mail icon | 94,284 triangles, 0.36 s | 6,702 triangles, 0.21 s |
| Edge cases | 165,284 triangles, 0.88 s | 31,314 triangles, 0.45 s |

The biggest speedup came from flattening the distance lookup into plain arrays. Nested Swift arrays and class references had caused reference-counting contention across threads. Recommendation 3 and the manifold fix (GitHub issue #4) are still open.

## Licenses

meshoptimizer: MIT. probabilistic-quadrics: MIT. Manifold: Apache 2.0. OpenMesh: BSD 3-Clause. CGAL: GPL or commercial (avoid).

## Sources

- meshoptimizer: https://github.com/zeux/meshoptimizer
- Manifold: https://github.com/elalish/manifold
- Garland and Heckbert 1997: https://www.cs.princeton.edu/courses/archive/fall06/cos526/papers/garland97.pdf
- Garland and Heckbert 1998 (attributes): https://mgarland.org/files/papers/quadric2.pdf
- Ju et al. 2002, *Dual Contouring of Hermite Data*: https://people.engr.tamu.edu/schaefer/research/dualcontour.pdf
- Schaefer, Ju, and Warren 2007, *Manifold Dual Contouring*: https://people.engr.tamu.edu/schaefer/research/dualsimp_tvcg.pdf
- Trettner and Kobbelt 2020, probabilistic quadrics: https://diglib.eg.org/handle/10.1111/cgf13933
- NVIDIA's USD mesh normal requirements: https://docs.omniverse.nvidia.com/kit/docs/asset-requirements/latest/capabilities/geometry/requirements/usdgeom-mesh-normals-exist.html
