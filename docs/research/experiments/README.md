# Unmerged Mesh Experiments

These patches are research artifacts, not production changes. They apply on top of the validator optimization in `b4a7aeb`; use `git apply --check` before applying either patch. They have not passed the complete SVG corpus comparison. Do not ship them on the strength of one benchmark.

## Evidence

A temporary controlled comparison on one complex icon used alternating runs after app builds and corpus processing had finished:

| Variant | Median Parse-and-Mesh Time | Reduction from Control |
| --- | --- | --- |
| Committed fast-verdict control | 4.901 s | — |
| Table-driven tetrahedral extraction | 4.522 s | 7.75% |
| Scalar validation and earlier rejection | 4.404 s | 10.15% |

All twelve outputs passed strict validation and had the same 175,194 triangles, geometry/index hash, and normal hash. A differential test of the scalar validator also compared complete reports and fast verdicts on ten thousand deterministic malformed meshes without a mismatch. These results do not replace the full corpus test or establish a speedup for every icon. No variant reduces triangle count.

## Patches and Next Checks

[Scalar validation](scalar-validation.patch) replaces per-triangle three-element arrays and sets with scalar or SIMD operations. It also returns earlier for invalid facts that cannot be repaired by later triangles, such as an edge used by more than two faces. It preserves complete public diagnostic reports. This is the smaller next experiment.

[Table extraction](table-extraction.patch) uses sixteen tetrahedral sign cases and fixed cell storage instead of per-cell and per-tetrahedron map/filter arrays. It retains the crossing formula and normal evaluation. Review case orientation and shared-edge indexing carefully.

For either patch, run the core and app suites, then compare every SVG against the released baseline. Require the same strict validity, triangle counts, geometry/index hashes, normal hashes, and warning counts. Use alternating isolated runs for timing; concurrent full-corpus runs are output comparisons only. Apply and verify each patch separately before considering a combined version.

The local evidence files are `/tmp/tubeline-geometry-audit/temporary-matrix-results.json` and `/tmp/tubeline-geometry-audit/fast-validation-comparison.json`. They contain derived hashes and timings; private SVGs remain outside Git.
