#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
crosshair="$source_root/platforms/win/resources/cursors/xxsnap-crosshair.cur"
rotation="$source_root/platforms/win/resources/cursors/xxsnap-rotation.cur"

if ! command -v magick >/dev/null 2>&1; then
    echo "ImageMagick is required to verify Windows cursor assets." >&2
    exit 1
fi

if [ ! -f "$crosshair" ]; then
    echo "Windows crosshair cursor is missing: $crosshair" >&2
    exit 1
fi

dimensions=$(magick identify -format '%wx%h' "$crosshair")
if [ "$dimensions" != "32x32" ]; then
    echo "Windows crosshair canvas must be 32x32 to prevent Win32 from enlarging the macOS glyph; got $dimensions." >&2
    exit 1
fi

hotspot=$(od -An -tu1 -j10 -N4 "$crosshair" | xargs)
if [ "$hotspot" != "15 0 15 0" ]; then
    echo "Windows crosshair hotspot must preserve the centered macOS hotspot at (15,15); got $hotspot." >&2
    exit 1
fi

visible_bounds=$(magick identify -format '%@' "$crosshair")
if [ "$visible_bounds" != "15x15+8+9" ]; then
    echo "Windows crosshair visible glyph must remain the macOS-sized 15x15 image; got $visible_bounds." >&2
    exit 1
fi

echo "Windows crosshair keeps the 15x15 macOS glyph without Win32 enlargement."

if [ ! -f "$rotation" ]; then
    echo "Windows rotation cursor is missing: $rotation" >&2
    exit 1
fi

rotation_dimensions=$(magick identify -format '%wx%h' "$rotation")
if [ "$rotation_dimensions" != "32x32" ]; then
    echo "Windows rotation cursor canvas must be 32x32 to prevent Win32 enlargement; got $rotation_dimensions." >&2
    exit 1
fi

rotation_hotspot=$(od -An -tu1 -j10 -N4 "$rotation" | xargs)
if [ "$rotation_hotspot" != "16 0 16 0" ]; then
    echo "Windows rotation hotspot must remain centered at (16,16); got $rotation_hotspot." >&2
    exit 1
fi

rotation_visible_bounds=$(magick identify -format '%@' "$rotation")
if [ "$rotation_visible_bounds" != "14x14+9+9" ]; then
    echo "Windows rotation visible glyph must remain the macOS-sized 14x14 image; got $rotation_visible_bounds." >&2
    exit 1
fi

echo "Windows rotation cursor keeps the macOS glyph without Win32 enlargement."
