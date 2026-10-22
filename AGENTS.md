# Tubeline — AI Project Instructions

Single source of truth for AI sessions in this repo. `CLAUDE.md` points here.

## Identity

- **Product:** Tubeline (codename until Phase 5 name research)
- **Publisher:** Tent Studios, LLC (Jeff Alldridge) — team `ACL5A8Y9U7`
- **What it is:** A native macOS utility that turns stroked SVG icons into 3D
  tube models (USDZ) for Apple Motion. Drop SVGs, get `.usdz` files with a live
  3D preview. Every stroke becomes a round tube; intersections fuse cleanly.
- **What it is NOT:** A 3D modeler, a renderer, or a general SVG-to-3D
  extruder. No textures, UVs, lights or cameras in the output.
- **Price:** Free. **License:** MIT, public repo (decision 2026-10-22).
  Distribution: notarized Developer ID build (GitHub releases / Gumroad);
  Mac App Store optional later.
- **macOS target:** 14.0+ (Sonoma), Apple silicon only
- **Core philosophy:** Feel like Apple could have shipped it. Native frameworks,
  zero third-party dependencies unless they earn their place. Output must be
  clean geometry a motion designer never has to fix.

## The One Non-Negotiable Rule

**One watertight solid per icon.** Strokes, caps, joints, dashes and fills are
modeled as a single signed distance field and meshed once. Never stitch
separately-meshed tubes or leave interior faces — clean intersections are the
product. Any optimization (decimation, retopology) must keep the mesh closed
(no boundary edges); `MeshingTests.assertWatertight` guards this. Known gap:
dual contouring can pinch two sheets onto one edge at crossing saddles
(non-manifold, not a hole) — manifold DC is on the backlog.

## Tech Stack

- **Swift / SwiftUI** — `@Observable`, MainActor-default isolation in the app
- **TubelineCore** (Swift package at repo root) — SVG parsing, dashing, SDF +
  dual contouring mesher, USDZ writer (own zip writer; `usdcat` converts to
  binary crate when available, text USD otherwise), SceneKit preview scene
- **`tubeline` CLI** (same package) — batch conversion and `--png` previews
- **SceneKit** — 3D preview (orbit camera)
- **xcodegen** — `app/project.yml` generates the Xcode project. Never edit the
  `.xcodeproj` by hand: `cd app && xcodegen generate`
- **XCTest** — `app/TubelineTests`, hosted in the sandboxed app (so tests also
  prove sandbox behavior, e.g. launching `usdcat`)

## Project Structure

```
tubeline/
├── AGENTS.md  CLAUDE.md  README.md  CHANGELOG.md  LICENSE (MIT)
├── Package.swift                 ← TubelineCore library + tubeline CLI
├── Sources/TubelineCore/         ← engine (parser, Dasher, FusedMesher, USDZWriter, …)
├── Sources/tubeline/             ← CLI
├── Samples/                      ← our own test SVGs (tracked); Samples/User/ is gitignored
├── .claude/memory/               ← MEMORY / DECISIONS / BACKLOG / PREFERENCES
├── docs/research/  docs/release/  docs/testing/  docs/superpowers/{specs,plans}/
├── marketing/  scripts/release.sh
└── app/
    ├── project.yml  ExportOptions.plist  ExportOptions-developer-id.plist
    ├── Tubeline/{App,Models,Services,Views,Resources}/
    └── TubelineTests/
```

## Build & Test

```bash
cd app
xcodegen generate
xcodebuild -project Tubeline.xcodeproj -scheme Tubeline build
xcodebuild -project Tubeline.xcodeproj -scheme Tubeline test
# CLI (TL_PROFILE=1 prints per-stage timings)
swift run -c release tubeline Samples -o /tmp/out --png
```

## Compliance

- **Sandbox:** user-selected read-write + app-scope bookmarks. "Save next to
  original" asks once per folder (`FolderAccess`) and remembers the grant.
  Hardened runtime on. Same binary for every channel.
- **No network, no analytics, no telemetry.** Privacy manifest declares
  UserDefaults only.
- Never put an Apple product name ("Motion", "Reality") in the app name.

## Development Phases

| Phase | Goal | Status |
|---|---|---|
| 0 | Scaffold: engine, CLI, app shell, tests, house layout | Done 2026-10-22 |
| 1 | Core MVP: drop → preview → export, all edge cases (caps, dashes, fills, extrusion) | Done 2026-10-22 |
| 2 | **Empirical Motion validation** — import into Motion: scale, Solid Color material, normals, performance with many icons | Open |
| 3 | Geometry optimization: QEM decimation, faster meshing (docs/research/2026-10-22-claude-mesh-optimization.md) | Core done 2026-10-22; manifold DC + welded USD normals open |
| 4 | Polish: app icon, a11y, HIG audit, Settings window, user icon test pass | |
| 5 | Ship: name research, notarized build, site/README screenshots | |

## Conventions

- One type per file in the app; engine files group closely related types
- No processing logic in views
- Typed errors (`LocalizedError`), no silent failures, no force unwraps in production paths
- Comments explain WHY
- Conventional commits; **AI may commit, but NEVER push. Jeff pushes.**
- Commit `.claude/memory/` files

## Session Protocol

Standard Tent Studios Hello/Shutdown protocol.

**Hello:** read `.claude/memory/MEMORY.md`, then this file. Check
`git log --oneline -10` + `git status`, flag discrepancies with memory.

**Shutdown:** present-then-execute — decisions, MEMORY.md entry preview, git
state, suggested commits; on confirmation update memory files.

## Skills

Portfolio-level skills in `~/Documents/GitHub/.claude/skills/`:
**new-mac-app** (this scaffold), **app-store-preflight** (Gumroad/Developer ID
notarization channel), **swiftui-pro** (SwiftUI review).
