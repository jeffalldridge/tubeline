# Fill Extrusion Regression

## Cause and Behavior

The parser treated shapes with no declared fill or stroke as centerlines with a 1-unit stroke. Illustrator and other exporters can omit the default black fill, so filled artwork could become an outline tube. A declared zero-width stroke also left `FillRegion.strokeWidth` set to zero, selecting the outlined-slab path instead of extrusion.

SVG defines black as the initial fill and none as the initial stroke. See the [W3C painting specification](https://www.w3.org/TR/SVG/painting.html#SpecifyingFillPaint). The parser now honors that default fill for shapes without stroke paint, including inherited and CSS `stroke:none`. It never invents a stroke. Explicit fill and opacity declarations remain respected. A stroke must have positive width and visible opacity before it changes the fill profile.

For compatibility, an explicitly stroked line icon that omits `fill="none"` still has no implicit fill. It must declare a fill to include both. Shapes that actually declare a visible stroke retain their outline tube. This is an intentional line-icon policy, not full SVG paint conformance.

## Verification

Five new regression tests failed against the previous parser. The updated standalone engine suite passed forty-nine tests, and the app-hosted suite passed seventy-four. Coverage includes unstyled paths, rectangles, circles, explicit no-stroke paint, hidden fills, mixed Illustrator-style CSS classes, compound fill contours, and zero-width strokes. The mesh regression compares fill-only output exactly against an explicit-fill control and checks watertightness, artwork bounds, and the requested extrusion depth with a large tube-thickness setting.

An original compound square fixture with a square hole reproduced the visual failure. Before the fix, both contours became thin tubes: 4,276 triangles and 0.04 cm depth. After the fix, the filled region extruded with its hole intact: 10,812 triangles and 0.14 cm depth at the default 4 pt setting. The silhouette no longer grows by an invented stroke. The corrected USDZ passed `usdchecker --arkit`. The native app also previewed the corrected filled region and hole, displayed 10,812 triangles, and exported successfully. That app-exported USDZ passed `usdchecker --arkit` too. The fixture used the denser validated extraction path and reported its existing mesh-density warning.

The before and after PNGs and USDZ files remain in `/tmp/tubeline-fill-fix`; these are local verification artifacts. This change does not alter the published 0.2.0 release. Motion import of this follow-up still needs user acceptance.

The complete 162-SVG corpus passed strict mesh validation. Of those outputs, 158 matched the release baseline exactly in triangle count, geometry/index hash, normal hash, and warning count. Four changed as intended: their mixed artwork contains unstyled filled lettering that the old parser converted into tubes. These corrected outputs remained valid; their triangle counts increased because the filled glyphs now have the requested extrusion depth. Private input paths and derived renders remain outside Git. Evidence is in `/tmp/tubeline-fill-fix/corpus-digests.log`, compared with `/tmp/tubeline-geometry-audit/baseline-all-digests.log`.

[GitHub CI run 39869360713](https://github.com/jeffalldridge/tubeline/actions/runs/39869360713) passed on code commit `c0a8822`, including engine and app tests, CLI output safety, sample conversion, and USDZ validation.

## Proposed Session Memory Entry

Fixed default-fill inference and zero-width stroke classification without changing explicitly stroked line art. Forty-nine core tests and seventy-four app tests passed; native preview/export and USDZ validation passed. All 162 corpus outputs remained valid, with 158 exactly unchanged and four corrected mixed fill/stroke icons. The fix is on the development branch; the published 0.2.0 build is unchanged.
