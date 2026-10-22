#!/bin/zsh
# Renders the app icon's glyph layer with Tubeline itself: marketing/icon/glyph.svg becomes a
# shaded 3D tube on a transparent background, placed in the Icon Composer bundle
# (app/Tubeline/Resources/AppIcon.icon). Gradient, shadow and glass live in icon.json —
# edit those in Icon Composer.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
swift build -c release --product tubeline >/dev/null
.build/release/tubeline marketing/icon/glyph.svg -o "$OUT" --surface shaded --facets 64 \
  --png-transparent --png-size 1024
cp "$OUT/glyph.png" app/Tubeline/Resources/AppIcon.icon/Assets/tube.png
echo "Updated app/Tubeline/Resources/AppIcon.icon/Assets/tube.png"
