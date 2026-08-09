#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ICON="$PROJECT_DIR/LittleSpud/Assets.xcassets/AppIcon.appiconset/LittleSpudIcon-Light.png"
RES_DIR="$PROJECT_DIR/android/app/src/main/res"
STORE_DIR="$PROJECT_DIR/android/store-assets"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Missing iOS source icon: $SOURCE_ICON" >&2
  exit 1
fi

densities=(mdpi hdpi xhdpi xxhdpi xxxhdpi)
legacy_sizes=(48 72 96 144 192)
adaptive_sizes=(108 162 216 324 432)

for index in "${!densities[@]}"; do
  output_dir="$RES_DIR/mipmap-${densities[$index]}"
  mkdir -p "$output_dir"
  sips --resampleHeightWidth "${legacy_sizes[$index]}" "${legacy_sizes[$index]}" \
    "$SOURCE_ICON" --out "$output_dir/ic_launcher.png" >/dev/null
  cp "$output_dir/ic_launcher.png" "$output_dir/ic_launcher_round.png"
  sips --resampleHeightWidth "${adaptive_sizes[$index]}" "${adaptive_sizes[$index]}" \
    "$SOURCE_ICON" --out "$output_dir/ic_launcher_foreground.png" >/dev/null
done

mkdir -p "$STORE_DIR"
sips --resampleHeightWidth 512 512 "$SOURCE_ICON" \
  --out "$STORE_DIR/little-spud-play-icon-512.png" >/dev/null

echo "Generated Android launcher icons and $STORE_DIR/little-spud-play-icon-512.png"
