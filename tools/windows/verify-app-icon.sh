#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
source_icon="$source_root/platforms/mac/Resources/Icons/xxsnap.png"
windows_icon="$source_root/platforms/win/resources/icons/Snipory.ico"
expected_sizes="256 128 96 64 48 32 24 16"

if ! command -v magick >/dev/null 2>&1; then
    echo "ImageMagick is required to verify the Windows app icon." >&2
    exit 1
fi

actual_sizes=$(magick identify -format '%w ' "$windows_icon")
if [ "$actual_sizes" != "$expected_sizes " ]; then
    echo "Unexpected Windows app icon sizes: $actual_sizes" >&2
    exit 1
fi

temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT HUP INT TERM

frame_index=0
for size in $expected_sizes; do
    expected="$temporary_dir/expected-$size.png"
    actual="$temporary_dir/actual-$size.png"
    magick "$source_icon" -resize "${size}x${size}" "$expected"
    magick "$windows_icon[$frame_index]" "$actual"
    if ! magick compare -metric AE "$expected" "$actual" null: 2>/dev/null; then
        echo "Windows app icon frame ${size}x${size} does not match the macOS app icon." >&2
        exit 1
    fi
    frame_index=$((frame_index + 1))
done

echo "Windows app icon matches the macOS source at all 8 sizes."
