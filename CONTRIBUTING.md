# Contributing to Tubeline

Thanks for helping. Tubeline is small on purpose: one job (stroked SVG → clean 3D tubes for
Apple Motion), native frameworks, no third-party dependencies.

## Reporting a bad conversion

The most useful report is an SVG that converts wrong. Please attach:

- the SVG (or a minimal one that reproduces it — only artwork you have the right to share),
- your settings (or the `tubeline` command line you ran),
- a screenshot of the preview, and what you expected.

## Development

Requirements: Apple silicon Mac, macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd app && xcodegen generate          # the .xcodeproj is generated, never committed
xcodebuild -project Tubeline.xcodeproj -scheme Tubeline test \
  CODE_SIGNING_ALLOWED=NO            # or open it in Xcode and press ⌘U
swift run -c release tubeline Samples -o /tmp/tubeline --png
```

To sign and run the app with your own Apple ID, set your team in Xcode's Signing & Capabilities
or pass `DEVELOPMENT_TEAM=<your team>` — please don't commit that change.

- The engine lives in `Sources/TubelineCore`; the app in `app/Tubeline`.
- Read [AGENTS.md](AGENTS.md) for architecture and conventions (it doubles as the guide for
  AI coding assistants).
- The one rule: **one watertight solid per icon.** Never stitch separately meshed tubes.
- Add a test for every fix (`app/TubelineTests`). Use generated SVG strings or files in
  `Samples/` — never third-party icon sets. Put your own test icons in `Samples/User/` (ignored).
- `TL_PROFILE=1 swift run -c release tubeline …` prints per-stage timings.

## Pull requests

- One concern per PR, [Conventional Commits](https://www.conventionalcommits.org/) titles
  (`fix:`, `feat:`, `perf:`, `docs:` …).
- CI must be green: build, tests, and every sample passing `usdchecker`.
- For geometry changes, include before/after renders (`--png`) and triangle counts.

By contributing you agree your work is released under the [MIT License](LICENSE).
