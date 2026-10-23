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

## Validation After the Project Review

The October 22 improvement pass added topology validation before export. The earlier watertightness test accepted any even edge incidence and skipped collapsed edges, so its passing result did not establish a manifold surface. The replacement checks edge incidence and winding, duplicate and degenerate faces, finite coordinates and indices, and connected vertex neighborhoods after welding split-normal vertices. It does not prove the absence of every geometric self-intersection.

Meshing now runs in normalized tube-radius units, with physical sizing applied afterward. This removes the scale-sensitive failures reproduced in the original crossing fixture. If simplification damages an otherwise valid dual contour, the dense contour is retained. Ambiguous contours retry extraction from the same sampled whole-icon field using consistent tetrahedra. This avoids stitching separate strokes, but it can require more triangles and approximates sharp creases with the sampled field.

A local run converted all six original samples and the private collection of 156 icons with the default detail of 32, optimization enabled, and Output Scale 1×. All 162 meshes passed validation. These are parse-and-mesh timings from one run on the development Mac, not a controlled performance comparison with version 0.1.0.

| Measurement | Median | Ninety-Fifth Percentile | Maximum |
| --- | --- | --- | --- |
| All meshes, triangles | 48,844 | 183,486 | 231,620 |
| All meshes, time | 0.93 s | 6.63 s | 13.22 s |
| Denser path, triangles | 146,382 | 222,346 | 231,620 |
| Denser path, time | 5.62 s | 7.39 s | 13.22 s |

Forty-two icons used the denser path. The app and CLI warn when this happens; the app keeps the triangle count visible above the preview. Reducing this cost while preserving manifold topology remains the priority for issue #4. The private artwork and rendered validation artifacts remain outside Git.

The app-hosted suite passed forty-nine tests, including eight app-state regressions; `swift test` passed the forty-one engine tests separately. All six tracked samples exported, rendered to PNG, and passed `usdchecker --arkit`. Native app checks covered per-field inheritance, repeated exports without replacement, Finder reveal, visible camera and output controls, and the accessible preview. Output Scale 100× changed the test heart's width from approximately 0.706 cm to 70.59 cm while retaining 8,038 triangles. Six independent identical CLI conversions also produced identical USDZ hashes.

## First Post-Release Validation Optimization

The retry path needs a validity verdict, while the public validation method provides a complete diagnostic report. Once edge, face, index, or finite-value checks have established failure, retry decisions can skip construction and traversal of per-vertex adjacency dictionaries. Otherwise, vertex neighborhoods are still checked, including the case of two closed tetrahedra touching at only one vertex. The public complete report is unchanged.

Three alternating baseline/candidate runs on one complex fallback icon produced these parse-and-mesh timings:

| Run | Release Baseline | Fast Verdict |
| --- | --- | --- |
| 1 | 5.706 s | 5.127 s |
| 2 | 5.707 s | 5.246 s |
| 3 | 5.764 s | 5.249 s |
| Median | 5.707 s | 5.246 s |

The median decreased by about 8.1 percent for this case. Each output had 175,194 triangles and identical geometry/index and normal SHA-256 digests. This does not establish an equivalent speedup across the corpus.

A separate complete comparison covered all 162 SVGs. Triangle counts, strict validation results, geometry/index hashes, normal hashes, and warning counts matched the release baseline exactly. The broad runs overlapped other work and are not controlled timing evidence. The standalone suite passed forty-four tests, and the app-hosted suite passed sixty-one, including the queued-export fixes developed alongside this optimization.

Larger experiments—deferred normals, packed edge keys, case-table extraction, scalar validation, and earlier rejection of irreparable edge failures—remain temporary. Measure and validate them separately before changing the production extractor.

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
