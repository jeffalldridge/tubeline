# Tubeline: Instructions for AI Agents

This file is the single source of truth for AI sessions in this repository. `CLAUDE.md` points here. Human contributors should start with [CONTRIBUTING.md](CONTRIBUTING.md).

## Identity

- **Product:** Tubeline, a native Mac app that turns stroked SVG icons into 3D tube models saved as USDZ, for Apple Motion and other motion graphics apps. Each stroke becomes a round tube, and crossings fuse cleanly.
- **Not:** a 3D modeler, a renderer, or a general SVG extruder. Exported files have no textures, UV maps, lights, or cameras.
- **Publisher:** Tent Studios, LLC (Jeff Alldridge), Apple Developer team `ACL5A8Y9U7`.
- **Price and license:** free, MIT License, public repository at github.com/jeffalldridge/tubeline.
- **Distribution:** notarized Developer ID builds on GitHub Releases (version 0.2.0 shipped October 22, 2026). The Mac App Store may come later.
- **Platform:** Apple silicon Macs running macOS 14 or later. No Intel builds.
- **Philosophy:** it should feel like something Apple could have shipped. Use Apple's frameworks and avoid third-party dependencies unless one clearly earns its place. The output should never need cleanup by a motion designer.

## The Rule That Can't Be Broken

**Every icon becomes one closed solid.** Strokes, caps, joints, dashes, and fills are modeled as a single signed distance field and meshed once. Never mesh tubes separately and stitch them together, and never leave interior faces; clean intersections are the product. Any optimization must keep the mesh closed, with no boundary edges. `MeshingTests.assertWatertight` checks this.

Disconnected marks may form separate closed components in the same mesh. Where a dual-contouring cell joins surface sheets incorrectly, the engine retries the same sampled union with consistent tetrahedra. It validates edge incidence, winding, vertex neighborhoods, and degenerate or duplicate faces before export. The fallback can produce heavier meshes; contouring improvements remain tracked in issue #4.

## How the Engine Works

The engine is the `TubelineCore` Swift package at the repository root. A conversion (`Converter.convert`) runs these steps:

1. **Parse** (`SVGDocument.swift`, `PathData.swift`, `Dasher.swift`): read shapes, transforms, styles, and CSS classes; flatten curves into polylines; split dashes. Honor default black fills when no stroke paint is declared. Explicitly stroked line art still requires an explicit fill; never invent a stroke for an unstyled shape.
2. **Model** (`Converter.buildMesh`): turn strokes into primitives (capsules, capped cylinders, spheres) and fills into slabs or extrusions, grouped so fillets blend only between separate strokes. Scale from artwork points to centimeters.
3. **Sample and contour** (`FusedMesher.swift`): sample the exact distance on a grid in parallel, using `SpatialLookup`, then extract a surface with dual contouring so creases stay sharp. Meshing uses normalized internal units; physical sizing is applied afterward. Invalid contour topology triggers a tetrahedral extraction from the same whole-icon field.
4. **Simplify** (`Decimator.swift`): collapse edges by quadric error, testing surface distance at the proposed vertex and sample points across changed triangles. Tiles run in parallel; a final pass cleans up the seams between them. These probes are a sampled error criterion, not a proof of the maximum error over every triangle.
5. **Shade and order**: take normals from the exact surface, split them at creases, and reorder triangles for the GPU (`MeshOrdering.swift`).
6. **Write** (`USDZWriter.swift`): write USD text with exact types, convert it to binary with macOS's `usdcat`, and package it as USDZ with our own zip writer. Model I/O was rejected because its output fails `usdchecker`.

`PreviewRenderer.swift` builds the SceneKit scene for the app's preview and for the CLI's `--png` renders. Set `TL_PROFILE=1` to print timings for each stage.

## Repository Layout

```
Package.swift            TubelineCore library and tubeline command-line tool
Sources/TubelineCore/    The engine (see above)
Sources/tubeline/        Command-line tool
app/project.yml          XcodeGen definition; the .xcodeproj is generated and ignored by Git
app/Tubeline/            SwiftUI app: App, Models, Services, Views, Resources
app/TubelineTests/       XCTest suite, hosted in the sandboxed app
Samples/                 Original test SVGs; Samples/User is for private icons and ignored
marketing/icon/          Source SVG for the app icon's glyph
scripts/                 release.sh (notarized release), render-icon.sh (icon glyph)
docs/research/           Research notes (mesh optimization)
docs/release/            RELEASING.md
.github/                 CI, release workflow, issue and pull request templates
.claude/memory/          Session memory: MEMORY, DECISIONS, BACKLOG, PREFERENCES
README, ROADMAP, CHANGELOG, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, LICENSE
```

