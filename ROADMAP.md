# Roadmap

This is where Tubeline is headed. It's a plan, not a promise, and priorities will shift as people use the app. Each item links to a GitHub issue, where you can follow progress, add a 👍, or describe how you'd use it.

*Last updated October 22, 2026 (version 0.3.0)*

## Principles

- Tubeline does one job: it turns stroked artwork into clean 3D models for motion graphics apps.
- USDZ is the default format. New formats are added alongside it, never in its place.
- Every icon becomes one closed solid, light enough to animate dozens at a time.
- The app uses Apple's frameworks, avoids third-party dependencies, and never connects to the network or collects data. It runs on Apple silicon Macs with macOS 14 or later.

## Recently Shipped

- [GLB (glTF 2.0) export for After Effects and other apps](https://github.com/jeffalldridge/tubeline/issues/2) in version 0.3.0. USDZ stays the default, and you can choose GLB or both. Solid Color uses an unlit material so it stays flat in GLB too.

## Now (Version 0.3)

- [Test the output in motion graphics apps, starting with Apple Motion](https://github.com/jeffalldridge/tubeline/issues/3): check size, materials, and performance in real projects, including After Effects with GLB. Feedback is welcome.
- Fix problems found with real-world icons. If one converts badly, please [report it](https://github.com/jeffalldridge/tubeline/issues/new?template=bad-conversion.yml).

## Next

- [Remove the last dense fallbacks at stroke crossings](https://github.com/jeffalldridge/tubeline/issues/4). Version 0.3 contours each sheet of surface separately, so only 2 of 162 test icons still need the denser fallback mesh.
- [Support miter and bevel corners](https://github.com/jeffalldridge/tubeline/issues/5).

## Later

- [Support `<use>` and `<symbol>`](https://github.com/jeffalldridge/tubeline/issues/6).
- [Add an optional low-poly mode with crisp joins](https://github.com/jeffalldridge/tubeline/issues/7).
- Continue accessibility and localization review. The Settings window shipped in 0.2.
- Offer Tubeline on the Mac App Store in addition to the free download.

## Not Planned

- Textures, UV maps, lights, cameras, or animation in exported files. Your motion graphics app handles those.
- `<text>` elements. Convert text to outlines first.
- Intel-based Macs.

## How the Roadmap Works

Every item is a GitHub issue with the [`roadmap`](https://github.com/jeffalldridge/tubeline/labels/roadmap) label, and this page summarizes them. Items move from Later to Next to Now as work is scheduled, and finished work is listed in the [changelog](CHANGELOG.md).

To suggest something, [open a feature request](https://github.com/jeffalldridge/tubeline/issues/new?template=feature.yml) and describe the motion design task you're trying to do.
