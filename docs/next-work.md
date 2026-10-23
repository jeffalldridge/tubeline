# After the 0.2.0 Release

## Agent Handoff Snapshot

The development branch `codex/mesh-optimization` ([pull request #8](https://github.com/jeffalldridge/tubeline/pull/8)) now also carries per-sheet contouring and GLB export. It was merged into `main` and released as 0.3.0; the 0.2.0 tag is unchanged.

**Per-sheet contouring (commit `c7864cf`).** Dual contouring now gives each separate sheet of surface in a cell its own vertex, grouping a cell's crossing edges per cube face with the asymptotic decider so neighboring cells always agree. Quads face from each grid edge's inside end toward its outside end instead of guessing from normals, and vertices that solve to the same sharp corner are separated. On the 162-icon corpus the dense tetrahedral fallback dropped from 42 icons to 2 (`54a ai-agent-visibility` and `211a deployment-gpu`, each with a single tunnel-like cell where both neighbors join two sheets), total conversion time dropped from 408 s to 186 s, and the slowest icon from 29.0 s to 6.2 s. Former fallback icons now average about 58,000 triangles instead of 147,000. Icons that never needed the fallback changed by at most 0.85 percent in triangle count, from the exact quad orientation. Every mesh still passes strict validation.

**GLB export (commit `3904c45`).** `GLBWriter` writes binary glTF 2.0 in meters with Y up, linear base colors, and `KHR_materials_unlit` for Solid Color. `Converter.convert(svg:to:)` writes several formats from one mesh. The CLI has `--format usdz|glb|both`; the app has a Format menu in the export bar, remembers it, keeps an icon's files under one name, and reveals every file. All 163 GLB exports of the corpus and samples pass the Khronos glTF Validator with no errors or warnings, and three.js renders them upright, at the expected size, with an unlit material for Solid Color. CI now converts the samples to both formats and validates each.

**Verified locally:** 56 engine tests and 82 app tests pass; `scripts/test-cli-output.sh` passes with the new multi-format checks; a native walkthrough of the app found no layout problems beyond the copy fixes that were made.

**Not yet verified:** importing GLB into After Effects, Cinema 4D, or Blender (no copy installed here); VoiceOver and Full Keyboard Access acceptance; Motion acceptance of the newer meshes.

## Shareable Build

[Download Tubeline 0.3.1](https://github.com/jeffalldridge/tubeline/releases/download/v0.3.1/Tubeline-0.3.1.dmg). Open the DMG and drag Tubeline to Applications. Requires Apple silicon and macOS 14 or later.

Version 0.3.1 makes 10× the default Output Scale for both USDZ and GLB, so icons import into After Effects at a workable size, and fixes blended T joints (no bump on top, smooth fillets underneath). The tag `v0.3.1` points to commit `ca5b370`, on which CI passed. Apple's notary service accepted the app, DMG, and CLI; the app and DMG are stapled. A fresh download matched its checksums, Gatekeeper accepted the DMG and the app inside it (version 0.3.1, build 4), and the shipped CLI converted all six samples to USDZ and GLB at matching 10× sizes, all of which passed `usdchecker --arkit` and the Khronos glTF Validator. Notarization used the `syntaxlook-notary` keychain profile.

Published SHA-256 digests:

```text
d7fe7ebb400510b1ddc46c65ea6ceda10d9fefa0e2ce3fc7ddedaa542e11c462  Tubeline-0.3.1.dmg
b73ceb99e9b05ed78f46b4fb7323913f0894642544aa1c317f28891792e7cb2e  tubeline-cli-0.3.1.zip
```

Earlier versions remain available under their own tags.

## What to Demonstrate

1. Add SVGs or drop a folder. Adding previews before export by default; an existing saved automatic-export preference remains respected.
2. Keep Batch selected for shared settings. Choose Selected Icon to override individual values while other values continue inheriting the batch settings.
3. Watch the large triangle count above the preview. Show Form adds preview lighting without changing the exported material.
4. Use Front for an orthographic view, Fit to reframe without changing the angle, and Reset View for the initial perspective angle. Shortcuts are Command-1, Command-0, and Command-2.
5. Choose an integer Output Scale. A 24 pt canvas is about 0.85 cm at 1×; 10× gives about 8.5 cm before differences between canvas and visible artwork bounds. Scaling does not increase the triangle count.
6. Choose the destination in the bottom bar and export. Existing outputs are kept; repeat exports get unique filenames. Show in Finder reveals the result.

The exported artwork lies in XY, faces +Z, and uses Y up at zero rotation. It contains no camera or baked rotation. Projection in Motion or another receiving app depends on that app's camera. Jeff confirmed that the earlier USDZ output works well in Motion; the new release has not been independently accepted in Motion or Cinema 4D.

## Verified Follow-Up on the Development Branch

Commit `a5cc62e` fixes automatic-export requests lost during active batches and completed-row removals that canceled remaining exports. Requests coalesce by icon, take current settings when dequeued, and are discarded on explicit cancellation. Commit `0b5f9ba` strengthens orientation checks; a temporary vertical-reflection mutation failed the intended assertions. Commit `b4a7aeb` skips vertex-link diagnostics only after another check has already established failure. The public validation report remains complete.

The complete app suite passed sixty-one tests, and the standalone core suite passed forty-four. A clean and incremental app build passed the built-product metadata and icon checks. The validator change was compared against the release baseline across all 162 SVGs: triangle counts, strict validity, geometry/index hashes, normal hashes, and warning counts matched exactly.

Three alternating runs on one complex icon measured median parse-and-mesh time of 5.707 s for the release baseline and 5.246 s for the validator change, about 8.1 percent lower. This is a result for one case, not a corpus-wide speed claim. Larger extraction and validator experiments remain unmerged. Reviewable patches and their limits are saved in `docs/research/experiments/README.md`.

Commit `829e1a9` fixes a reproduced concurrent CLI race: both processes could report success while only one output survived. The CLI now stages beside the destination and uses an atomic exclusive rename, retrying a unique name on collision. PNG publication preserves existing files too; a late PNG collision reports partial success. Explicit `--replace` remains replacement. `scripts/test-cli-output.sh` passes the new CLI, detects the race in the released CLI, and runs in CI. Model/PNG races, replacement, reserved batch names, and staging cleanup were checked locally.

Mesh Detail is now pinned above the scrolling settings as a standalone control. Its slider spans 6–64; Draft, Low, Balanced, and High presets use targets of 6, 16, 32, and 64. Optimize Mesh remains in the scrolling settings. Fill controls and intersection blending are exposed; only unit calibration stays collapsed. App Settings directly edits persistent startup detail, optimization, thickness, and output scale. The full app suite passed sixty-two tests, including startup preference persistence and separation from active batch settings. Native checks confirmed the main hierarchy, preferences window, and a heart changing from 2,228 to 8,038 to 29,022 triangles across the three presets. A later native check verified the pinned control stays visible while scrolling through Fills and Unit Calibration. The same heart produced 354 triangles at Draft, 8,038 at Balanced, and 29,022 at High. The app build passed after this layout change; the engine was unchanged. Saved user defaults were left unchanged during native checks.

The final [UI and HIG audit](research/2026-10-22-ui-ux-hig-audit.md) adds validated numeric drafts, saved-default guards, View menu camera/orbit commands, standard cancellation commands, clearer accessibility labels, and Reduce Motion handling. Sixty-nine integrated app tests pass. Native checks verified invalid-input feedback, orbit and Front, keyboard export, and text deletion preserving the icon. Actual VoiceOver, Full Keyboard Access, contrast, enlarged text, and minimum-window-size acceptance remain open in the audit.

The [fill extrusion fix](research/2026-10-22-fill-extrusion-regression.md) honors omitted default fills without inventing strokes and prevents zero-width strokes from suppressing extrusion. Forty-nine core tests and seventy-four app tests pass; code commit `c0a8822` passed GitHub CI. All 162 corpus meshes remain valid: 158 match the release exactly, and four with unstyled filled lettering now extrude correctly. Native preview/export and USDZ validation passed. This fix is not in the published 0.2.0 download.

## Continue Development

Work after the tag is on `codex/mesh-optimization`. Do not alter or move the published tag. Priorities:

1. Reduce fallback extraction and validation cost while preserving the whole-icon signed distance field and every topology acceptance rule.
2. Keep the strengthened orientation regression as a guard when changing coordinate conversion or export.
3. Rerun the complete local corpus after geometry changes. Keep private SVGs and derived renders out of Git.
4. Continue with lighter fallback meshes or manifold dual contouring, then GLB export. Issue #4 tracks fallback performance and topology; issue #2 tracks GLB.

## Geometry Baseline and Limits

All 162 tested SVGs passed strict mesh validation. Forty-two used a denser path; in that group, median output was 146,382 triangles and median parse-and-mesh time was 5.619 s. Across the full corpus, the median was 48,844 triangles and 0.932 s. These are measurements on the development Mac, not performance guarantees.

On one representative fallback case, sampling took 0.016 s, dual contour extraction took 0.204 s, and fallback work took 4.510 s. The raw fallback had 1,718,584 triangles and simplified to 175,194. Avoid optimizing grid sampling first: it is a small part of this case's cost. Investigate normals computed for discarded vertices, per-cell allocations, invalid-mesh validation work, and simplification candidates under the existing error bounds.

A first temporary deferred-normal and packed-edge-key prototype preserved position/index and normal digests exactly, but three paired runs showed only a modest, noisy improvement. Measure further changes with alternating baseline/candidate runs, no concurrent builds, strict validity, and exact geometry digests when output should be unchanged.

Passing tests and notarization do not establish VoiceOver acceptance, performance with dozens of icons in Motion, or Cinema 4D import sizing. Those remain hands-on checks.
