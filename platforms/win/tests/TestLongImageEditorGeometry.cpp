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
} // namespace

int main()
{
    testNarrowCaptureUsesImageWidthWithoutBlankMargins();
    testScrollOffsetClampsAndMapsToFullImageCoordinates();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
