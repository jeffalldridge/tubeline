# Fill Extrusion Regression

## Cause and Behavior

The parser treated shapes with no declared fill or stroke as centerlines with a 1-unit stroke. Illustrator and other exporters can omit the default black fill, so filled artwork could become an outline tube. A declared zero-width stroke also left `FillRegion.strokeWidth` set to zero, selecting the outlined-slab path instead of extrusion.

SVG defines black as the initial fill and none as the initial stroke. See the [W3C painting specification](https://www.w3.org/TR/SVG/painting.html#SpecifyingFillPaint). The parser now honors that default fill for shapes without stroke paint, including inherited and CSS `stroke:none`. It never invents a stroke. Explicit fill and opacity declarations remain respected. A stroke must have positive width and visible opacity before it changes the fill profile.

For compatibility, an explicitly stroked line icon that omits `fill="none"` still has no implicit fill. It must declare a fill to include both. Shapes that actually declare a visible stroke retain their outline tube. This is an intentional line-icon policy, not full SVG paint conformance.

## Verification

Five new regression tests failed against the previous parser. The updated standalone engine suite passed forty-nine tests, and the app-hosted suite passed seventy-four. Coverage includes unstyled paths, rectangles, circles, explicit no-stroke paint, hidden fills, mixed Illustrator-style CSS classes, compound fill contours, and zero-width strokes. The mesh regression compares fill-only output exactly against an explicit-fill control and checks watertightness, artwork bounds, and the requested extrusion depth with a large tube-thickness setting.

An original compound square fixture with a square hole reproduced the visual failure. Before the fix, both contours became thin tubes: 4,276 triangles and 0.04 cm depth. After the fix, the filled region extruded with its hole intact: 10,812 triangles and 0.14 cm depth at the default 4 pt setting. The silhouette no longer grows by an invented stroke. The corrected USDZ passed `usdchecker --arkit`. The fixture used the denser validated extraction path and reported its existing mesh-density warning.

The before and after PNGs and USDZ files remain in `/tmp/tubeline-fill-fix`; these are local verification artifacts. This change does not alter the published 0.2.0 release. Motion import of this follow-up still needs user acceptance.
