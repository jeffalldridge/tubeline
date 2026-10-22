# Tubeline Session Memory

A rolling log of the last ten sessions, newest first. Older entries move to `archive/`.

## October 22, 2026: From Idea to Public 0.1.0 Release

**Worked on:** Built the whole tool in one session. The engine parses SVG (paths, arcs, transforms, CSS classes, dashes), models the icon as a signed distance field, contours it with crisp creases or fillets, handles fills as discs and extrusions, simplifies the mesh against the exact surface (6–14 times fewer triangles), and writes validated USDZ. Added the SwiftUI app with a SceneKit preview, the command-line tool, the Tent Studios repository layout, sandboxing, and twenty-two tests. Published the MIT-licensed repository with CI, then released a notarized 0.1.0 with an original icon (replacing an SF Symbol) and a public roadmap. Finished with a cleanup pass that rewrote the docs in Chicago style and replaced three samples that had reused Lucide path data.

Later the same day: added the "Protect main" ruleset (no force pushes or deletion, CI required on pull requests, admins bypass) and ran Jeff's first private icon set, `Samples/User/SVG Icons Outlines` (156 Illustrator-style icons on a 48 × 48 canvas with 1 pt strokes). All 156 converted with no failures and looked right in spot checks: median 0.69 s and 44,000 triangles per icon, worst 1.17 s and 91,000 triangles.

**State after:** 0.1.0 is on GitHub Releases; CI is green; the repository is cleaned up and ready for a fresh agent to pressure-test. Motion import hasn't been tested yet.

**Handoff for the next agent:** start with AGENTS.md (it maps the engine pipeline and the rules), then BACKLOG.md. The build, test, and CLI commands in AGENTS.md all work from a fresh clone; run tests with `CODE_SIGNING_ALLOWED=NO` if you don't have the Tent Studios certificate. Releasing needs Jeff's Mac.

**Next:** Jeff tests exported icons in Motion (issue #3) and adds his own icons to `Samples/User`. GLB export (issue #2) is the 0.2 headline.
