#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
crosshair="$source_root/platforms/win/resources/cursors/xxsnap-crosshair.cur"
rotation="$source_root/platforms/win/resources/cursors/xxsnap-rotation.cur"
eraser="$source_root/platforms/win/resources/cursors/xxsnap-eraser.cur"
eraser_light="$source_root/platforms/win/resources/cursors/xxsnap-eraser-light.cur"
brush="$source_root/platforms/win/resources/cursors/xxsnap-brush.cur"
brush_light="$source_root/platforms/win/resources/cursors/xxsnap-brush-light.cur"
eyedropper="$source_root/platforms/win/resources/cursors/xxsnap-eyedropper.cur"
eyedropper_light="$source_root/platforms/win/resources/cursors/xxsnap-eyedropper-light.cur"

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

for eraser_cursor in "$eraser" "$eraser_light"; do
    if ! eraser_geometry=$(magick identify -format '%wx%h|%@' "$eraser_cursor"); then
        echo "Unable to inspect Windows eraser cursor: $eraser_cursor" >&2
        exit 1
    fi
    eraser_dimensions=${eraser_geometry%%|*}
    eraser_visible_bounds=${eraser_geometry#*|}
    eraser_hotspot=$(od -An -tu1 -j10 -N4 "$eraser_cursor" | xargs)
    if [ "$eraser_dimensions" != "32x32" ] \
        || [ "$eraser_hotspot" != "11 0 21 0" ] \
        || [ "$eraser_visible_bounds" != "18x18+7+7" ]; then
        echo "Windows eraser cursor must preserve the 18px Mac glyph and translated (11,21) hotspot; got $eraser_dimensions, $eraser_hotspot, $eraser_visible_bounds." >&2
        exit 1
    fi
done

echo "Windows eraser cursor variants keep the 18px macOS glyph without Win32 enlargement."

eraser_alpha=$(magick "$eraser" -alpha extract -format '%#' info:)
eraser_light_alpha=$(magick "$eraser_light" -alpha extract -format '%#' info:)
eraser_tip_color=$(magick "$eraser" \
    -format '%[fx:p{11,21}.r] %[fx:p{11,21}.g] %[fx:p{11,21}.b]' info:)
eraser_light_tip_color=$(magick "$eraser_light" \
    -format '%[fx:p{11,21}.r] %[fx:p{11,21}.g] %[fx:p{11,21}.b]' info:)
if [ "$eraser_alpha" != "$eraser_light_alpha" ] \
    || [ "$eraser_tip_color" != "0 0 0" ] \
    || [ "$eraser_light_tip_color" != "1 1 1" ]; then
    echo "Windows eraser cursor variants must share an alpha mask and use dark/light foreground colors; got $eraser_tip_color and $eraser_light_tip_color." >&2
    exit 1
fi

echo "Windows eraser cursor variants preserve matching dark/light contrast masks."

eraser_orientation=$(magick "$eraser" \
    -format '%[fx:p{11,21}.a] %[fx:p{11,8}.a]' info:)
eraser_tip_alpha=${eraser_orientation%% *}
eraser_opposite_alpha=${eraser_orientation#* }
if [ "$eraser_tip_alpha" = "0" ] || [ "$eraser_opposite_alpha" != "0" ]; then
    echo "Windows eraser glyph must point down toward the (11,21) hotspot; alpha tip/opposite were $eraser_tip_alpha/$eraser_opposite_alpha." >&2
    exit 1
fi

echo "Windows eraser cursor points down toward its macOS hotspot."

if [ ! -f "$brush" ]; then
    echo "Windows brush cursor is missing: $brush" >&2
    exit 1
fi

brush_dimensions=$(magick identify -format '%wx%h' "$brush")
brush_hotspot=$(od -An -tu1 -j10 -N4 "$brush" | xargs)
brush_visible_bounds=$(magick identify -format '%@' "$brush")
if [ "$brush_dimensions" != "32x32" ] \
    || [ "$brush_hotspot" != "10 0 22 0" ] \
    || [ "$brush_visible_bounds" != "18x18+7+7" ]; then
    echo "Windows brush cursor must preserve the 18px project pencil and translated (10,22) hotspot; got $brush_dimensions, $brush_hotspot, $brush_visible_bounds." >&2
    exit 1
fi

echo "Windows brush cursor keeps the 18px project pencil with its tip hotspot."

brush_orientation=$(magick "$brush" \
    -format '%[fx:p{10,22}.a] %[fx:p{10,8}.a]' info:)
brush_tip_alpha=${brush_orientation%% *}
brush_opposite_alpha=${brush_orientation#* }
if [ "$brush_tip_alpha" = "0" ] || [ "$brush_opposite_alpha" != "0" ]; then
    echo "Windows brush glyph must point down toward the (10,22) hotspot; alpha tip/opposite were $brush_tip_alpha/$brush_opposite_alpha." >&2
    exit 1
fi

echo "Windows brush cursor points down toward its pencil-tip hotspot."

for brush_cursor in "$brush" "$brush_light"; do
    brush_dimensions=$(magick identify -format '%wx%h' "$brush_cursor")
    brush_hotspot=$(od -An -tu1 -j10 -N4 "$brush_cursor" | xargs)
    brush_visible_bounds=$(magick identify -format '%@' "$brush_cursor")
    if [ "$brush_dimensions" != "32x32" ] \
        || [ "$brush_hotspot" != "10 0 22 0" ] \
        || [ "$brush_visible_bounds" != "18x18+7+7" ]; then
        echo "Windows brush cursor variants must share the project pencil dimensions, bounds, and hotspot; got $brush_cursor: $brush_dimensions, $brush_hotspot, $brush_visible_bounds." >&2
        exit 1
    fi
done

if ! cmp -s "$brush" "$brush_light"; then
    echo "Windows brush cursor variants must use the same black-outline white pencil on every background." >&2
    exit 1
fi

for cursor_name in \
    move move-light \
    resize-left-right resize-left-right-light \
    resize-up-down resize-up-down-light \
    resize-top-left-bottom-right resize-top-left-bottom-right-light \
    resize-top-right-bottom-left resize-top-right-bottom-left-light; do
    cursor="$source_root/platforms/win/resources/cursors/xxsnap-$cursor_name.cur"
    if [ ! -f "$cursor" ]; then
        echo "Windows background-aware cursor is missing: $cursor" >&2
        exit 1
    fi
    dimensions=$(magick identify -format '%wx%h' "$cursor")
    hotspot=$(od -An -tu1 -j10 -N4 "$cursor" | xargs)
    if [ "$dimensions" != "32x32" ] || [ "$hotspot" != "16 0 16 0" ]; then
        echo "Windows background-aware cursor must use a 32x32 Mac canvas and centered hotspot; got $cursor_name: $dimensions, $hotspot." >&2
        exit 1
    fi
done

echo "Windows move and resize cursors provide matching dark/light Mac variants."

for eyedropper_cursor in "$eyedropper" "$eyedropper_light"; do
    if [ ! -f "$eyedropper_cursor" ]; then
        echo "Windows eyedropper cursor is missing: $eyedropper_cursor" >&2
        exit 1
    fi
    eyedropper_dimensions=$(magick identify -format '%wx%h' "$eyedropper_cursor")
    eyedropper_hotspot=$(od -An -tu1 -j10 -N4 "$eyedropper_cursor" | xargs)
    eyedropper_visible_bounds=$(magick identify -format '%@' "$eyedropper_cursor")
    if [ "$eyedropper_dimensions" != "32x32" ] \
        || [ "$eyedropper_hotspot" != "7 0 24 0" ] \
        || [ "$eyedropper_visible_bounds" != "18x18+7+7" ]; then
        echo "Windows eyedropper cursor must preserve the 18px Mac glyph and translated (7,24) hotspot; got $eyedropper_dimensions, $eyedropper_hotspot, $eyedropper_visible_bounds." >&2
        exit 1
    fi
done

eyedropper_orientation=$(magick "$eyedropper_light" \
    -format '%[fx:p{7,24}.a] %[fx:p{7,7}.a]' info:)
eyedropper_tip_alpha=${eyedropper_orientation%% *}
eyedropper_opposite_alpha=${eyedropper_orientation#* }
if [ "$eyedropper_tip_alpha" = "0" ] || [ "$eyedropper_opposite_alpha" != "0" ]; then
    echo "Windows eyedropper glyph must point down toward the (7,24) hotspot; alpha tip/opposite were $eyedropper_tip_alpha/$eyedropper_opposite_alpha." >&2
    exit 1
fi

echo "Windows eyedropper cursor points down toward its macOS hotspot."
