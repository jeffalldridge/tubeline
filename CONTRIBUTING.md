# Contributing to Tubeline

Thanks for your interest in helping. Tubeline is deliberately small: it turns stroked SVG artwork into clean 3D tubes for motion graphics apps, using Apple's frameworks and no third-party dependencies. Before you start on something large, check the [roadmap](ROADMAP.md) and comment on the related issue so we can agree on an approach first.

## Reporting a Bad Conversion

An SVG that converts incorrectly is the most useful bug report. Please include:

- The SVG, or a smaller one that shows the same problem. Only share artwork you have the right to share.
- Your settings, or the `tubeline` command you ran.
- A screenshot of the preview and a description of what you expected.

## Setting Up

You need an Apple silicon Mac with macOS 14 or later, Xcode 26 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
swift test                         # Engine tests run without an app host.
cd app
xcodegen generate                  # The Xcode project is generated, never committed.
xcodebuild -project Tubeline.xcodeproj -scheme Tubeline test \
  CODE_SIGNING_ALLOWED=NO            # Or open the project in Xcode and press ⌘U.
cd ..
swift run -c release tubeline Samples -o /tmp/tubeline --png
```

To run the signed app under your own Apple ID, choose your team in Xcode's Signing & Capabilities pane, or pass `DEVELOPMENT_TEAM=<your team ID>` to `xcodebuild`. Please don't commit that change.

## Guidelines

- The engine lives in `Sources/TubelineCore` and the app in `app/Tubeline`. [AGENTS.md](AGENTS.md) explains the architecture and conventions. It also serves as the guide for AI coding assistants.
- Mesh the whole icon's distance field once. Overlaps must fuse, and disconnected marks must remain closed components. Never mesh tubes separately and stitch them together. Validate topology before exporting.
- Add a test with every fix in `app/TubelineTests`. Use SVG strings written in the test or files in `Samples`, never third-party icon sets. Keep your own test icons in `Samples/User`, which Git ignores.
- Write docs and interface text in American English, following the *Chicago Manual of Style*.
- To see how long each stage takes, run `TL_PROFILE=1 swift run -c release tubeline …`.

## Pull Requests

- Keep each pull request to one change, with a title that follows [Conventional Commits](https://www.conventionalcommits.org/) (for example, `fix:`, `feat:`, or `docs:`).
- CI must pass. It builds the app, runs the tests, and checks every sample with `usdchecker`.
- For geometry changes, include before-and-after renders (`--png`) and triangle counts.

By contributing, you agree that your work is released under the [MIT License](LICENSE).
