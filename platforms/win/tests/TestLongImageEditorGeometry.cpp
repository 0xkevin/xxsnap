#include "scroll/LongImageEditorGeometry.h"

#include <cstdlib>
#include <iostream>

using namespace xxsnap::win;

namespace
{
int failureCount = 0;

#define CHECK(value)                                                                   \
    do {                                                                               \
        if (!(value)) {                                                                \
            std::cerr << __FILE__ << ':' << __LINE__ << " CHECK failed: " #value       \
                      << '\n';                                                         \
            ++failureCount;                                                            \
        }                                                                              \
    } while (false)

void testNarrowCaptureUsesImageWidthWithoutBlankMargins()
{
    const auto layout = longImageEditorLayout({0, 0, 1920, 1040}, 600, 5000, 96, 96);
    CHECK(layout.bounds.width == 1000);
    CHECK(layout.displayScale > 1.66 && layout.displayScale < 1.67);
    CHECK(layout.bounds.height > 0);
    CHECK(layout.visibleSourceHeight == 504);
    CHECK(layout.maximumSourceOffset == 5000 - layout.visibleSourceHeight);
}

void testScrollOffsetClampsAndMapsToFullImageCoordinates()
{
    const auto layout = longImageEditorLayout({100, 50, 1280, 720}, 500, 4000, 96, 96);
    CHECK(clampedLongImageOffset(-50, layout) == 0);
    CHECK(clampedLongImageOffset(9000, layout) == layout.maximumSourceOffset);
    CHECK(longImageAnnotationOrigin(321, 144).y == 214.0F);
}

void testPreviewMatchesImageAspectRatioAndClampsBesideSelection()
{
    const auto preview = longImagePreviewBounds(
        {0, 0, 1920, 1040}, {100, 100, 800, 600}, 600, 2400, 96, 96);
    CHECK(preview.width == 120);
    CHECK(preview.height == 480);
    CHECK(preview.x == 908);
    CHECK(preview.y == 100);

    const auto leftPreview = longImagePreviewBounds(
        {0, 0, 1280, 720}, {950, 50, 300, 500}, 300, 600, 96, 96);
    CHECK(leftPreview.width == 240);
    CHECK(leftPreview.height == 480);
    CHECK(leftPreview.x == 702);
    CHECK(leftPreview.y == 50);
}
} // namespace

int main()
{
    testNarrowCaptureUsesImageWidthWithoutBlankMargins();
    testScrollOffsetClampsAndMapsToFullImageCoordinates();
    testPreviewMatchesImageAspectRatioAndClampsBesideSelection();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
