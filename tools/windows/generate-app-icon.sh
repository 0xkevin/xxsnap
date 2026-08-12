#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
source_icon="$source_root/platforms/mac/Resources/Icons/xxsnap.png"
windows_icon="$source_root/platforms/win/resources/icons/Snipory.ico"

if ! command -v magick >/dev/null 2>&1; then
    echo "ImageMagick is required to generate the Windows app icon." >&2
    exit 1
fi

magick "$source_icon" \
    -define icon:auto-resize=256,128,96,64,48,32,24,16 \
    "$windows_icon"

echo "Generated Windows app icon from platforms/mac/Resources/Icons/xxsnap.png."
