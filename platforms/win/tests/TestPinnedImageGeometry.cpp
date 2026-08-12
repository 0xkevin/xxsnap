#include "pin/PinnedImageGeometry.h"

#include <cstdlib>
#include <iostream>

namespace {

using xxsnap::win::PinnedImageSize;
using xxsnap::win::fittedPinnedImageSize;
using xxsnap::win::initialPinnedImageRect;
using xxsnap::win::scaledPinnedImageSize;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": "
                  << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

void testMacSizingContract()
{
    const snipory::core::portable::PixelRect visible{0, 0, 1'000, 800};
    CHECK(fittedPinnedImageSize({2'000, 1'000}, visible).width == 800);
    CHECK(fittedPinnedImageSize({2'000, 1'000}, visible).height == 400);
    const auto tiny = fittedPinnedImageSize({12, 6}, visible);
    CHECK(tiny.width == 96);
    CHECK(tiny.height == 48);

    const auto enlarged = scaledPinnedImageSize(
        {200, 100}, 2.0, 1.5, visible);
    CHECK(enlarged.width == 300);
    CHECK(enlarged.height == 150);
    const auto minimum = scaledPinnedImageSize(
        {200, 100}, 2.0, 0.1, visible);
    CHECK(minimum.width == 96);
    CHECK(minimum.height == 48);
}

void testInitialPlacementUsesSourceOrCentersFittedLongImage()
{
    const snipory::core::portable::PixelRect visible{0, 0, 1'000, 800};
    const auto source = initialPinnedImageRect(
        {160, 90}, {120, 220, 160, 90}, visible);
    CHECK(source.x == 120 && source.y == 220);
    CHECK(source.width == 160 && source.height == 90);

    const auto longImage = initialPinnedImageRect(
        {400, 4'000}, {120, 100, 400, 4'000}, visible);
    CHECK(longImage.width == 56);
    CHECK(longImage.height == 560);
    CHECK(longImage.x == 472);
    CHECK(longImage.y == 120);
}

} // namespace

int main()
{
    testMacSizingContract();
    testInitialPlacementUsesSourceOrCentersFittedLongImage();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