## Build and Test

```bash
swift test                     # Engine tests without an app host.
cd app
xcodegen generate
xcodebuild -project Tubeline.xcodeproj -scheme Tubeline build
xcodebuild -project Tubeline.xcodeproj -scheme Tubeline test   # Add CODE_SIGNING_ALLOWED=NO without the team's certificate.
cd ..
swift run -c release tubeline Samples -o /tmp/out --png
for f in /tmp/out/*.usdz; do usdchecker --arkit "$f"; done
```

The app-hosted suite includes engine tests and app-state regressions. CI (`.github/workflows/ci.yml`) also runs the standalone engine tests, converts the original samples, and validates USDZ on an Apple silicon runner with Xcode 26.

## Releases

Follow [RELEASING.md](docs/release/RELEASING.md). `scripts/release.sh --publish` signs, notarizes, staples, tags, and publishes. It needs the Tent Studios Developer ID certificate and a notarytool profile, which exist only on Jeff's Mac. The CI release workflow skips itself until signing secrets are added to the repository.

## Compliance

- **Sandbox:** user-selected read-write access plus app-scoped bookmarks. Saving next to the original file asks once per folder (`FolderAccess`) and remembers the answer. Hardened runtime is on.
- **Privacy:** no network access, analytics, or telemetry. The privacy manifest declares UserDefaults and file timestamps for user-selected SVGs.
- **Icon:** the glyph is original artwork rendered by Tubeline. Never use SF Symbols in the icon, because Apple's license forbids it.
- **Samples and tests:** use only original artwork or SVG written in the test. Never commit third-party icon sets.
- **Naming:** never put an Apple product name, such as Motion or Reality, in the app's name.

## Status

| Phase | Goal | Status |
| --- | --- | --- |
| 0 | Engine, CLI, app shell, tests, and house layout | Done October 22, 2026 |
| 1 | Core conversion with every edge case (caps, dashes, fills, extrusion) | Done October 22, 2026 |
| 2 | Testing in motion graphics apps, starting with Apple Motion (issue #3) | Open |
| 3 | Lighter, faster meshes | Done; manifold contouring (issue #4) is still open |
| 4 | Polish: Settings window, accessibility, HIG review | Open |
| 5 | Ship: notarized build, icon, public repository | 0.2.0 released; trademark check still open |

The public plan is [ROADMAP.md](ROADMAP.md). Every item there is a GitHub issue labeled `roadmap`; keep the file and the issues in sync, and move finished work to [CHANGELOG.md](CHANGELOG.md). USDZ is always the default export format, and GLB export for After Effects (issue #2) is next.

## Conventions

- In the app, put one type in each file. Engine files group closely related types.
- Keep processing logic out of views.
- Use typed errors (`LocalizedError`). Don't fail silently, and don't force-unwrap in production code paths.
- Comments explain why, not what.
- Use Conventional Commits. AI agents may commit freely, but push only when Jeff asks.
- `main` is protected by the "Protect main" ruleset: no force pushes, no deletion, and pull requests need the `build-and-test` CI check to pass. Repository admins bypass it, so Jeff (and agents pushing as Jeff) can still push directly. Never rewrite published history.
- Commit the `.claude/memory` files.

## Writing

These rules apply to every agent and to all text that ships: docs, interface strings, CLI help, release notes, issues, and commit messages.

- Use American English and the *Chicago Manual of Style*: serial commas; closed em dashes (word—word); headline-style capitalization for titles and headings; numbers zero through one hundred spelled out in running prose, but numerals with units, versions, and measurements (24 pt, 0.1.0); and commas after "e.g." and "i.e."
- Make it sound like a person wrote it. Use plain verbs, short sentences, and concrete claims. Reread text before committing it and cut anything that reads like AI: hype words (seamless, robust, powerful, effortless, leverage), "not just X but Y" constructions, padded lists of three, stacked em dashes, "In short," bold lead-ins on every bullet, and emoji.
- Interface text follows the voice of Apple's Human Interface Guidelines: brief and direct, with title case for buttons and menu items.

## Session Protocol

Tubeline uses the standard Tent Studios hello and shutdown routine.

- **Hello:** read `.claude/memory/MEMORY.md`, then this file. Run `git log --oneline -10` and `git status`, and point out anything that doesn't match the memory.
- **Shutdown:** list decisions, preview the new MEMORY.md entry, report the Git state, and suggest commits. After Jeff confirms, update the memory files.

## Skills

Shared skills live in `~/Documents/GitHub/.claude/skills/`: **new-mac-app** (the layout this repository follows), **app-store-preflight** (signing and notarization checks), and **swiftui-pro** (SwiftUI review).
