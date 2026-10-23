# Releasing Tubeline

Each release is signed with the Tent Studios, LLC Developer ID certificate (team ACL5A8Y9U7), notarized by Apple, and published on GitHub. A release includes a notarized and stapled DMG, the notarized `tubeline` command-line tool, and SHA-256 checksums.

## Steps

1. In `app/project.yml`, increase `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
2. In `CHANGELOG.md`, move the notes under `[Unreleased]` into a new `## [x.y.z] - YYYY-MM-DD` section and update the comparison links at the bottom.
3. Commit the changes, then run the release script:

   ```bash
   scripts/release.sh             # Builds and notarizes into build/release only.
   scripts/release.sh --publish   # Also tags vX.Y.Z, pushes the tag, and creates the release.
   ```

   The script defaults to a notarytool keychain profile named `tubeline-notary`. Jeff's release Mac currently uses the existing team profile `syntaxlook-notary`; run `TUBELINE_NOTARY_PROFILE=syntaxlook-notary scripts/release.sh --publish` there. To use another stored profile for the same team, set `TUBELINE_NOTARY_PROFILE`.

## What the Script Checks

Before notarizing, the script confirms that the tests pass and that the exported app:

- Is signed with the Tent Studios Developer ID and has the hardened runtime enabled
- Keeps its sandbox entitlement and has no `get-task-allow` entitlement
- Is built for Apple silicon only and matches the version number
- Has no leftover `CFBundleIconFile` key, which causes App Store validation error 90236
- Includes the copyright, graphics-design category, explicit encryption declaration, and a parseable privacy manifest

After notarization, it staples the app and the DMG and confirms that Gatekeeper accepts both. It also runs the signed command-line tool once before notarizing it.

## Releasing from CI

When a `v*.*.*` tag is pushed, `.github/workflows/release.yml` runs the same script and uploads the files to the release. It needs the signing secrets listed at the top of that file. Until those secrets are added, the workflow skips its steps and leaves a notice, so releases published from a Mac don't show a failed run.

## App Icon

Tubeline renders the icon's glyph itself, from `marketing/icon/glyph.svg`, by running `scripts/render-icon.sh`. The gradient, shadow, and glass settings live in `app/Tubeline/Resources/AppIcon.icon`, which you can edit in Icon Composer. Don't use SF Symbols in the icon; Apple's license doesn't allow it.
