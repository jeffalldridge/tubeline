# Releasing Tubeline

Releases are Developer ID–signed (Tent Studios, LLC · ACL5A8Y9U7), notarized by Apple and
published as GitHub Releases: a notarized, stapled DMG, the notarized `tubeline` CLI, and
SHA-256 checksums.

## Steps

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `app/project.yml`.
2. Move the `[Unreleased]` notes in `CHANGELOG.md` under `## [x.y.z] - YYYY-MM-DD` and
   update the compare links at the bottom.
3. Commit, then run:

   ```bash
   scripts/release.sh             # dry run: build/release/ only
   scripts/release.sh --publish   # tag vX.Y.Z, push the tag, create the GitHub Release
   ```

   Set `TUBELINE_NOTARY_PROFILE` if your notarytool keychain profile isn't named
   `tubeline-notary` (any profile for team ACL5A8Y9U7 works).

## What the script checks

Tests pass; the exported app is signed by the Tent Studios Developer ID with hardened
runtime and the sandbox entitlement, has no `get-task-allow`, is arm64-only, matches the
version, and has no stale `CFBundleIconFile` (validator error 90236). The app and DMG are
notarized and stapled and pass Gatekeeper (`spctl`); the CLI is notarized and smoke-tested.

## CI releases

`.github/workflows/release.yml` runs the same script on a pushed `v*.*.*` tag once the
signing secrets listed in that file are configured, and uploads to the release. Until then
it skips with a notice, so locally published releases never show a failed run.

## App icon

The icon's glyph is rendered by Tubeline itself from `marketing/icon/glyph.svg`
(`scripts/render-icon.sh`); gradient, shadow and glass are in
`app/Tubeline/Resources/AppIcon.icon` (edit in Icon Composer). Never use SF Symbols in the
icon — Apple's license forbids it.
