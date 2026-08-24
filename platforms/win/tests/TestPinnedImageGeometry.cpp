#include "pin/PinnedImageGeometry.h"
#include "pin/PinnedImageShadow.h"
#include "pin/PinnedImageHost.h"
#include "fullscreen/FullScreenCapturePreviewHost.h"

#include <cstdlib>
#include <iostream>
#include <set>
#include <cstring>
#include <string_view>

namespace {

using xxsnap::win::PinnedImageSize;
using xxsnap::win::fittedPinnedImageSize;
using xxsnap::win::fullScreenPreviewRect;
using xxsnap::win::initialPinnedImageRect;
using xxsnap::win::pinnedImageShadowPixel;
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

BOOL CALLBACK findCurrentProcessPinnedImage(HWND window, LPARAM result)
{
    DWORD processId = 0U;
    GetWindowThreadProcessId(window, &processId);
    if (processId != GetCurrentProcessId()) return TRUE;
    wchar_t className[64]{};
    if (GetClassNameW(window, className,
            static_cast<int>(sizeof(className) / sizeof(className[0]))) > 0
        && std::wstring_view(className) == L"XxSnapPinnedImageWindow") {
        *reinterpret_cast<HWND*>(result) = window;
        return FALSE;
    }
    return TRUE;
}

HWND currentProcessPinnedImageWindow()
{
    HWND result = nullptr;
    EnumWindows(findCurrentProcessPinnedImage,
        reinterpret_cast<LPARAM>(&result));
    return result;
}

bool processWindowStationIsVisible()
{
    USEROBJECTFLAGS flags{};
    DWORD length = 0U;
    return GetUserObjectInformationW(GetProcessWindowStation(), UOI_FLAGS,
               &flags, sizeof(flags), &length) != FALSE
        && (flags.dwFlags & WSF_VISIBLE) != 0U;
}

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

void testFullScreenPreviewMatchesMacBottomRightPlacement()
{
    const auto wide = fullScreenPreviewRect(2'000, 1'000, {0, 0, 1'000, 800});
    CHECK(wide.width == 320);
    CHECK(wide.height == 160);
    CHECK(wide.x == 660);
    CHECK(wide.y == 620);

    const auto tall = fullScreenPreviewRect(1'000, 2'000, {-500, 40, 900, 700});
    CHECK(tall.width == 110);
    CHECK(tall.height == 220);
    CHECK(tall.x == 270);
    CHECK(tall.y == 500);
}

void testPinnedImageShadowFadesSmoothlyWithoutBlueRings()
{
    const snipory::core::portable::PixelRect image{18, 18, 160, 90};
    std::set<std::uint8_t> alphaValues;
    std::uint8_t previousAlpha = 255U;
    for (std::int64_t distance = 1; distance <= 18; ++distance) {
        const auto pixel = pinnedImageShadowPixel(
            {image.x - distance, image.y + image.height / 2}, image);
        CHECK(pixel.alpha > 0U);
        CHECK(pixel.alpha <= previousAlpha);
        CHECK(pixel.blue > pixel.green);
        CHECK(pixel.green > pixel.red);
        CHECK(pixel.blue <= pixel.alpha);
        alphaValues.insert(pixel.alpha);
        previousAlpha = pixel.alpha;
    }
    CHECK(alphaValues.size() >= 12U);
}

void testPinnedImageCreatesAVisibleInteractiveWindow()
{
    snipory::core::portable::MemoryBudget budget(2U * 1024U * 1024U);
    auto allocation = snipory::core::portable::PixelBuffer::allocate(
        160, 90, budget);
    CHECK(allocation.value != nullptr);
    if (!allocation.value) return;
    std::memset(allocation.value->data(), 0xFF, allocation.value->byteCount());

    xxsnap::win::PinnedImageHost host(GetModuleHandleW(nullptr), nullptr);
    CHECK(host.pin(std::move(*allocation.value), {120, 120, 160, 90}));
    CHECK(host.count() == 1U);
    const auto window = currentProcessPinnedImageWindow();
    CHECK(window != nullptr);
    if (window == nullptr) return;
    if (processWindowStationIsVisible()) {
        CHECK(IsWindowVisible(window) != FALSE);
    }
    RECT before{};
    RECT after{};
    CHECK(GetWindowRect(window, &before) != FALSE);
    SendMessageW(window, WM_MOUSEWHEEL, MAKEWPARAM(0, WHEEL_DELTA), 0);
    CHECK(GetWindowRect(window, &after) != FALSE);
    CHECK(after.right - after.left > before.right - before.left);
    CHECK(after.bottom - after.top > before.bottom - before.top);
    DestroyWindow(window);
    CHECK(host.count() == 0U);
}

} // namespace

int main()
{
    testMacSizingContract();
    testInitialPlacementUsesSourceOrCentersFittedLongImage();
    testFullScreenPreviewMatchesMacBottomRightPlacement();
    testPinnedImageShadowFadesSmoothlyWithoutBlueRings();
    testPinnedImageCreatesAVisibleInteractiveWindow();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
