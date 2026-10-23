# Tubeline Decisions

Architectural and product decisions, with the reasoning behind them. Newest first.

## October 23, 2026: Default Output Scale Is 10×, the Same for USDZ and GLB (Jeff)

GLB imported into After Effects far too small at true print size; Jeff had to scale it 1,000 percent. A GLB-only scale was tried and rejected: Jeff wants both formats sized identically. The default Output Scale is now 10× for both; Motion's Automatic size normalizes USDZ anyway. Saved defaults from before version 2 of the options at 1× migrate to 10× once; other saved values stay. Adobe documents no unit mapping for GLB; community reports suggest about 512 px per meter.

## October 23, 2026: Blend Only Where Surfaces Meet at an Angle (Jeff's T Report)

A plain smooth union inflated places where one stroke merely touches another from inside (a bump on top of a T) or where tubes are tangent (the front of a crossing). Blending now scales each pair's fillet by the angle between their surfaces: none within about 26 degrees of parallel, full past about 96. Rejected: an "exposed surface" test, which collapsed the fillet near the joint. Fading the fillet abruptly caused dimples, so the fade is gradual and uses whole-stroke directions. Blended meshes skip crease splitting (it misread tight fillets as creases and made shards), and contouring checks every cell corner because blended fields aren't 1-Lipschitz.

## October 22, 2026: Share 0.2.0 Before Further Optimization (Jeff)

Ship the reviewed workflow, camera, sizing, and geometry safeguards as 0.2.0 so Jeff can demonstrate it to a colleague. GLB remains next without a promised version. Continue optimization after the release tag. Output Scale is an integer multiplier; physical units and topology stay independent. Preview projection belongs to the preview, while the exported model faces +Z at zero rotation.

## October 22, 2026: Light Protection for main (Jeff)

A repository ruleset named "Protect main" blocks force pushes and branch deletion and requires the `build-and-test` CI check on pull requests. Repository admins can bypass it, so Jeff and his agents keep pushing directly to `main`. Required reviews and required pull requests were left off because they would force a solo maintainer to review his own work.

## October 22, 2026: Writing Follows Chicago Style in a Natural Voice (Jeff)

All text that ships uses American English and the *Chicago Manual of Style* and is edited so it doesn't read like AI wrote it. The rules are in the Writing section of AGENTS.md.

## October 22, 2026: Samples Must Be Original Artwork

Three samples had reused path data from the Lucide icon set (ISC license, which requires keeping its notice). They were redrawn instead of attributed so the samples stay free of third-party terms. Tests and samples use only original artwork.

## October 22, 2026: USDZ Stays the Default; GLB Comes Next (Jeff)

After Effects prefers GLB, so GLB export, with an unlit material for Solid Color, is the headline for 0.2. It's an additional format and never replaces USDZ. The public plan lives in ROADMAP.md, and each item is a GitHub issue labeled `roadmap`.

## October 22, 2026: Releases Are Built Locally, with a Guarded CI Workflow

This matches macSubtitleOCR-gui and syntax-look-app: a Developer ID export, a notarized and stapled app and DMG, a notarized CLI, SHA-256 checksums, and notes taken from the changelog. The tag-triggered workflow skips itself until signing secrets are added.

## October 22, 2026: The Icon Is an Original Glyph Rendered by Tubeline (Jeff)

Jeff's temporary icon used the SF Symbol `graph.3d`, which Apple's license forbids in app icons. Jeff chose to replace it with an original loop-the-loop glyph (`marketing/icon/glyph.svg`) rendered as a 3D tube by Tubeline, keeping his gradient and glass settings.

## October 22, 2026: Keep usdcat for Binary USD; Model I/O Rejected (Measured)

Model I/O writes binary USD in-process in 5 ms, compared with about 70 ms for `usdcat`, but it leaves out `metersPerUnit` and gives material colors the wrong types, so `usdchecker` fails. We write exact USD text and convert it with `/usr/bin/usdcat`. If `usdcat` is missing, the text layer is packaged as is, which also passes `usdchecker --arkit`.

## October 22, 2026: Defaults Favor Animation Performance (Jeff)

Optimization is on, facets default to 32 (the true number of sides; exact normals keep shading round), each icon is one mesh with one material (one draw call), and triangles are ordered for the GPU. Apple silicon only.

## October 22, 2026: No Metal for Meshing (Measured)

After parallelizing on the CPU, grid sampling, the part a GPU would speed up, takes 3–30 ms. Most of the remaining time is mesh simplification, which is sequential graph work. A Metal path would add setup cost without a visible gain. Revisit only if people convert very large icons interactively.

## October 22, 2026: Simplify with Quadric Edge Collapse; Skip Adaptive Contouring (Research)

Uniform dual contouring was 5–12 times denser than needed on straight runs. Quadric edge collapse on the welded mesh, limited to one facet's sag and checked against the exact distance field, gives the biggest gain for the least code. Adaptive contouring can't coarsen much along thin tubes. See `docs/research/2026-10-22-claude-mesh-optimization.md`.

## October 22, 2026: Free and Open Source (Jeff)

MIT License, public repository, published by Tent Studios. This overrides the house default of proprietary, paid apps; Tubeline is a free tool for motion designers.

## October 22, 2026: Sizing Is Based on Points (Jeff)

Artwork is drawn in points, so one SVG unit is one point (design tools treat px and pt alike), and one point is 1/72 inch by default. USD output is in centimeters (`metersPerUnit = 0.01`), as Apple's tools write it. Extrusion depth is in points too.

## October 22, 2026: Solid Color Is the Default Surface (Jeff)

An emission-only `UsdPreviewSurface` makes icons read as flat color whatever the scene's lighting. Shaded, a matte diffuse material, is the alternative.

## October 22, 2026: One Distance-Field Solid Instead of Swept Tubes

Swept tubes overlap and leave interior faces. A single signed distance field gives clean crisp or filleted intersections, fills, and extrusions in one model. Dual contouring keeps crisp seams and flat cap edges sharp, and crease vertices get split normals.

## October 22, 2026: Only Declared Fills Count

SVG's implicit black fill would turn line icons into blobs, so only fills the file declares become solid. A filled shape with an outline becomes a disc as thick as the outline instead of a torus; a fill with no outline is extruded.
