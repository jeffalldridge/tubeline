# Tubeline Session Memory

A rolling log of the last ten sessions, newest first. Older entries move to `archive/`.

## October 22, 2026: Release 0.2.0 for Colleague Review

**Worked on:** Independent engine, export, and app audits followed by geometry validation, safer export state, batch settings with per-field overrides, saved defaults, visible output controls and triangle counts, integer output scaling, and repaired camera commands. Front uses an orthographic camera with zero rotation. USDZ remains XY artwork facing +Z, Y up, with no baked camera or rotation.

**Evidence:** Fifty-six app tests passed; all 162 test SVGs passed strict mesh validation. Six original samples passed `usdchecker --arkit`. Native checks covered export destinations, collision handling, inheritance, scale, and Front/Reset controls. Jeff reports that the earlier USDZ output imports well into Motion; the new release still needs his Motion and Cinema 4D acceptance.

**Follow-up:** On `codex/mesh-optimization`, committed stronger vertical-orientation coverage (`0b5f9ba`), release metadata guards (`8de26ac`), queued automatic exports and settled-row removal fixes (`a5cc62e`), and an internal early verdict for already-invalid meshes (`b4a7aeb`). Sixty-one app tests and forty-four core tests passed. All 162 outputs matched the release baseline in geometry/index and normal hashes, triangle counts, strict validity, and warning counts. A controlled three-pair experiment on one complex icon measured an 8.1 percent median reduction; do not generalize that to every icon. Further extractor experiments remain unmerged. Commit `829e1a9` also fixes a reproduced concurrent CLI keep-both race using sibling staging and exclusive atomic publication, with a regression harness added to CI. The released CLI still has this race; avoid concurrent commands writing to the same output folder until the follow-up ships.

**Tradeoff:** Forty-two corpus icons take a denser validated path. Across that group, median output is 146,382 triangles and median parse-and-mesh time is 5.619 s. Do not weaken topology checks to improve these numbers. The next task is reducing fallback extraction and simplification cost while preserving the whole-icon SDF.

**Release handoff:** Jeff authorized logical commits, pushing, and a signed, notarized 0.2.0 release. Published v0.2.0 from commit `0fba569` with a signed, notarized, stapled DMG and a signed, notarized CLI. Gatekeeper accepted both app and DMG. GitHub CI run `39860251368` passed for that exact commit, including engine build/tests, sample USDZ validation, and app tests. The actual stored notary profile is `syntaxlook-notary`. Further work is on `codex/mesh-optimization`; preserve the release tag. See `docs/next-work.md`.

## October 22, 2026: From Idea to Public 0.1.0 Release

**Worked on:** Built the whole tool in one session. The engine parses SVG (paths, arcs, transforms, CSS classes, dashes), models the icon as a signed distance field, contours it with crisp creases or fillets, handles fills as discs and extrusions, simplifies the mesh against the exact surface (6–14 times fewer triangles), and writes validated USDZ. Added the SwiftUI app with a SceneKit preview, the command-line tool, the Tent Studios repository layout, sandboxing, and twenty-two tests. Published the MIT-licensed repository with CI, then released a notarized 0.1.0 with an original icon (replacing an SF Symbol) and a public roadmap. Finished with a cleanup pass that rewrote the docs in Chicago style and replaced three samples that had reused Lucide path data.

Later the same day: added the "Protect main" ruleset (no force pushes or deletion, CI required on pull requests, admins bypass) and ran Jeff's first private icon set, `Samples/User/SVG Icons Outlines` (156 Illustrator-style icons on a 48 × 48 canvas with 1 pt strokes). All 156 converted with no failures and looked right in spot checks: median 0.69 s and 44,000 triangles per icon, worst 1.17 s and 91,000 triangles.

**State after:** 0.1.0 is on GitHub Releases; CI is green; the repository is cleaned up and ready for a fresh agent to pressure-test. Motion import hasn't been tested yet.

**Handoff for the next agent:** start with AGENTS.md (it maps the engine pipeline and the rules), then BACKLOG.md. The build, test, and CLI commands in AGENTS.md all work from a fresh clone; run tests with `CODE_SIGNING_ALLOWED=NO` if you don't have the Tent Studios certificate. Releasing needs Jeff's Mac.

**Next:** Jeff tests exported icons in Motion (issue #3) and adds his own icons to `Samples/User`. GLB export (issue #2) is the 0.2 headline.
