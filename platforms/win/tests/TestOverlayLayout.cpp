#include "overlay/OverlayRenderer.h"
#include "overlay/OverlayWindow.h"
#include "overlay/VisualStyleCatalog.h"
#include "resource.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

namespace {

using snipory::core::portable::PixelRect;
using xxsnap::win::DipRect;
using xxsnap::win::DpiRestartDecision;
using xxsnap::win::DpiRestartResult;
using xxsnap::win::DpiRestartState;
using xxsnap::win::MvpToolbarAction;
using xxsnap::win::OverlayLayout;
using xxsnap::win::OverlayLayoutInput;
using xxsnap::win::Rgba8;
using xxsnap::win::VisualStyleCatalog;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

bool close(float lhs, float rhs) noexcept
{
    return std::fabs(lhs - rhs) < 0.001F;
}

float rectRight(DipRect rect) noexcept
{
    return rect.x + rect.width;
}

float rectBottom(DipRect rect) noexcept
{
    return rect.y + rect.height;
}

bool intersects(DipRect lhs, DipRect rhs) noexcept
{
    return lhs.x < rectRight(rhs)
        && rectRight(lhs) > rhs.x
        && lhs.y < rectBottom(rhs)
        && rectBottom(lhs) > rhs.y;
}

std::int64_t scaledPhysicalPixels(std::int64_t dips, std::uint32_t dpi) noexcept
{
    return dips * static_cast<std::int64_t>(dpi) / 96;
}

BOOL CALLBACK collectIntegerResourceName(
    HMODULE,
    LPCWSTR,
    LPWSTR name,
    LONG_PTR context)
{
    auto& resourceIds = *reinterpret_cast<std::vector<int>*>(context);
    resourceIds.push_back(IS_INTRESOURCE(name)
            ? static_cast<int>(reinterpret_cast<ULONG_PTR>(name))
            : -1);
    return TRUE;
}

void checkRect(DipRect actual, DipRect expected, int line)
{
    if (!close(actual.x, expected.x)
        || !close(actual.y, expected.y)
        || !close(actual.width, expected.width)
        || !close(actual.height, expected.height)) {
        std::cerr << "CHECK rect failed at line " << line << ": actual=["
                  << actual.x << ',' << actual.y << ',' << actual.width << ','
                  << actual.height << "] expected=[" << expected.x << ','
                  << expected.y << ',' << expected.width << ',' << expected.height
                  << "]\n";
        ++failureCount;
    }
}

#define CHECK_RECT(actual, expected) checkRect((actual), (expected), __LINE__)

std::vector<Rgba8> makeDeterministicGrid(std::size_t width, std::size_t height)
{
    constexpr std::array palette{
        Rgba8{232, 83, 120, 255},
        Rgba8{83, 120, 232, 255},
        Rgba8{83, 200, 145, 255},
        Rgba8{240, 190, 70, 255},
    };
    std::vector<Rgba8> pixels(width * height);
    for (std::size_t y = 0; y < height; ++y) {
        for (std::size_t x = 0; x < width; ++x) {
            const auto column = x / 40U;
            const auto row = y / 40U;
            pixels[y * width + x] = palette[(column + row) % palette.size()];
        }
    }
    return pixels;
}

OverlayLayout fixedLayout(std::uint32_t dpi)
{
    return xxsnap::win::computeOverlayLayout({
        PixelRect{0, 0, 640, 360},
        PixelRect{160, 90, 320, 180},
        dpi,
        dpi,
        80.0F,
    });
}

void testDeterministicManifest()
{
    const auto grid = makeDeterministicGrid(640U, 360U);
    CHECK(grid.size() == 640U * 360U);
    CHECK((grid[0] == Rgba8{232, 83, 120, 255}));
    CHECK((grid[40] == Rgba8{83, 120, 232, 255}));

    const auto layout = fixedLayout(96U);
    CHECK_RECT(layout.overlayBounds, (DipRect{0, 0, 640, 360}));
    CHECK_RECT(layout.border, (DipRect{160, 90, 320, 180}));
    CHECK_RECT(layout.sizeLabel, (DipRect{160, 58, 98, 24}));
    CHECK_RECT(layout.toolbar, (DipRect{336, 278, 144, 28}));
    CHECK_RECT(layout.cancel, (DipRect{368, 282, 20, 20}));
    CHECK_RECT(layout.save, (DipRect{396, 282, 20, 20}));
    CHECK_RECT(layout.copy, (DipRect{424, 282, 20, 20}));
    CHECK(layout.sizeLabelText == L"320 x 180  px");

    const std::string expected =
        "{\"mask\":[[0,0,640,90],[0,90,160,180],[480,90,160,180],[0,270,640,90]],"
        "\"border\":[160,90,320,180],\"sizeLabel\":[160,58,98,24],"
        "\"toolbar\":[336,278,144,28],\"cancel\":[368,282,20,20],"
        "\"save\":[396,282,20,20],\"copy\":[424,282,20,20],"
        "\"handles\":[[155,85,10,10],[315,85,10,10],[475,85,10,10],"
        "[155,175,10,10],[475,175,10,10],[155,265,10,10],"
        "[315,265,10,10],[475,265,10,10]]}";
    const auto manifest = xxsnap::win::overlayLayoutManifestJson(layout);
    CHECK(manifest == expected);
    std::cout << manifest << '\n';
}

void testDpiScaling()
{
    constexpr std::array dpis{96U, 120U, 144U, 192U};
    for (const auto dpi : dpis) {
        const auto layout = fixedLayout(dpi);
        CHECK(close(layout.toolbar.width, 144.0F));
        CHECK(close(layout.toolbar.height, 28.0F));
        CHECK(close(layout.cancel.width, 20.0F));
        CHECK(
            xxsnap::win::dipLengthToPhysicalPixels(layout.toolbar.width, dpi)
            == static_cast<std::int64_t>(144U * dpi / 96U));
        CHECK(
            xxsnap::win::dipLengthToPhysicalPixels(layout.cancel.width, dpi)
            == static_cast<std::int64_t>(20U * dpi / 96U));
        CHECK(layout.cancel.x < layout.save.x);
        CHECK(layout.save.x < layout.copy.x);
    }
}

void testEdgePlacementAndClamping()
{
    const OverlayLayout nearBottom = xxsnap::win::computeOverlayLayout({
        PixelRect{0, 0, 640, 360}, PixelRect{400, 330, 220, 24}, 96, 96, 80.0F});
    CHECK(nearBottom.toolbar.y + nearBottom.toolbar.height < nearBottom.border.y);

    const OverlayLayout nearTop = xxsnap::win::computeOverlayLayout({
        PixelRect{0, 0, 640, 360}, PixelRect{0, 2, 80, 20}, 96, 96, 72.0F});
    CHECK_RECT(nearTop.toolbar, (DipRect{88, 10, 144, 28}));
    CHECK(!intersects(nearTop.toolbar, nearTop.border));

    const OverlayLayout nearRight = xxsnap::win::computeOverlayLayout({
        PixelRect{0, 0, 640, 360}, PixelRect{620, 100, 20, 80}, 96, 96, 72.0F});
    CHECK(nearRight.toolbar.x >= 8.0F);
    CHECK(nearRight.toolbar.x + nearRight.toolbar.width <= 632.0F);

    const OverlayLayout tiny = xxsnap::win::computeOverlayLayout({
        PixelRect{-320, -180, 640, 360}, PixelRect{-320, -180, 1, 1}, 96, 96, 30.0F});
    const auto inside = [&tiny](DipRect rect) {
        return rect.x >= tiny.overlayBounds.x
            && rect.y >= tiny.overlayBounds.y
            && rect.x + rect.width <= tiny.overlayBounds.x + tiny.overlayBounds.width
            && rect.y + rect.height <= tiny.overlayBounds.y + tiny.overlayBounds.height;
    };
    CHECK(inside(tiny.sizeLabel));
    CHECK(inside(tiny.toolbar));
    CHECK(inside(tiny.cancel));
    CHECK(inside(tiny.save));
    CHECK(inside(tiny.copy));
    CHECK_RECT(tiny.border, (DipRect{0, 0, 1, 1}));
    CHECK_RECT(tiny.handles[0], (DipRect{-5, -5, 10, 10}));
}

void testCrossDisplaySelectionChromeOwnership()
{
    const PixelRect selection{500, 80, 300, 200};
    const auto left = xxsnap::win::computeOverlayLayout({
        PixelRect{0, 0, 640, 360}, selection, 96, 96, 80.0F, true});
    const auto right = xxsnap::win::computeOverlayLayout({
        PixelRect{640, 0, 640, 360}, selection, 96, 96, 80.0F, false});

    CHECK_RECT(left.border, (DipRect{500, 80, 300, 200}));
    CHECK_RECT(right.border, (DipRect{-140, 80, 300, 200}));
    CHECK(rectRight(left.border) > left.overlayBounds.width);
    CHECK(right.border.x < right.overlayBounds.x);
    CHECK(!close(rectRight(left.border), left.overlayBounds.width));
    CHECK(!close(right.border.x, right.overlayBounds.x));
    CHECK(left.border.x > left.overlayBounds.x);
    CHECK(rectRight(right.border) < right.overlayBounds.width);
    CHECK_RECT(left.handles[0], (DipRect{495, 75, 10, 10}));
    CHECK_RECT(right.handles[2], (DipRect{155, 75, 10, 10}));
    CHECK(left.handles[2].x > left.overlayBounds.width);
    CHECK(rectRight(right.handles[0]) < right.overlayBounds.x);

    CHECK_RECT(left.mask[1], (DipRect{0, 80, 500, 200}));
    CHECK_RECT(left.mask[2], (DipRect{640, 80, 0, 200}));
    CHECK_RECT(right.mask[1], (DipRect{0, 80, 0, 200}));
    CHECK_RECT(right.mask[2], (DipRect{160, 80, 480, 200}));

    CHECK(left.showActions);
    CHECK(!right.showActions);
    CHECK(left.sizeLabel.width > 0.0F);
    CHECK(left.toolbar.width == VisualStyleCatalog::mvpToolbarWidthDip);
    CHECK_RECT(right.sizeLabel, (DipRect{}));
    CHECK_RECT(right.toolbar, (DipRect{}));
    CHECK_RECT(right.cancel, (DipRect{}));
    CHECK_RECT(right.save, (DipRect{}));
    CHECK_RECT(right.copy, (DipRect{}));
}

void testMacToolbarSideCandidatesAtEveryDpi()
{
    constexpr std::array dpis{96U, 120U, 144U, 192U};
    for (const auto dpi : dpis) {
        const auto px = [dpi](std::int64_t dips) {
            return scaledPhysicalPixels(dips, dpi);
        };
        const PixelRect display{0, 0, px(800), px(600)};

        const auto rightSide = xxsnap::win::computeOverlayLayout({
            display,
            PixelRect{px(200), px(20), px(300), px(560)},
            dpi,
            dpi,
            80.0F,
            true,
        });
        CHECK_RECT(rightSide.toolbar, (DipRect{508, 544, 144, 28}));
        CHECK(!intersects(rightSide.toolbar, (DipRect{200, 20, 300, 560})));

        const auto leftSide = xxsnap::win::computeOverlayLayout({
            display,
            PixelRect{px(500), px(20), px(292), px(560)},
            dpi,
            dpi,
            80.0F,
            true,
        });
        CHECK_RECT(leftSide.toolbar, (DipRect{348, 544, 144, 28}));
        CHECK(!intersects(leftSide.toolbar, (DipRect{500, 20, 292, 560})));
    }
}

void testWindowAndResourceContracts()
{
    CHECK(xxsnap::win::overlayWindowStyle() == WS_POPUP);
    CHECK(
        xxsnap::win::overlayWindowExtendedStyle()
        == (WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE));

    constexpr auto resources = xxsnap::win::mvpOverlayButtonResources();
    static_assert(resources.size() == 3);
    CHECK(resources[0].action == MvpToolbarAction::cancel);
    CHECK(resources[0].resourceId == IDR_CANCEL_CAPTURE_PNG);
    CHECK(resources[1].action == MvpToolbarAction::save);
    CHECK(resources[1].resourceId == IDR_SAVE_TO_FILE_PNG);
    CHECK(resources[2].action == MvpToolbarAction::copy);
    CHECK(resources[2].resourceId == IDR_COPY_TO_CLIPBOARD_PNG);
}

void testDpiRestartNotificationIsSingleAndFailClosed()
{
    DpiRestartDecision success;
    int callbackCount = 0;
    auto nestedResult = DpiRestartResult::notified;
    CHECK(success.state() == DpiRestartState::waiting);
    CHECK(success.notify(WM_PAINT, [&callbackCount] {
        ++callbackCount;
    }) == DpiRestartResult::ignored);
    CHECK(callbackCount == 0);

    const auto successResult = success.notify(WM_DPICHANGED, [&] {
        ++callbackCount;
        CHECK(success.state() == DpiRestartState::notifying);
        nestedResult = success.notify(WM_DPICHANGED, [&callbackCount] {
            ++callbackCount;
        });
    });
    CHECK(successResult == DpiRestartResult::notified);
    CHECK(nestedResult == DpiRestartResult::ignored);
    CHECK(success.state() == DpiRestartState::notified);
    CHECK(callbackCount == 1);
    CHECK(success.notify(WM_DPICHANGED, [&callbackCount] {
        ++callbackCount;
    }) == DpiRestartResult::ignored);
    CHECK(callbackCount == 1);

    DpiRestartDecision throwing;
    CHECK(throwing.notify(WM_DPICHANGED, [] {
        throw 17;
    }) == DpiRestartResult::closeOverlay);
    CHECK(throwing.state() == DpiRestartState::failedClosed);
    CHECK(throwing.error().has_value());
    if (throwing.error().has_value()) {
        CHECK(
            throwing.error()->code
            == xxsnap::win::OverlayWindowErrorCode::dpiRestartCallbackFailed);
    }
    CHECK(throwing.notify(WM_DPICHANGED, [] {}) == DpiRestartResult::ignored);

    DpiRestartDecision missingCallback;
    CHECK(missingCallback.notify(WM_DPICHANGED, {})
        == DpiRestartResult::closeOverlay);
    CHECK(missingCallback.state() == DpiRestartState::failedClosed);

    auto selfDestroying = std::make_unique<DpiRestartDecision>();
    auto* decisionDuringNotification = selfDestroying.get();
    CHECK(decisionDuringNotification->notify(WM_DPICHANGED, [&selfDestroying] {
        selfDestroying.reset();
    }) == DpiRestartResult::notified);
    CHECK(selfDestroying == nullptr);
}

void testDirectWriteConfigurationFailuresAreExplicit()
{
    CHECK(!xxsnap::win::checkTextFormatConfigurationResult(S_OK).has_value());
    const auto failure = xxsnap::win::checkTextFormatConfigurationResult(E_INVALIDARG);
    CHECK(failure.has_value());
    if (failure.has_value()) {
        CHECK(
            failure->code
            == xxsnap::win::OverlayRendererErrorCode::textFormatConfigurationFailed);
        CHECK(failure->nativeCode == E_INVALIDARG);
        CHECK(failure->resourceId == 0);
    }
}

void testEmbeddedToolbarResources()
{
    const auto module = GetModuleHandleW(nullptr);
    CHECK(module != nullptr);
    if (module == nullptr) {
        return;
    }

    constexpr std::array<unsigned char, 8> pngSignature{
        0x89U, 0x50U, 0x4EU, 0x47U, 0x0DU, 0x0AU, 0x1AU, 0x0AU};
    for (const auto resource : xxsnap::win::mvpOverlayButtonResources()) {
        const auto handle = FindResourceW(
            module,
            MAKEINTRESOURCEW(resource.resourceId),
            MAKEINTRESOURCEW(10));
        CHECK(handle != nullptr);
        if (handle == nullptr) {
            continue;
        }

        const auto byteCount = SizeofResource(module, handle);
        CHECK(byteCount >= pngSignature.size());
        const auto loaded = LoadResource(module, handle);
        CHECK(loaded != nullptr);
        const auto* bytes = static_cast<const unsigned char*>(LockResource(loaded));
        CHECK(bytes != nullptr);
        if (bytes == nullptr || byteCount < pngSignature.size()) {
            continue;
        }
        for (std::size_t index = 0; index < pngSignature.size(); ++index) {
            CHECK(bytes[index] == pngSignature[index]);
        }
    }

    constexpr int nonMvpSettingsResourceId = 104;
    CHECK(FindResourceW(
        module,
        MAKEINTRESOURCEW(nonMvpSettingsResourceId),
        MAKEINTRESOURCEW(10)) == nullptr);

    std::vector<int> embeddedResourceIds;
    CHECK(EnumResourceNamesW(
        module,
        MAKEINTRESOURCEW(10),
        &collectIntegerResourceName,
        reinterpret_cast<LONG_PTR>(&embeddedResourceIds)) != FALSE);
    std::sort(embeddedResourceIds.begin(), embeddedResourceIds.end());
    CHECK((embeddedResourceIds == std::vector<int>{
        IDR_CANCEL_CAPTURE_PNG,
        IDR_SAVE_TO_FILE_PNG,
        IDR_COPY_TO_CLIPBOARD_PNG,
    }));
}

} // namespace

int main()
{
    testDeterministicManifest();
    testDpiScaling();
    testEdgePlacementAndClamping();
    testCrossDisplaySelectionChromeOwnership();
    testMacToolbarSideCandidatesAtEveryDpi();
    testWindowAndResourceContracts();
    testDpiRestartNotificationIsSingleAndFailClosed();
    testDirectWriteConfigurationFailuresAreExplicit();
    testEmbeddedToolbarResources();

    if (failureCount != 0) {
        std::cerr << failureCount << " overlay layout check(s) failed\n";
        return 1;
    }
    std::cout << "Overlay layout checks passed\n";
    return 0;
}
