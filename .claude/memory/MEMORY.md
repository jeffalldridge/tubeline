# Tubeline Session Memory

A rolling log of the last ten sessions, newest first. Older entries move to `archive/`.

## October 22, 2026: From Idea to Public 0.1.0 Release

**Worked on:** Built the whole tool in one session. The engine parses SVG (paths, arcs, transforms, CSS classes, dashes), models the icon as a signed distance field, contours it with crisp creases or fillets, handles fills as discs and extrusions, simplifies the mesh against the exact surface (6–14 times fewer triangles), and writes validated USDZ. Added the SwiftUI app with a SceneKit preview, the command-line tool, the Tent Studios repository layout, sandboxing, and twenty-two tests. Published the MIT-licensed repository with CI, then released a notarized 0.1.0 with an original icon (replacing an SF Symbol) and a public roadmap. Finished with a cleanup pass that rewrote the docs in Chicago style and replaced three samples that had reused Lucide path data.

**State after:** 0.1.0 is on GitHub Releases; CI is green; Motion import hasn't been tested yet.

**Next:** Jeff tests exported icons in Motion (issue #3) and adds his own icons to `Samples/User`. GLB export (issue #2) is the 0.2 headline.
