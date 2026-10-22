# After the 0.2.0 Release

## Shareable Build

[Download Tubeline 0.2.0](https://github.com/jeffalldridge/tubeline/releases/download/v0.2.0/Tubeline-0.2.0.dmg). Open the DMG and drag Tubeline to Applications. Requires Apple silicon and macOS 14 or later.

The release tag `v0.2.0` points to `0fba5693dbb8a344e4b53224b7a53be262e8a060`. [GitHub CI run 39860251368](https://github.com/jeffalldridge/tubeline/actions/runs/39860251368) passed on that exact commit: engine and CLI compilation, engine tests, six original sample conversions with `usdchecker --arkit`, and app build/tests.

The release script ran fifty-six app tests successfully. App and DMG passed Developer ID signature checks, notarization, stapling, and Gatekeeper assessment. The CLI was signed, smoke-tested, and notarized. Shipped app metadata includes the copyright, graphics-design category, encryption declaration, and privacy reasons for UserDefaults and user-selected file timestamps. The release Mac uses the existing `syntaxlook-notary` profile through `TUBELINE_NOTARY_PROFILE`.

Published SHA-256 digests:

```text
ca0ec785ded24c9b1d1191820bd50fcbb829b18c6dde5b4e1108a0b0d2eb9b1c  Tubeline-0.2.0.dmg
3ddbd9a2ed5da008a37d4a81533d1e84eca1eec08b465f03e49021a21357675a  tubeline-cli-0.2.0.zip
```

The signed Release app launched, previewed an original heart SVG, exported it, and responded to Front. The shipped CLI converted all six original samples, and each output passed `usdchecker --arkit`.

## What to Demonstrate

1. Add SVGs or drop a folder. Adding previews before export by default; an existing saved automatic-export preference remains respected.
2. Keep Batch selected for shared settings. Choose Selected Icon to override individual values while other values continue inheriting the batch settings.
3. Watch the large triangle count above the preview. Show Form adds preview lighting without changing the exported material.
4. Use Front for an orthographic view, Fit to reframe without changing the angle, and Reset View for the initial perspective angle. Shortcuts are Command-1, Command-0, and Command-2.
5. Choose an integer Output Scale. A 24 pt canvas is about 0.85 cm at 1×; 10× gives about 8.5 cm before differences between canvas and visible artwork bounds. Scaling does not increase the triangle count.
6. Choose the destination in the bottom bar and export. Existing outputs are kept; repeat exports get unique filenames. Show in Finder reveals the result.

The exported artwork lies in XY, faces +Z, and uses Y up at zero rotation. It contains no camera or baked rotation. Projection in Motion or another receiving app depends on that app's camera. Jeff confirmed that the earlier USDZ output works well in Motion; the new release has not been independently accepted in Motion or Cinema 4D.

## Continue Development

Work after the tag is on `codex/mesh-optimization`. Do not alter or move the published tag. Priorities:

1. Reduce fallback extraction and validation cost while preserving the whole-icon signed distance field and every topology acceptance rule.
2. Strengthen the orientation regression test to detect vertical mirroring through the asymmetric arm location, including after USDZ reload.
3. Rerun the complete local corpus after geometry changes. Keep private SVGs and derived renders out of Git.
4. Continue with lighter fallback meshes or manifold dual contouring, then GLB export. Issue #4 tracks fallback performance and topology; issue #2 tracks GLB.

## Geometry Baseline and Limits

All 162 tested SVGs passed strict mesh validation. Forty-two used a denser path; in that group, median output was 146,382 triangles and median parse-and-mesh time was 5.619 s. Across the full corpus, the median was 48,844 triangles and 0.932 s. These are measurements on the development Mac, not performance guarantees.

On one representative fallback case, sampling took 0.016 s, dual contour extraction took 0.204 s, and fallback work took 4.510 s. The raw fallback had 1,718,584 triangles and simplified to 175,194. Avoid optimizing grid sampling first: it is a small part of this case's cost. Investigate normals computed for discarded vertices, per-cell allocations, invalid-mesh validation work, and simplification candidates under the existing error bounds.

A first temporary deferred-normal and packed-edge-key prototype preserved position/index and normal digests exactly, but three paired runs showed only a modest, noisy improvement. Measure further changes with alternating baseline/candidate runs, no concurrent builds, strict validity, and exact geometry digests when output should be unchanged.

Passing tests and notarization do not establish VoiceOver acceptance, performance with dozens of icons in Motion, or Cinema 4D import sizing. Those remain hands-on checks.
