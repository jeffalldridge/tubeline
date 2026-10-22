# Roadmap

Where Tubeline is headed. This is a plan, not a promise: priorities move with feedback,
and every item links to an issue where you can follow progress, upvote with 👍, or add a
use case. Last updated 2026-10-22 (v0.1.0).

## Principles

- **One job, done well:** stroked artwork → clean 3D models for motion graphics apps.
- **USDZ is the default output.** Other formats are added alongside it, never instead of it.
- **Clean geometry first:** one closed solid per icon, light enough to animate by the dozen.
- **Native and private:** Apple frameworks, no third-party dependencies unless they earn it,
  no network, no analytics. Apple silicon, macOS 14+.

## Now — v0.1.x

- [Validate output in motion graphics apps (Apple Motion first)](https://github.com/jeffalldridge/tubeline/issues/3)
  — sizing, materials and performance in real projects. Feedback wanted.
- Bug fixes from real-world icons ([report a bad conversion](https://github.com/jeffalldridge/tubeline/issues/new?template=bad-conversion.yml)).

## Next — v0.2

- [**Export GLB (glTF 2.0) for After Effects and other apps**](https://github.com/jeffalldridge/tubeline/issues/2)
  — USDZ stays the default; GLB (or both) as an option, with an unlit material for Solid Color.
- [Manifold dual contouring at crossing saddles](https://github.com/jeffalldridge/tubeline/issues/4)
  — strictly 2-manifold meshes where strokes cross.
- [Miter and bevel stroke joins](https://github.com/jeffalldridge/tubeline/issues/5)

## Later

- [Support `<use>` and `<symbol>`](https://github.com/jeffalldridge/tubeline/issues/6)
- [Optional crisp low-poly mode (analytic sweeps)](https://github.com/jeffalldridge/tubeline/issues/7)
- Settings window, accessibility and localization pass
- Mac App Store distribution (alongside the free notarized download)

## Not planned

- Textures, UVs, lights, cameras or animation inside the exported files — your motion
  graphics app handles those.
- `<text>` elements — convert text to outlines first.
- Intel Macs.

## How the roadmap works

- Each item is a GitHub issue labeled [`roadmap`](https://github.com/jeffalldridge/tubeline/labels/roadmap);
  this file is the summary and links to them.
- Items move Later → Next → Now as they're scheduled, and land in [CHANGELOG.md](CHANGELOG.md)
  when released.
- Have an idea? [Open a feature request](https://github.com/jeffalldridge/tubeline/issues/new?template=feature.yml)
  describing the motion-design task you're trying to do.
