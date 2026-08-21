#include "overlay/OverlayHost.h"
#include "capture/DisplayTopology.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <chrono>
#include <cstring>
#include <iostream>
#include <memory>
#include <optional>
#include <tuple>
#include <utility>
#include <vector>

namespace {

using snipory::core::portable::PixelPoint;
using snipory::core::portable::PixelRect;
using xxsnap::win::OverlayInputAction;
using xxsnap::win::OverlayInputPlatform;
using xxsnap::win::OverlayInputRouter;
using xxsnap::win::OverlayMode;
using xxsnap::win::OverlayInputStatus;
using xxsnap::win::overlayActionPreservesWindows;
using xxsnap::win::OverlayCursorStyle;
using xxsnap::win::OverlaySurface;
using xxsnap::win::NumberMarkType;
using xxsnap::win::SelectionPhase;
using xxsnap::win::ShapeEditorKey;
using xxsnap::win::AnnotationColor;
using xxsnap::win::AnnotationRect;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

class FakePlatform final : public OverlayInputPlatform {
public:
    bool captureMouse(HWND window) noexcept override
    {
        ++captureCalls;
        capturedWindow = captureSucceeds ? window : nullptr;
        return captureSucceeds;
    }

    bool releaseMouse() noexcept override
    {
        ++releaseCalls;
        capturedWindow = nullptr;
        return releaseSucceeds;
    }

    std::optional<PixelPoint> cursorPosition() noexcept override
    {
        ++cursorCalls;
        return cursor;
    }

    bool registerEscapeHotKey(HWND window, int identifier) noexcept override
    {
        ++registerCalls;
        registeredWindow = window;
        registeredIdentifier = identifier;
        return registerSucceeds;
    }

    bool unregisterEscapeHotKey(HWND window, int identifier) noexcept override
    {
        ++unregisterCalls;
        return unregisterSucceeds
            && window == registeredWindow
            && identifier == registeredIdentifier;
    }

    bool registerToolbarHotKeys(HWND) noexcept override
    {
        ++registerToolbarCalls;
        return true;
    }

    bool unregisterToolbarHotKeys(HWND) noexcept override
    {
        ++unregisterToolbarCalls;
        return true;
    }

    std::optional<AnnotationColor> chooseColor(
        HWND window,
        AnnotationColor) noexcept override
    {
        ++chooseColorCalls;
        chosenColorWindow = window;
        return chosenColor;
    }

    bool shiftPressed() noexcept override
    {
        return shiftDown;
    }

    bool copyText(const std::wstring& text) noexcept override
    {
        copiedText = text;
        ++copyTextCalls;
        return copyTextSucceeds;
    }

    bool captureSucceeds = true;
    bool releaseSucceeds = true;
    bool registerSucceeds = true;
    bool unregisterSucceeds = true;
    std::optional<PixelPoint> cursor;
    HWND capturedWindow = nullptr;
    HWND registeredWindow = nullptr;
    int registeredIdentifier = 0;
    int captureCalls = 0;
    int releaseCalls = 0;
    int cursorCalls = 0;
    int registerCalls = 0;
    int unregisterCalls = 0;
    int registerToolbarCalls = 0;
    int unregisterToolbarCalls = 0;
    int chooseColorCalls = 0;
    HWND chosenColorWindow = nullptr;
    bool shiftDown = false;
    bool copyTextSucceeds = true;
    int copyTextCalls = 0;
    std::wstring copiedText;
    std::optional<AnnotationColor> chosenColor = AnnotationColor{1, 2, 3, 255};
};

std::unique_ptr<xxsnap::win::FrozenDesktop> solidDesktop(
    AnnotationColor color)
{
    using namespace xxsnap::win;
    std::vector<DisplayDescriptor> descriptors{{
        L"desktop",
        {-640, 0, 1280, 360},
        96U,
        96U,
        DISPLAYCONFIG_ROTATION_IDENTITY,
    }};
    const auto topologyResult = buildDisplayTopologySnapshot(descriptors);
    if (!topologyResult.hasValue()) {
        return nullptr;
    }
    snipory::core::portable::MemoryBudget budget(8U * 1024U * 1024U);
    auto allocation = snipory::core::portable::PixelBuffer::allocate(
        1280, 360, budget);
    if (!allocation.value) {
        return nullptr;
    }
    for (std::size_t offset = 0U;
         offset < allocation.value->byteCount(); offset += 4U) {
        allocation.value->data()[offset] = static_cast<std::byte>(color.blue);
        allocation.value->data()[offset + 1U] = static_cast<std::byte>(color.green);
        allocation.value->data()[offset + 2U] = static_cast<std::byte>(color.red);
        allocation.value->data()[offset + 3U] = std::byte{0xFF};
    }
    std::vector<FrozenDisplay> displays;
    displays.emplace_back(descriptors.front(), std::move(*allocation.value));
    return std::make_unique<FrozenDesktop>(
        *topologyResult.value(),
        std::move(displays),
        std::chrono::steady_clock::time_point{});
}

void setDesktopPixel(
    xxsnap::win::FrozenDesktop& desktop,
    PixelPoint point,
    AnnotationColor color)
{
    for (auto& display : desktop.displays) {
        const auto bounds = display.descriptor.pixelBounds;
        if (point.x < bounds.x || point.y < bounds.y
            || point.x >= bounds.x + bounds.width
            || point.y >= bounds.y + bounds.height) {
            continue;
        }
        const auto x = point.x - bounds.x;
        const auto y = point.y - bounds.y;
        auto* pixel = display.pixels.data()
            + static_cast<std::uint64_t>(y) * display.pixels.stride()
            + static_cast<std::uint64_t>(x) * 4U;
        pixel[0] = static_cast<std::byte>(color.blue);
        pixel[1] = static_cast<std::byte>(color.green);
        pixel[2] = static_cast<std::byte>(color.red);
        pixel[3] = static_cast<std::byte>(color.alpha);
        return;
    }
}

const HWND leftWindow = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(1));
const HWND rightWindow = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(2));

std::vector<OverlaySurface> surfaces()
{
    return {
        {leftWindow, PixelRect{-640, 0, 640, 360}, 96, 96},
        {rightWindow, PixelRect{0, 0, 640, 360}, 144, 144},
    };
}

void createReadySelection(OverlayInputRouter& router)
{
    CHECK(router.pointerDown(leftWindow, PixelPoint{500, 80}));
    router.platformPointerMove(PixelPoint{120, 280});
    router.platformPointerUp(PixelPoint{120, 280});
    CHECK(router.phase() == SelectionPhase::ready);
    CHECK((router.selection() == PixelRect{-140, 80, 260, 200}));
}

void testPinToolbarTransfersTheReadySelection()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true);
    createReadySelection(router);
    const auto owner = router.presentations()[1];
    const auto pin = std::find_if(
        owner.toolbarItems.begin(), owner.toolbarItems.end(),
        [](const auto& item) {
            return item.action == xxsnap::win::ToolbarAction::pin;
        });
    CHECK(pin != owner.toolbarItems.end());
    if (pin != owner.toolbarItems.end()) {
        CHECK(router.pointerDown(rightWindow, pin->centerPhysical));
    }
    CHECK(actions.size() == 1U);
    CHECK(actions.front() == OverlayInputAction::pin);
    CHECK(router.status() == OverlayInputStatus::completed);
}

void testCtrlOnePinsTheReadySelection()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true);
    createReadySelection(router);
    CHECK(router.keyPressed(ShapeEditorKey::pin, true, false));
    CHECK(actions.size() == 1U);
    CHECK(actions.front() == OverlayInputAction::pin);
}

void testPinnedImageEditorLocksSelectionAndFinishesWithoutCaptureActions()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    const auto window = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(3));
    OverlayInputRouter router(
        PixelRect{40, 60, 500, 300},
        {{window, PixelRect{40, 60, 500, 300}, 96, 96}},
        platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true, nullptr, OverlayMode::pinnedImageEditor);
    router.lockSelection({40, 60, 500, 300});
    CHECK(router.phase() == SelectionPhase::ready);
    const auto presentation = router.presentations().front();
    CHECK(presentation.pinnedImageEditor);
    CHECK(presentation.toolbarItems.size()
        == xxsnap::win::pinnedEditorToolbarActions().size());
    CHECK(std::none_of(presentation.toolbarItems.begin(),
        presentation.toolbarItems.end(), [](const auto& item) {
            return item.action == xxsnap::win::ToolbarAction::scroll
                || item.action == xxsnap::win::ToolbarAction::cancel
                || item.action == xxsnap::win::ToolbarAction::pin;
        }));
    const auto finish = std::find_if(presentation.toolbarItems.begin(),
        presentation.toolbarItems.end(), [](const auto& item) {
            return item.action == xxsnap::win::ToolbarAction::finishEditing;
        });
    CHECK(finish != presentation.toolbarItems.end());
    if (finish != presentation.toolbarItems.end()) {
        CHECK(router.pointerDown(window, finish->centerPhysical));
    }
    CHECK(actions.size() == 1U);
    CHECK(actions.front() == OverlayInputAction::finishEditing);
}

void testPinnedImageEditorEscapeFinishesInsteadOfCancelling()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    const auto window = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(3));
    OverlayInputRouter router(
        PixelRect{40, 60, 500, 300},
        {{window, PixelRect{40, 60, 500, 300}, 96, 96}},
        platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true, nullptr, OverlayMode::pinnedImageEditor);
    router.lockSelection({40, 60, 500, 300});

    router.escapePressed();

    CHECK(actions.size() == 1U);
    CHECK(actions.front() == OverlayInputAction::finishEditing);
    CHECK(router.status() == OverlayInputStatus::completed);
}

void testLongImageEditorEscapeFinishesInsteadOfCancelling()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    const auto window = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(4));
    OverlayInputRouter router(
        PixelRect{40, 60, 500, 300},
        {{window, PixelRect{40, 60, 500, 300}, 96, 96}},
        platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true, nullptr, OverlayMode::longImageEditor);
    router.lockSelection({40, 60, 500, 300});

    router.escapePressed();

    CHECK(actions == std::vector<OverlayInputAction>{
        OverlayInputAction::finishEditing});
    CHECK(router.status() == OverlayInputStatus::completed);
}

void testPinnedImageEditorStandaloneShiftRequestsToolbarHideOnRelease()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    const auto window = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(3));
    OverlayInputRouter router(
        PixelRect{40, 60, 500, 300},
        {{window, PixelRect{40, 60, 500, 300}, 96, 96}},
        platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true, nullptr, OverlayMode::pinnedImageEditor);
    router.lockSelection({40, 60, 500, 300});

    CHECK(router.pinnedImageShiftChanged(true, false, false));
    CHECK(actions.empty());
    CHECK(router.pinnedImageShiftChanged(false, false, false));
    CHECK(actions == std::vector<OverlayInputAction>{
        OverlayInputAction::hideEditingToolbar});
    CHECK(router.status() == OverlayInputStatus::active);
}

void testPinnedImageEditorShiftToggleCancelsForMixedInput()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    const auto window = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(3));
    OverlayInputRouter router(
        PixelRect{40, 60, 500, 300},
        {{window, PixelRect{40, 60, 500, 300}, 96, 96}},
        platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true, nullptr, OverlayMode::pinnedImageEditor);
    router.lockSelection({40, 60, 500, 300});

    CHECK(router.pinnedImageShiftChanged(true, false, false));
    CHECK(!router.pinnedImageShiftChanged(true, false, true));
    CHECK(!router.pinnedImageShiftChanged(false, false, false));
    CHECK(actions.empty());

    CHECK(router.pinnedImageShiftChanged(true, false, false));
    router.cancelPinnedImageShiftShortcut();
    CHECK(!router.pinnedImageShiftChanged(false, false, false));
    CHECK(actions.empty());
}

void testPinnedImageEditorAlwaysOnTopShortcutIsNonTerminal()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    const auto window = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(3));
    OverlayInputRouter router(
        PixelRect{40, 60, 500, 300},
        {{window, PixelRect{40, 60, 500, 300}, 96, 96}},
        platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true, nullptr, OverlayMode::pinnedImageEditor);
    router.lockSelection({40, 60, 500, 300});

    CHECK(router.togglePinnedImageAlwaysOnTop());
    CHECK(actions == std::vector<OverlayInputAction>{
        OverlayInputAction::togglePinnedImageAlwaysOnTop});
    CHECK(router.status() == OverlayInputStatus::active);
}

PixelPoint dipCenterAt144Dpi(AnnotationRect rect)
{
    return {
        static_cast<std::int64_t>((rect.x + rect.width / 2.0F) * 1.5F + 0.5F),
        static_cast<std::int64_t>((rect.y + rect.height / 2.0F) * 1.5F + 0.5F),
    };
}

void testCrossWindowRoutingUsesVirtualPhysicalCoordinates()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); });
    CHECK(router.activateEscapeHotKey(leftWindow));

    CHECK(router.pointerDown(leftWindow, PixelPoint{500, 80}));
    CHECK(router.phase() == SelectionPhase::creating);
    CHECK(platform.capturedWindow == leftWindow);
    CHECK(!router.presentations()[0].showActions);
    CHECK(!router.presentations()[1].showActions);

    platform.cursor = PixelPoint{120, 280};
    router.pointerMove(rightWindow, PixelPoint{5, 5});
    router.pointerUp(rightWindow, PixelPoint{5, 5});
    CHECK(router.phase() == SelectionPhase::ready);
    CHECK((router.selection() == PixelRect{-140, 80, 260, 200}));
    CHECK(platform.cursorCalls == 2);
    CHECK(platform.releaseCalls == 1);
    CHECK(actions.empty());
    router.captureChanged();
    CHECK(router.status() == OverlayInputStatus::active);
    CHECK(actions.empty());

    const auto presentations = router.presentations();
    CHECK(presentations.size() == 2);
    CHECK(!presentations[0].showActions);
    CHECK(presentations[1].showActions);
}

void testActionHandleBodyAndBlankPriority()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); });
    createReadySelection(router);

    const auto owner = router.presentations()[1];
    CHECK(owner.showActions);
    CHECK(owner.toolbarItems.size() == 3U);
    CHECK(router.pointerDown(rightWindow, owner.toolbarItems[2].centerPhysical));
    CHECK(actions.size() == 1);
    CHECK(actions[0] == OverlayInputAction::copy);
    CHECK(router.status() == OverlayInputStatus::completed);
    CHECK(platform.captureCalls == 1);
    CHECK(platform.unregisterCalls == 0);

    FakePlatform resizePlatform;
    OverlayInputRouter resizeRouter(
        PixelRect{-640, 0, 1280, 360}, surfaces(), resizePlatform, {});
    createReadySelection(resizeRouter);
    CHECK(resizeRouter.pointerDown(leftWindow, PixelPoint{500, 80}));
    CHECK(resizeRouter.phase() == SelectionPhase::resizing);

    FakePlatform movePlatform;
    OverlayInputRouter moveRouter(
        PixelRect{-640, 0, 1280, 360}, surfaces(), movePlatform, {});
    createReadySelection(moveRouter);
    CHECK(moveRouter.pointerDown(leftWindow, PixelPoint{550, 160}));
    CHECK(moveRouter.phase() == SelectionPhase::moving);

    FakePlatform blankPlatform;
    OverlayInputRouter blankRouter(
        PixelRect{-640, 0, 1280, 360}, surfaces(), blankPlatform, {});
    createReadySelection(blankRouter);
    CHECK(blankRouter.pointerDown(rightWindow, PixelPoint{400, 40}));
    CHECK(blankRouter.phase() == SelectionPhase::creating);
}

void testAllToolbarActionsFireExactlyOnceWithoutStartingCapture()
{
    for (const auto expected : {
             OverlayInputAction::cancel,
             OverlayInputAction::save,
             OverlayInputAction::copy}) {
        FakePlatform platform;
        std::vector<OverlayInputAction> actions;
        OverlayInputRouter router(
            PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
            [&actions](OverlayInputAction action) { actions.push_back(action); });
        CHECK(router.activateEscapeHotKey(leftWindow));
        createReadySelection(router);
        const auto owner = router.presentations()[1];
        const auto itemIndex = expected == OverlayInputAction::cancel
            ? 0U
            : expected == OverlayInputAction::save ? 1U : 2U;
        CHECK(owner.toolbarItems.size() == 3U);
        const auto point = owner.toolbarItems[itemIndex].centerPhysical;
        const auto capturesBeforeAction = platform.captureCalls;
        CHECK(router.pointerDown(rightWindow, point));
        CHECK(actions.size() == 1);
        CHECK(actions[0] == expected);
        CHECK(platform.captureCalls == capturesBeforeAction);
        CHECK(platform.unregisterCalls == 1);
        router.escapePressed();
        router.cancelPressed();
        CHECK(actions.size() == 1);
    }
}

void testToolbarPresentationUsesSharedPhysicalRects()
{
    FakePlatform platform;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {});
    createReadySelection(router);
    const auto owner = router.presentations()[1];
    CHECK(owner.toolbarItems.size() == 3U);
    CHECK(owner.toolbarItems[0].action == xxsnap::win::ToolbarAction::cancel);
    CHECK(owner.toolbarItems[1].action == xxsnap::win::ToolbarAction::save);
    CHECK(owner.toolbarItems[2].action == xxsnap::win::ToolbarAction::copy);
    for (const auto& item : owner.toolbarItems) {
        CHECK(item.rectPhysical.width == 30);
        CHECK(item.rectPhysical.height == 30);
        CHECK(item.centerPhysical.x >= item.rectPhysical.x);
        CHECK(item.centerPhysical.x < item.rectPhysical.x + item.rectPhysical.width);
    }
}

void testOnePixelOutsideToolbarItemsDoesNotFireAction()
{
    for (std::size_t itemIndex = 0; itemIndex < 3U; ++itemIndex) {
        FakePlatform platform;
        std::vector<OverlayInputAction> actions;
        OverlayInputRouter router(
            PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
            [&actions](OverlayInputAction action) { actions.push_back(action); });
        createReadySelection(router);
        const auto item = router.presentations()[1].toolbarItems[itemIndex];
        const PixelPoint outside{
            item.rectPhysical.x + item.rectPhysical.width,
            item.centerPhysical.y,
        };
        CHECK(router.pointerDown(rightWindow, outside));
        CHECK(actions.empty());
        CHECK(router.phase() == SelectionPhase::creating);
    }
}

void testCancelSourcesAreIdempotentAndCaptureFailureFailsClosed()
{
    for (int source = 0; source < 4; ++source) {
        FakePlatform platform;
        std::vector<OverlayInputAction> actions;
        OverlayInputRouter router(
            PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
            [&actions](OverlayInputAction action) { actions.push_back(action); });
        CHECK(router.activateEscapeHotKey(leftWindow));
        CHECK(router.pointerDown(leftWindow, PixelPoint{20, 20}));
        if (source == 0) {
            router.captureChanged();
        } else if (source == 1) {
            router.cancelMode();
        } else if (source == 2) {
            router.escapePressed();
        } else {
            router.cancelPressed();
        }
        router.captureChanged();
        router.cancelMode();
        router.escapePressed();
        router.cancelPressed();
        CHECK(router.status() == OverlayInputStatus::cancelled);
        CHECK(actions.size() == 1);
        CHECK(actions[0] == OverlayInputAction::cancel);
        CHECK(platform.unregisterCalls == 1);
    }

    FakePlatform failing;
    failing.captureSucceeds = false;
    std::vector<OverlayInputAction> actions;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), failing,
        [&actions](OverlayInputAction action) { actions.push_back(action); });
    CHECK(router.activateEscapeHotKey(leftWindow));
    CHECK(!router.pointerDown(leftWindow, PixelPoint{20, 20}));
    CHECK(router.status() == OverlayInputStatus::cancelled);
    CHECK(actions.size() == 1);
    CHECK(failing.unregisterCalls == 1);
    CHECK(router.lastError()
        == xxsnap::win::OverlayInputErrorCode::mouseCaptureFailed);

    FakePlatform cursorFailure;
    OverlayInputRouter cursorRouter(
        PixelRect{-640, 0, 1280, 360}, surfaces(), cursorFailure, {});
    CHECK(cursorRouter.pointerDown(leftWindow, PixelPoint{20, 20}));
    cursorRouter.pointerMove(leftWindow, PixelPoint{21, 21});
    CHECK(cursorRouter.status() == OverlayInputStatus::cancelled);
    CHECK(cursorRouter.lastError()
        == xxsnap::win::OverlayInputErrorCode::cursorPositionFailed);

    FakePlatform releaseFailure;
    releaseFailure.releaseSucceeds = false;
    OverlayInputRouter releaseRouter(
        PixelRect{-640, 0, 1280, 360}, surfaces(), releaseFailure, {});
    CHECK(releaseRouter.pointerDown(leftWindow, PixelPoint{20, 20}));
    releaseRouter.platformPointerUp(PixelPoint{-610, 30});
    CHECK(releaseRouter.status() == OverlayInputStatus::cancelled);
    CHECK(releaseRouter.lastError()
        == xxsnap::win::OverlayInputErrorCode::mouseReleaseFailed);
}

void testEscapeRegistrationLifecycleIsExplicit()
{
    FakePlatform platform;
    {
        OverlayInputRouter router(
            PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {});
        CHECK(router.activateEscapeHotKey(leftWindow));
        CHECK(router.activateEscapeHotKey(leftWindow));
        CHECK(platform.registerCalls == 1);
    }
    CHECK(platform.unregisterCalls == 1);

    FakePlatform failure;
    failure.registerSucceeds = false;
    OverlayInputRouter failed(
        PixelRect{-640, 0, 1280, 360}, surfaces(), failure, {});
    CHECK(!failed.activateEscapeHotKey(leftWindow));
    CHECK(failed.status() == OverlayInputStatus::cancelled);
    CHECK(failed.lastError()
        == xxsnap::win::OverlayInputErrorCode::escapeHotKeyRegistrationFailed);

    CHECK(xxsnap::win::isOverlayEscapeHotKey(
        static_cast<WPARAM>(xxsnap::win::overlayEscapeHotKeyIdentifier)));
    CHECK(!xxsnap::win::isOverlayEscapeHotKey(
        static_cast<WPARAM>(xxsnap::win::overlayEscapeHotKeyIdentifier + 1)));
}

void testEscapeUnregisterFailureIsObservableAndRetriedOnDestruction()
{
    FakePlatform platform;
    platform.unregisterSucceeds = false;
    {
        OverlayInputRouter router(
            PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {});
        CHECK(router.activateEscapeHotKey(leftWindow));
        router.escapePressed();
        CHECK(platform.unregisterCalls == 1);
        CHECK(router.lastError()
            == xxsnap::win::OverlayInputErrorCode::escapeHotKeyUnregistrationFailed);
    }
    CHECK(platform.unregisterCalls == 2);
}

void testTerminalCallbackMaySynchronouslyDestroyRouter()
{
    FakePlatform platform;
    std::unique_ptr<OverlayInputRouter> router;
    router = std::make_unique<OverlayInputRouter>(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
        [&router](OverlayInputAction) { router.reset(); });
    auto* activeRouter = router.get();
    activeRouter->escapePressed();
    CHECK(router == nullptr);
}

void testRestartShutdownReleasesCaptureAndHotKeyWithoutCancelAction()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); });
    CHECK(router.activateEscapeHotKey(leftWindow));
    CHECK(router.pointerDown(leftWindow, PixelPoint{20, 20}));
    router.shutdownForRestart();
    CHECK(router.status() == OverlayInputStatus::cancelled);
    CHECK(platform.releaseCalls == 1);
    CHECK(platform.unregisterCalls == 1);
    CHECK(actions.empty());
    router.captureChanged();
    CHECK(actions.empty());
}

void testScrollToolbarSuspendsOverlayWithoutCompletingRouter()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true);
    CHECK(router.activateEscapeHotKey(leftWindow));
    createReadySelection(router);
    const auto owner = router.presentations()[1];
    CHECK(owner.toolbarItems.size() == 17U);
    CHECK(owner.toolbarItems[10].action
        == xxsnap::win::ToolbarAction::scroll);
    CHECK(router.pointerDown(
        rightWindow, owner.toolbarItems[10].centerPhysical));
    CHECK(actions.size() == 1U);
    CHECK(actions.front() == OverlayInputAction::scrollCapture);
    CHECK(router.status() == OverlayInputStatus::active);
    CHECK(platform.unregisterCalls == 1);
}

void testScrollCapturePreservesOverlayWindowsForSuspensionAndResume()
{
    CHECK(overlayActionPreservesWindows(OverlayInputAction::scrollCapture));
    CHECK(overlayActionPreservesWindows(
        OverlayInputAction::togglePinnedImageAlwaysOnTop));
    CHECK(!overlayActionPreservesWindows(OverlayInputAction::copy));
}

void testToolbarHoverShowsMacShortcutTipAndRStartsScrollCapture()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true);
    CHECK(router.activateEscapeHotKey(leftWindow));
    createReadySelection(router);
    const auto owner = router.presentations()[1];
    const auto scroll = owner.toolbarItems[10];
    const auto scrollHotKey = xxsnap::win::overlayToolbarHotKey(
        xxsnap::win::overlayToolbarHotKeyIdentifier(
            xxsnap::win::ToolbarAction::scroll, false));
    CHECK(scrollHotKey.has_value());
    CHECK(scrollHotKey.has_value()
        && scrollHotKey->action == xxsnap::win::ToolbarAction::scroll);
    CHECK(scrollHotKey.has_value() && !scrollHotKey->shift);
    const auto shiftedPenHotKey = xxsnap::win::overlayToolbarHotKey(
        xxsnap::win::overlayToolbarHotKeyIdentifier(
            xxsnap::win::ToolbarAction::pen, true));
    CHECK(shiftedPenHotKey.has_value());
    CHECK(shiftedPenHotKey.has_value()
        && shiftedPenHotKey->action == xxsnap::win::ToolbarAction::pen);
    CHECK(shiftedPenHotKey.has_value() && shiftedPenHotKey->shift);
    CHECK(!xxsnap::win::overlayToolbarHotKey(
        xxsnap::win::overlayToolbarHotKeyIdentifier(
            xxsnap::win::ToolbarAction::save, false)).has_value());
    CHECK(!xxsnap::win::overlayToolbarHotKey(
        xxsnap::win::overlayToolbarHotKeyIdentifier(
            xxsnap::win::ToolbarAction::clearAll, false)).has_value());

    router.pointerMove(rightWindow, scroll.centerPhysical);

    const auto hovered = router.presentations()[1];
    CHECK(hovered.toolbarTooltip.has_value());
    if (hovered.toolbarTooltip.has_value()) {
        CHECK(hovered.toolbarTooltip->text == L"滚动截图 (R)");
        CHECK(hovered.toolbarTooltip->anchor == scroll.rectPhysical);
    }
    router.pointerLeave(rightWindow);
    CHECK(!router.presentations()[1].toolbarTooltip.has_value());

    CHECK(!router.toolbarShortcutPressed('R', false, false, true));
    CHECK(actions.empty());
    CHECK(router.toolbarShortcutPressed('R', false, false, false));
    CHECK(actions == std::vector<OverlayInputAction>{
        OverlayInputAction::scrollCapture});
    CHECK(platform.unregisterCalls == 1);
}

void testMacToolShortcutsSelectToolsAndDoNotInterruptInlineText()
{
    FakePlatform platform;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
        [](OverlayInputAction) {}, true);
    createReadySelection(router);
    CHECK(router.activateEscapeHotKey(leftWindow));
    CHECK(platform.registerToolbarCalls == 1);
    constexpr std::array shortcuts{
        std::pair{'S', xxsnap::win::ToolbarAction::rectangle},
        std::pair{'A', xxsnap::win::ToolbarAction::polyline},
        std::pair{'B', xxsnap::win::ToolbarAction::pen},
        std::pair{'H', xxsnap::win::ToolbarAction::marker},
        std::pair{'P', xxsnap::win::ToolbarAction::eyedropper},
        std::pair{'M', xxsnap::win::ToolbarAction::mosaic},
        std::pair{'T', xxsnap::win::ToolbarAction::text},
        std::pair{'N', xxsnap::win::ToolbarAction::number},
        std::pair{'G', xxsnap::win::ToolbarAction::magnifier},
        std::pair{'E', xxsnap::win::ToolbarAction::eraser},
    };
    for (const auto& [key, action] : shortcuts) {
        CHECK(router.toolbarShortcutPressed(key, false, false, false));
        const auto presentation = router.presentations()[1];
        const auto item = std::find_if(presentation.toolbarItems.begin(),
            presentation.toolbarItems.end(), [action](const auto& candidate) {
                return candidate.action == action;
            });
        CHECK(item != presentation.toolbarItems.end());
        CHECK(item != presentation.toolbarItems.end() && item->selected);
    }

    CHECK(router.toolbarShortcutPressed('T', false, false, false));
    CHECK(router.pointerDown(rightWindow, {100, 100}));
    CHECK(router.isEditingInlineValue());
    router.synchronizeToolbarHotKeys();
    CHECK(platform.unregisterToolbarCalls == 1);
    CHECK(router.toolbarShortcutPressed('N', false, false, false));
    CHECK(router.isEditingInlineValue());
    CHECK(router.textInput(L"S"));
    CHECK(router.isEditingInlineValue());
    router.escapePressed();
    router.synchronizeToolbarHotKeys();
    CHECK(!router.isEditingInlineValue());
    CHECK(platform.registerToolbarCalls == 2);
}

void testControlToolbarShortcutsRouteThroughCatalog()
{
    FakePlatform platform;
    OverlayInputRouter historyRouter(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
        [](OverlayInputAction) {}, true);
    createReadySelection(historyRouter);
    CHECK(historyRouter.toolbarShortcutPressed('S', false, false, false));
    CHECK(historyRouter.pointerDown(rightWindow, {80, 80}));
    platform.cursor = PixelPoint{140, 140};
    historyRouter.pointerMove(rightWindow, {140, 140});
    historyRouter.pointerUp(rightWindow, {140, 140});
    CHECK(historyRouter.annotationDocument().annotations().size() == 1U);
    CHECK(historyRouter.toolbarShortcutPressed('Z', true, false, false));
    CHECK(historyRouter.annotationDocument().annotations().empty());
    CHECK(historyRouter.toolbarShortcutPressed('Z', true, true, false));
    CHECK(historyRouter.annotationDocument().annotations().size() == 1U);

    constexpr std::array terminalShortcuts{
        std::tuple{'S', xxsnap::win::OverlayInputAction::save},
        std::tuple{'C', xxsnap::win::OverlayInputAction::copy},
        std::tuple{'1', xxsnap::win::OverlayInputAction::pin},
    };
    for (const auto& [key, expected] : terminalShortcuts) {
        std::vector<OverlayInputAction> actions;
        OverlayInputRouter router(
            PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
            [&actions](OverlayInputAction action) { actions.push_back(action); },
            true);
        createReadySelection(router);
        CHECK(router.toolbarShortcutPressed(key, true, false, false));
        CHECK(actions == std::vector<OverlayInputAction>{expected});
    }
}

void testShapeToolIsNonTerminalAndEditsThroughSharedPresentation()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360},
        surfaces(),
        platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true);
    createReadySelection(router);

    auto owner = router.presentations()[1];
    CHECK(owner.toolbarItems.size() == 17U);
    const auto rectangle = owner.toolbarItems[0];
    CHECK(rectangle.action == xxsnap::win::ToolbarAction::rectangle);
    const auto capturesBeforeTool = platform.captureCalls;
    CHECK(router.pointerDown(rightWindow, rectangle.centerPhysical));
    CHECK(actions.empty());
    CHECK(platform.captureCalls == capturesBeforeTool);

    owner = router.presentations()[1];
    CHECK(owner.toolbarItems[0].selected);
    CHECK(owner.shapeOptions.has_value());
    CHECK(owner.annotationPlan.items.empty());

    auto options = *owner.shapeOptions;
    CHECK(router.pointerDown(
        rightWindow, dipCenterAt144Dpi(options.layout.rectangleDisclosure)));
    owner = router.presentations()[1];
    CHECK(owner.shapeOptions->cornerRadiusPanel.has_value());
    CHECK(router.pointerDown(
        rightWindow,
        dipCenterAt144Dpi(owner.shapeOptions->cornerRadiusPanel->increment)));
    CHECK(router.presentations()[1].shapeOptions->state.style().cornerRadiusDip
        == 6.0F);

    options = *router.presentations()[1].shapeOptions;
    CHECK(router.pointerDown(
        rightWindow, dipCenterAt144Dpi(options.layout.strokeStyle)));
    owner = router.presentations()[1];
    CHECK(owner.shapeOptions->strokePatternMenu.has_value());
    CHECK(router.pointerDown(
        rightWindow,
        dipCenterAt144Dpi(owner.shapeOptions->strokePatternMenu->items[2])));
    CHECK(router.presentations()[1].shapeOptions->state.style().strokePattern
        == xxsnap::win::AnnotationStrokePattern::dashNarrow);

    options = *router.presentations()[1].shapeOptions;
    CHECK(router.pointerDown(
        rightWindow, dipCenterAt144Dpi(options.layout.colorSwatches.back())));
    CHECK(platform.chooseColorCalls == 1);
    CHECK(platform.chosenColorWindow == rightWindow);
    CHECK((router.presentations()[1].shapeOptions->state.style().strokeColor
        == AnnotationColor{1, 2, 3, 255}));

    CHECK(router.pointerDown(rightWindow, PixelPoint{10, 100}));
    platform.cursor = PixelPoint{100, 180};
    router.pointerMove(rightWindow, PixelPoint{100, 180});
    CHECK(router.presentations()[1].annotationPlan.items.size() == 1U);
    router.pointerUp(rightWindow, PixelPoint{100, 180});
    CHECK(router.annotationDocument().annotations().size() == 1U);
    CHECK(actions.empty());

    owner = router.presentations()[1];
    CHECK(owner.annotationPlan.items.size() == 1U);
    const auto undo = std::find_if(owner.toolbarItems.begin(),
        owner.toolbarItems.end(), [](const auto& item) {
            return item.action == xxsnap::win::ToolbarAction::undo;
        });
    CHECK(undo != owner.toolbarItems.end());
    CHECK(undo->enabled);
    CHECK(router.pointerDown(rightWindow, undo->centerPhysical));
    CHECK(router.annotationDocument().annotations().empty());
    CHECK(actions.empty());

    CHECK(router.keyPressed(ShapeEditorKey::z, true, true));
    CHECK(router.annotationDocument().annotations().size() == 1U);
    CHECK(router.keyPressed(ShapeEditorKey::copy, true, false));
    CHECK(actions.size() == 1U);
    CHECK(actions[0] == OverlayInputAction::copy);
}

void testArrowToolUsesMacOptionsMenuAndCreatesEditableCurve()
{
    FakePlatform platform;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true);
    createReadySelection(router);

    auto owner = router.presentations()[1];
    CHECK(owner.toolbarItems.size() == 17U);
    CHECK(owner.toolbarItems[1].action == xxsnap::win::ToolbarAction::polyline);
    CHECK(router.pointerDown(
        rightWindow, owner.toolbarItems[1].centerPhysical));
    owner = router.presentations()[1];
    CHECK(owner.toolbarItems[1].selected);
    CHECK(owner.arrowLineOptions.has_value());
    CHECK(owner.arrowLineOptions->state.style().strokeWidthDip == 4.0F);

    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.arrowLineOptions->layout.startArrowType)));
    owner = router.presentations()[1];
    CHECK(owner.arrowLineOptions->arrowTypeMenu.has_value());
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.arrowLineOptions->arrowTypeMenu->items[5])));
    owner = router.presentations()[1];
    CHECK(owner.arrowLineOptions->state.startArrowType()
        == xxsnap::win::ArrowType::bar);
    CHECK(!owner.arrowLineOptions->arrowTypeMenu.has_value());

    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.arrowLineOptions->layout.startArrowType)));
    owner = router.presentations()[1];
    CHECK(owner.arrowLineOptions->arrowTypeMenu.has_value());
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.arrowLineOptions->arrowTypeMenu->items[5])));
    CHECK(!router.presentations()[1]
        .arrowLineOptions->arrowTypeMenu.has_value());

    owner = router.presentations()[1];
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.arrowLineOptions->layout.strokeStyle)));
    owner = router.presentations()[1];
    CHECK(owner.arrowLineOptions->strokePatternMenu.has_value());
    if (!owner.arrowLineOptions->strokePatternMenu.has_value()) {
        return;
    }
    const auto strokeItem = owner.arrowLineOptions->strokePatternMenu->items[5];
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        strokeItem)));
    owner = router.presentations()[1];
    if (!owner.arrowLineOptions.has_value()) {
        CHECK(owner.arrowLineOptions.has_value());
        return;
    }
    CHECK(owner.arrowLineOptions->state.style().strokePattern
        == xxsnap::win::AnnotationStrokePattern::sketchDashed);

    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.arrowLineOptions->layout.endArrowType)));
    owner = router.presentations()[1];
    CHECK(owner.arrowLineOptions->arrowTypeMenu.has_value());
    CHECK(owner.arrowLineOptions->arrowTypeMenuEndpoint
        == xxsnap::win::ArrowEndpoint::end);
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.arrowLineOptions->arrowTypeMenu->items[6])));
    owner = router.presentations()[1];
    CHECK(owner.arrowLineOptions->state.endArrowType()
        == xxsnap::win::ArrowType::dot);
    CHECK(!owner.arrowLineOptions->arrowTypeMenu.has_value());

    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.arrowLineOptions->layout.colorSwatches[2])));
    owner = router.presentations()[1];
    CHECK(owner.arrowLineOptions->state.style().strokeColor
        == xxsnap::win::macShapePalette()[2]);
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.arrowLineOptions->layout.colorSwatches.back())));
    CHECK(platform.chooseColorCalls == 1);
    owner = router.presentations()[1];
    CHECK((owner.arrowLineOptions->state.style().strokeColor
        == AnnotationColor{1, 2, 3, 255}));

    CHECK(router.pointerDown(rightWindow, PixelPoint{40, 90}));
    platform.cursor = PixelPoint{180, 190};
    router.pointerMove(rightWindow, PixelPoint{180, 190});
    CHECK(router.presentations()[1].annotationPlan.items.size() == 1U);
    router.pointerUp(rightWindow, PixelPoint{180, 190});
    CHECK(router.annotationDocument().annotations().size() == 1U);
    const auto& created = router.annotationDocument().annotations().front();
    CHECK(created.kind == xxsnap::win::AnnotationKind::arrowLine);
    CHECK(created.arrowLine.has_value());
    CHECK(created.arrowLine->startArrowType == xxsnap::win::ArrowType::bar);
    CHECK(created.arrowLine->endArrowType == xxsnap::win::ArrowType::dot);
    CHECK(created.style.strokePattern
        == xxsnap::win::AnnotationStrokePattern::sketchDashed);
    CHECK((created.style.strokeColor == AnnotationColor{1, 2, 3, 255}));
    CHECK(router.presentations()[1].annotationPlan.lineHandles.size() == 3U);
}

void testBrushToolUsesMacOptionsAndShiftStraightLine()
{
    FakePlatform platform;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true);
    createReadySelection(router);

    auto owner = router.presentations()[1];
    CHECK(owner.toolbarItems[2].action == xxsnap::win::ToolbarAction::pen);
    CHECK(router.pointerDown(
        rightWindow, owner.toolbarItems[2].centerPhysical));
    owner = router.presentations()[1];
    CHECK(owner.toolbarItems[2].selected);
    CHECK(owner.brushOptions.has_value());
    if (!owner.brushOptions.has_value()) {
        return;
    }
    CHECK(owner.brushOptions->state.style().strokeWidthDip == 3.0F);
    CHECK(owner.brushOptions->layout.toolbar.width == 418.0F);

    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.brushOptions->layout.strokeWidths[2])));
    owner = router.presentations()[1];
    CHECK(owner.brushOptions->state.style().strokeWidthDip == 7.0F);
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.brushOptions->layout.strokeStyle)));
    owner = router.presentations()[1];
    CHECK(owner.brushOptions->strokePatternMenu.has_value());
    CHECK(owner.brushOptions->strokePatternMenu->items.size() == 4U);
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.brushOptions->strokePatternMenu->items[3])));
    owner = router.presentations()[1];
    CHECK(owner.brushOptions->state.style().strokePattern
        == xxsnap::win::AnnotationStrokePattern::dashLongShort);
    CHECK(router.cursorStyle(rightWindow, PixelPoint{40, 90})
        == OverlayCursorStyle::brush);

    CHECK(router.pointerDown(rightWindow, PixelPoint{40, 90}));
    platform.shiftDown = true;
    platform.cursor = PixelPoint{180, 190};
    router.pointerMove(rightWindow, PixelPoint{180, 190});
    router.pointerUp(rightWindow, PixelPoint{180, 190});
    CHECK(router.annotationDocument().annotations().size() == 1U);
    const auto& created = router.annotationDocument().annotations().front();
    CHECK(created.kind == xxsnap::win::AnnotationKind::brush);
    CHECK(created.brushPath.has_value());
    CHECK(created.brushPath->points.size() == 2U);
    CHECK(created.style.strokeWidthDip == 7.0F);
    CHECK(created.style.strokePattern
        == xxsnap::win::AnnotationStrokePattern::dashLongShort);
    CHECK(!router.annotationDocument().selectedId().has_value());
    CHECK(router.presentations()[1].annotationPlan.lineHandles.empty());
}

void testDarkSelectionUsesMacLightToolCursors()
{
    FakePlatform platform;
    auto desktop = solidDesktop({10, 10, 10, 255});
    CHECK(desktop != nullptr);
    if (!desktop) return;
    setDesktopPixel(*desktop, PixelPoint{20, 100}, {255, 255, 255, 255});

    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true,
        desktop.get());
    createReadySelection(router);

    auto owner = router.presentations()[1];
    CHECK(router.cursorStyle(rightWindow, PixelPoint{40, 90})
        == OverlayCursorStyle::moveLight);
    CHECK(router.pointerDown(
        rightWindow, owner.toolbarItems[2].centerPhysical));
    CHECK(router.cursorStyle(rightWindow, PixelPoint{40, 90})
        == OverlayCursorStyle::brush);

    owner = router.presentations()[1];
    CHECK(router.pointerDown(
        rightWindow, owner.toolbarItems[3].centerPhysical));
    CHECK(router.cursorStyle(rightWindow, PixelPoint{40, 90})
        == OverlayCursorStyle::markerLight);
    CHECK(router.markerCursorStyle(true).has_value());
    CHECK((router.markerCursorStyle(true)->strokeColor
        == AnnotationColor{255, 255, 255, 255}));

    owner = router.presentations()[1];
    const auto eyedropper = std::find_if(
        owner.toolbarItems.begin(), owner.toolbarItems.end(),
        [](const auto& item) {
            return item.action == xxsnap::win::ToolbarAction::eyedropper;
        });
    CHECK(eyedropper != owner.toolbarItems.end());
    if (eyedropper == owner.toolbarItems.end()) return;
    CHECK(router.pointerDown(rightWindow, eyedropper->centerPhysical));
    router.pointerMove(rightWindow, PixelPoint{20, 100});
    CHECK(router.cursorStyle(rightWindow, PixelPoint{20, 100})
        == OverlayCursorStyle::eyedropper);
    router.pointerMove(rightWindow, PixelPoint{21, 100});
    CHECK(router.cursorStyle(rightWindow, PixelPoint{21, 100})
        == OverlayCursorStyle::eyedropperLight);
}

void testBrightSelectionKeepsMacDarkToolCursors()
{
    FakePlatform platform;
    auto desktop = solidDesktop({240, 240, 240, 255});
    CHECK(desktop != nullptr);
    if (!desktop) return;

    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true,
        desktop.get());
    createReadySelection(router);

    auto owner = router.presentations()[1];
    CHECK(router.pointerDown(
        rightWindow, owner.toolbarItems[2].centerPhysical));
    CHECK(router.cursorStyle(rightWindow, PixelPoint{40, 90})
        == OverlayCursorStyle::brush);

    owner = router.presentations()[1];
    CHECK(router.pointerDown(
        rightWindow, owner.toolbarItems[3].centerPhysical));
    CHECK(router.cursorStyle(rightWindow, PixelPoint{40, 90})
        == OverlayCursorStyle::marker);
}

void testMarkerToolUsesMacOptionsAndShiftSnapping()
{
    FakePlatform platform;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true);
    createReadySelection(router);
    auto owner = router.presentations()[1];
    CHECK(owner.toolbarItems[3].action == xxsnap::win::ToolbarAction::marker);
    CHECK(router.pointerDown(
        rightWindow, owner.toolbarItems[3].centerPhysical));
    owner = router.presentations()[1];
    CHECK(owner.toolbarItems[3].selected);
    CHECK(owner.markerOptions.has_value());
    if (!owner.markerOptions.has_value()) {
        return;
    }
    CHECK(owner.markerOptions->layout.toolbar.width == 306.0F);
    CHECK(owner.markerOptions->state.style().strokeWidthDip == 18.0F);
    CHECK((owner.markerOptions->state.style().strokeColor
        == AnnotationColor{179, 235, 0, 255}));
    CHECK(router.cursorStyle(rightWindow, PixelPoint{100, 100})
        == OverlayCursorStyle::marker);
    CHECK(router.markerCursorStyle().has_value());
    CHECK((router.markerCursorStyle()->strokeColor
        == AnnotationColor{179, 235, 0, 255}));
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.markerOptions->layout.strokeWidths[0])));
    CHECK(router.presentations()[1]
        .markerOptions->state.style().strokeWidthDip == 14.0F);

    CHECK(router.pointerDown(rightWindow, PixelPoint{40, 90}));
    platform.shiftDown = true;
    platform.cursor = PixelPoint{180, 140};
    router.pointerMove(rightWindow, PixelPoint{180, 140});
    router.pointerUp(rightWindow, PixelPoint{180, 140});
    CHECK(router.annotationDocument().annotations().size() == 1U);
    const auto& created = router.annotationDocument().annotations().front();
    CHECK(created.kind == xxsnap::win::AnnotationKind::marker);
    CHECK(created.markerLine.has_value());
    CHECK(created.style.strokeWidthDip == 14.0F);
    CHECK(router.annotationDocument().selectedId() == created.id);
    CHECK(router.presentations()[1].annotationPlan.lineHandles.size() == 2U);
}

void testEyedropperSamplesCopiesAndMeasuresLikeMac()
{
    FakePlatform platform;
    const auto desktop = solidDesktop({10, 20, 30, 255});
    CHECK(desktop != nullptr);
    if (!desktop) {
        return;
    }
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true,
        desktop.get());
    createReadySelection(router);
    const auto owner = router.presentations()[1];
    const auto eyedropper = std::find_if(
        owner.toolbarItems.begin(), owner.toolbarItems.end(),
        [](const auto& item) {
            return item.action == xxsnap::win::ToolbarAction::eyedropper;
        });
    CHECK(eyedropper != owner.toolbarItems.end());
    if (eyedropper == owner.toolbarItems.end()) {
        return;
    }
    CHECK(router.pointerDown(rightWindow, eyedropper->centerPhysical));
    const auto selectedOwner = router.presentations()[1];
    CHECK(std::find_if(
        selectedOwner.toolbarItems.begin(),
        selectedOwner.toolbarItems.end(),
        [](const auto& item) {
            return item.action == xxsnap::win::ToolbarAction::eyedropper
                && item.selected;
        }) != selectedOwner.toolbarItems.end());

    router.pointerMove(rightWindow, PixelPoint{20, 100});
    auto presentation = router.presentations()[1];
    CHECK(presentation.eyedropper.has_value());
    CHECK((presentation.eyedropper->color
        == AnnotationColor{10, 20, 30, 255}));
    CHECK(router.cursorStyle(rightWindow, PixelPoint{20, 100})
        == OverlayCursorStyle::eyedropperLight);
    CHECK(router.keyPressed(ShapeEditorKey::copy, false, false));
    CHECK(platform.copiedText == L"#0A141E");
    CHECK(router.presentations()[1]
        .eyedropper->copySuccessMillisecondsRemaining > 0U);
    CHECK(router.eyedropperShiftPressed());
    CHECK(router.keyPressed(ShapeEditorKey::copy, false, false));
    CHECK(platform.copiedText == L"10, 20, 30");

    CHECK(router.pointerDown(rightWindow, PixelPoint{20, 100}));
    router.pointerMove(rightWindow, PixelPoint{23, 104});
    CHECK(router.pointerDown(rightWindow, PixelPoint{23, 104}));
    presentation = router.presentations()[1];
    CHECK(presentation.eyedropper->measurementStart.has_value());
    CHECK(presentation.eyedropper->measurementEnd.has_value());
    CHECK(presentation.eyedropper->measurementLabel == L"5 px");

    CHECK(router.keyPressed(ShapeEditorKey::eyedropper, false, false));
    CHECK(!router.presentations()[1].eyedropper.has_value());
}

void testShapeCanBeCreatedOutsideLockedSelectionLikeMac()
{
    FakePlatform platform;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true);
    createReadySelection(router);

    auto owner = router.presentations()[1];
    CHECK(router.pointerDown(
        rightWindow, owner.toolbarItems[0].centerPhysical));
    CHECK(router.cursorStyle(rightWindow, PixelPoint{200, 20})
        == OverlayCursorStyle::crosshair);
    platform.cursor = PixelPoint{260, 60};
    CHECK(router.pointerDown(rightWindow, PixelPoint{200, 20}));
    router.pointerMove(rightWindow, *platform.cursor);
    router.pointerUp(rightWindow, *platform.cursor);
    CHECK(router.annotationDocument().annotations().size() == 1U);
    CHECK(router.annotationDocument().annotations().front().rect.y < 0.0F);
}

void testMosaicToolbarOptionsAndLiveComposite()
{
    FakePlatform platform;
    auto desktop = solidDesktop({40, 90, 140, 255});
    CHECK(desktop != nullptr);
    if (!desktop) {
        return;
    }
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true,
        desktop.get());
    createReadySelection(router);

    auto owner = router.presentations()[1];
    CHECK(owner.toolbarItems[5].action
        == xxsnap::win::ToolbarAction::mosaic);
    CHECK(router.pointerDown(
        rightWindow, owner.toolbarItems[5].centerPhysical));
    owner = router.presentations()[1];
    CHECK(owner.mosaicOptions.has_value());
    CHECK(owner.mosaicOptions->layout.toolbar.width == 252.0F);
    CHECK(owner.mosaicOptions->state.redaction().type
        == xxsnap::win::MosaicRedactionType::pixelMosaic);

    CHECK(router.pointerDown(rightWindow, PixelPoint{20, 100}));
    platform.cursor = PixelPoint{90, 150};
    router.pointerMove(rightWindow, PixelPoint{90, 150});
    router.pointerUp(rightWindow, PixelPoint{90, 150});
    CHECK(router.annotationDocument().annotations().size() == 1U);
    owner = router.presentations()[1];
    CHECK(owner.annotationComposite != nullptr);
    CHECK(owner.annotationPlan.items.size() == 1U);
    CHECK(owner.annotationPlanOutsideSelectionOnly);

    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.mosaicOptions->layout.redactionType)));
    owner = router.presentations()[1];
    CHECK(owner.mosaicOptions->state.redaction().type
        == xxsnap::win::MosaicRedactionType::gaussianBlur);
    const auto valueLayout = owner.mosaicOptions->layout;
    const PixelPoint valueStart{
        static_cast<std::int64_t>(
            valueLayout.valueTrack.x * 1.5F + 0.5F),
        static_cast<std::int64_t>(
            (valueLayout.valueTrack.y + 2.0F) * 1.5F + 0.5F),
    };
    CHECK(router.pointerDown(rightWindow, valueStart));
    platform.cursor = PixelPoint{
        static_cast<std::int64_t>((valueLayout.valueTrack.x
            + valueLayout.valueTrack.width) * 1.5F + 0.5F),
        valueStart.y,
    };
    router.pointerMove(rightWindow, platform.cursor.value());
    router.pointerUp(rightWindow, platform.cursor.value());
    owner = router.presentations()[1];
    CHECK(owner.mosaicOptions->state.redaction().value == 20);
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.mosaicOptions->layout.rectangleMode)));
    owner = router.presentations()[1];
    CHECK(owner.mosaicOptions->state.kind()
        == xxsnap::win::AnnotationKind::mosaicRectangle);
}

void testTextToolbarAcceptsUnicodeAndUsesRealPopupMenus()
{
    FakePlatform platform;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true);
    createReadySelection(router);
    auto owner = router.presentations()[1];
    CHECK(owner.toolbarItems[6].action == xxsnap::win::ToolbarAction::text);
    CHECK(router.keyPressed(ShapeEditorKey::text, false, false));
    owner = router.presentations()[1];
    CHECK(owner.textOptions.has_value());
    CHECK(owner.textOptions->state.style().textFontFamily
        == L"Microsoft YaHei");
    CHECK(router.pointerDown(rightWindow, PixelPoint{30, 100}));
    router.pointerUp(rightWindow, PixelPoint{30, 100});
    CHECK(router.textInput(L"中文"));
    CHECK(router.textInput(L"A"));
    CHECK(router.keyPressed(ShapeEditorKey::left, false, false));
    CHECK(router.textInput(L"测"));
    CHECK(router.keyPressed(ShapeEditorKey::text, false, false));
    CHECK(router.annotationDocument().annotations().size() == 1U);
    CHECK(*router.annotationDocument().annotations()[0].text == L"中文测A");

    owner = router.presentations()[1];
    CHECK(router.keyPressed(ShapeEditorKey::text, false, false));
    owner = router.presentations()[1];
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.textOptions->layout.fontFamily)));
    owner = router.presentations()[1];
    CHECK(owner.textOptions->popupMenu.has_value());
    CHECK(!owner.textOptions->popupLabels.empty());
    if (!owner.textOptions->popupLabels.empty()) {
        CHECK(owner.textOptions->popupLabels[0] == L"Microsoft YaHei");
    }
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.textOptions->layout.textSize)));
    owner = router.presentations()[1];
    CHECK(owner.textOptions->popupMenu.has_value());
    CHECK(owner.textOptions->selectedPopupIndex.has_value());
    if (owner.textOptions->selectedPopupIndex.has_value()) {
        CHECK(owner.textOptions->popupLabels[
            *owner.textOptions->selectedPopupIndex] == L"8");
    }
}

void testNumberToolbarCreatesSequenceAndSupportsDoubleClickEditing()
{
    FakePlatform platform;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true);
    createReadySelection(router);
    CHECK(router.keyPressed(ShapeEditorKey::number, false, false));
    auto owner = router.presentations()[1];
    CHECK(owner.numberOptions.has_value());
    CHECK(owner.numberOptions->state.style().textSize == 3.0F);
    auto cursor = router.numberCursorState();
    CHECK(cursor.has_value());
    CHECK(cursor->type == NumberMarkType::number);
    CHECK(cursor->value == 1);
    CHECK(cursor->color == owner.numberOptions->state.style().strokeColor);
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.numberOptions->layout.markType)));
    owner = router.presentations()[1];
    CHECK(owner.numberOptions->popupMenu.has_value());
    CHECK(owner.numberOptions->popupLabels.size() == 3U);
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.numberOptions->layout.markType)));

    platform.cursor = PixelPoint{30, 100};
    CHECK(router.pointerDown(rightWindow, PixelPoint{30, 100}));
    router.pointerUp(rightWindow, PixelPoint{30, 100});
    cursor = router.numberCursorState();
    CHECK(cursor.has_value());
    CHECK(cursor->value == 2);
    platform.cursor = PixelPoint{100, 100};
    CHECK(router.pointerDown(rightWindow, PixelPoint{100, 100}));
    router.pointerUp(rightWindow, PixelPoint{100, 100});
    CHECK(router.annotationDocument().annotations().size() == 2U);
    CHECK(router.annotationDocument().annotations()[0].numberSequenceIndex == 1);
    CHECK(router.annotationDocument().annotations()[1].numberSequenceIndex == 2);

    CHECK(router.pointerDown(rightWindow, PixelPoint{30, 100}, 2));
    CHECK(router.isEditingInlineValue());
    CHECK(router.keyPressed(ShapeEditorKey::backspace, false, false));
    CHECK(router.textInput(L"9"));
    CHECK(router.keyPressed(ShapeEditorKey::enter, false, false));
    CHECK(router.annotationDocument().annotations()[0].numberSequenceIndex == 9);
    CHECK(router.annotationDocument().annotations()[0].numberSequenceIsManual);
}

void testMagnifierToolbarMatchesMacOptionsAndUsesComposite()
{
    FakePlatform platform;
    auto desktop = solidDesktop({40, 90, 140, 255});
    CHECK(desktop != nullptr);
    if (!desktop) return;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true,
        desktop.get());
    createReadySelection(router);
    CHECK(router.keyPressed(ShapeEditorKey::magnifier, false, false));
    auto owner = router.presentations()[1];
    CHECK(owner.toolbarItems.size() == 17U);
    CHECK(owner.toolbarItems[8].action
        == xxsnap::win::ToolbarAction::magnifier);
    CHECK(owner.toolbarItems[8].selected);
    CHECK(owner.magnifierOptions.has_value());
    CHECK(owner.magnifierOptions->layout.toolbar.width == 440.0F);
    CHECK(owner.magnifierOptions->state.shape()
        == xxsnap::win::MagnifierShape::rectangle);
    CHECK(owner.magnifierOptions->state.zoom() == 2.0F);
    CHECK((owner.magnifierOptions->state.style().strokeColor
        == AnnotationColor{0, 122, 255, 255}));

    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.magnifierOptions->layout.circleMode)));
    owner = router.presentations()[1];
    CHECK(owner.magnifierOptions->state.shape()
        == xxsnap::win::MagnifierShape::circle);
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.magnifierOptions->layout.zoom)));
    owner = router.presentations()[1];
    CHECK(owner.magnifierOptions->zoomMenu.has_value());
    CHECK(owner.magnifierOptions->zoomMenu->items.size() == 4U);
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.magnifierOptions->zoomMenu->items[2])));
    owner = router.presentations()[1];
    CHECK(owner.magnifierOptions->state.zoom() == 3.0F);
    CHECK(!owner.magnifierOptions->zoomMenu.has_value());
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.magnifierOptions->layout.colorSwatches.back())));
    CHECK(platform.chooseColorCalls == 1);
    CHECK(platform.chosenColorWindow == rightWindow);
    owner = router.presentations()[1];
    CHECK((owner.magnifierOptions->state.style().strokeColor
        == AnnotationColor{1, 2, 3, 255}));

    platform.shiftDown = true;
    platform.cursor = PixelPoint{20, 100};
    CHECK(router.pointerDown(rightWindow, PixelPoint{20, 100}));
    platform.cursor = PixelPoint{90, 140};
    router.pointerMove(rightWindow, *platform.cursor);
    router.pointerUp(rightWindow, *platform.cursor);
    CHECK(router.annotationDocument().annotations().size() == 1U);
    const auto& annotation = router.annotationDocument().annotations()[0];
    CHECK(isMagnifierAnnotation(annotation));
    CHECK(annotation.magnifierShape
        == xxsnap::win::MagnifierShape::circle);
    CHECK(annotation.magnifierZoom == 3.0F);
    CHECK((annotation.style.strokeColor == AnnotationColor{1, 2, 3, 255}));
    CHECK(annotation.rect.width == annotation.rect.height);
    owner = router.presentations()[1];
    CHECK(owner.annotationComposite == nullptr);
    CHECK(owner.annotationPlan.items.size() == 1U);
    CHECK(!owner.annotationPlan.resizeHandles.empty());
    CHECK(!owner.annotationPlan.rotationHandle.has_value());
}

void testEraserToolbarUsesMacLayoutAndModes()
{
    FakePlatform platform;
    auto desktop = solidDesktop({40, 90, 140, 255});
    CHECK(desktop != nullptr);
    if (!desktop) return;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true,
        desktop.get());
    createReadySelection(router);
    CHECK(router.keyPressed(ShapeEditorKey::eraser, false, false));
    auto owner = router.presentations()[1];
    CHECK(owner.toolbarItems[9].action
        == xxsnap::win::ToolbarAction::eraser);
    CHECK(owner.toolbarItems[9].selected);
    CHECK(owner.eraserOptions.has_value());
    CHECK((owner.eraserOptions->layout.toolbar
        == AnnotationRect{owner.eraserOptions->layout.toolbar.x,
            owner.eraserOptions->layout.toolbar.y, 100, 28}));
    CHECK(owner.eraserOptions->mode == xxsnap::win::EraserMode::point);
    CHECK(router.cursorStyle(rightWindow, PixelPoint{40, 90})
        == OverlayCursorStyle::eraserLight);
    setDesktopPixel(*desktop, PixelPoint{40, 90}, {255, 255, 255, 255});
    CHECK(router.cursorStyle(rightWindow, PixelPoint{40, 90})
        == OverlayCursorStyle::eraser);
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.eraserOptions->layout.rectangleMode)));
    owner = router.presentations()[1];
    CHECK(owner.eraserOptions->mode == xxsnap::win::EraserMode::rectangle);
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.eraserOptions->layout.pointMode)));
    CHECK(router.presentations()[1].eraserOptions->mode
        == xxsnap::win::EraserMode::point);
}

void testRectangleEraserRoutesFromOutsideLockedSelection()
{
    FakePlatform platform;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform, {}, true);
    createReadySelection(router);
    const auto lockedSelection = router.selection();

    auto owner = router.presentations()[1];
    CHECK(router.pointerDown(rightWindow, owner.toolbarItems[0].centerPhysical));
    CHECK(router.pointerDown(rightWindow, PixelPoint{10, 100}));
    platform.cursor = PixelPoint{100, 180};
    router.pointerMove(rightWindow, PixelPoint{100, 180});
    router.pointerUp(rightWindow, PixelPoint{100, 180});
    CHECK(router.annotationDocument().annotations().size() == 1U);
    const auto annotationId = router.annotationDocument().annotations()[0].id;

    CHECK(router.keyPressed(ShapeEditorKey::eraser, false, false));
    owner = router.presentations()[1];
    CHECK(owner.eraserOptions.has_value());
    CHECK(router.pointerDown(rightWindow, dipCenterAt144Dpi(
        owner.eraserOptions->layout.rectangleMode)));
    CHECK(router.cursorStyle(rightWindow, PixelPoint{200, 200})
        == OverlayCursorStyle::crosshair);
    const auto capturesBefore = platform.captureCalls;
    CHECK(router.pointerDown(rightWindow, PixelPoint{200, 200}));
    CHECK(platform.captureCalls == capturesBefore + 1);
    platform.cursor = PixelPoint{40, 120};
    router.pointerMove(rightWindow, PixelPoint{40, 120});
    CHECK(router.presentations()[1].annotationPlan.eraserPreview.has_value());
    router.pointerUp(rightWindow, PixelPoint{40, 120});
    CHECK(router.phase() == SelectionPhase::ready);
    CHECK(router.selection() == lockedSelection);
    CHECK(router.annotationDocument().eraserMasks().size() == 1U);
    CHECK((router.annotationDocument().eraserMasks()[0].affectedAnnotationIds
        == std::vector<xxsnap::win::AnnotationId>{annotationId}));
}

void testTextRecognitionAutoCompletesWithoutCaptureChrome()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    OverlayInputRouter router(
        PixelRect{-640, 0, 1280, 360}, surfaces(), platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        false, nullptr, OverlayMode::textRecognition);
    auto presentations = router.presentations();
    CHECK(presentations.size() == 2U);
    CHECK(presentations[0].textRecognition);
    CHECK(presentations[1].textRecognition);
    CHECK(!presentations[0].showActions);
    CHECK(!presentations[1].showActions);
    CHECK(presentations[0].toolbarItems.empty());
    CHECK(router.cursorStyle(leftWindow, PixelPoint{300, 100})
        == OverlayCursorStyle::crosshair);

    CHECK(router.pointerDown(leftWindow, PixelPoint{500, 80}));
    platform.cursor = PixelPoint{120, 280};
    router.pointerMove(leftWindow, PixelPoint{500, 80});
    router.pointerUp(leftWindow, PixelPoint{500, 80});
    CHECK(router.status() == OverlayInputStatus::completed);
    CHECK(actions == std::vector<OverlayInputAction>{
        OverlayInputAction::recognizeText});
    CHECK((router.selection() == PixelRect{-140, 80, 260, 200}));
}

void testTeachingPenStartsFullScreenWithBrushAndHiddenToolbar()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    const auto window = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(3));
    OverlayInputRouter router(
        PixelRect{0, 0, 800, 600},
        {{window, PixelRect{0, 0, 800, 600}, 96, 96}},
        platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true, nullptr, OverlayMode::teachingPen);

    CHECK(router.phase() == SelectionPhase::ready);
    CHECK((router.selection() == PixelRect{0, 0, 800, 600}));
    const auto hidden = router.presentations().front();
    CHECK(hidden.teachingPen);
    CHECK(!hidden.showActions);
    CHECK(hidden.toolbarItems.empty());
    CHECK(router.cursorStyle(window, {100, 100})
        == OverlayCursorStyle::brush);
    platform.cursor = PixelPoint{160, 140};
    CHECK(router.pointerDown(window, {100, 100}));
    router.pointerMove(window, {160, 140});
    router.pointerUp(window, {160, 140});
    CHECK(router.cursorStyle(window, {120, 120})
        == OverlayCursorStyle::brush);

    CHECK(router.rightPointerDown(window, {360, 420}));
    const auto shown = router.presentations().front();
    CHECK(shown.showActions);
    CHECK(shown.toolbarItems.size()
        == xxsnap::win::teachingPenToolbarActions().size());
    CHECK(shown.toolbarItems.front().action == xxsnap::win::ToolbarAction::pen);
    CHECK(shown.toolbarItems.front().selected);
    CHECK((shown.toolbarItems.front().rectPhysical
        == PixelRect{370, 222, 20, 20}));

    CHECK(router.rightPointerDown(window, {360, 420}));
    CHECK(!router.presentations().front().showActions);
    CHECK(actions.empty());
}

void testTeachingPenToolbarSelectionAndCanvasDrawingMatchMac()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    const auto window = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(3));
    OverlayInputRouter router(
        PixelRect{0, 0, 800, 600},
        {{window, PixelRect{0, 0, 800, 600}, 96, 96}},
        platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true, nullptr, OverlayMode::teachingPen);

    CHECK(router.rightPointerDown(window, {360, 420}));
    const auto shown = router.presentations().front();
    const auto rectangle = std::find_if(
        shown.toolbarItems.begin(), shown.toolbarItems.end(), [](const auto& item) {
            return item.action == xxsnap::win::ToolbarAction::rectangle;
        });
    CHECK(rectangle != shown.toolbarItems.end());
    if (rectangle == shown.toolbarItems.end()) return;
    CHECK(router.pointerDown(window, rectangle->centerPhysical));
    const auto rectangleOptions = router.presentations().front();
    CHECK(rectangleOptions.showActions);
    CHECK(rectangleOptions.shapeOptions.has_value());
    if (rectangleOptions.shapeOptions.has_value()) {
        CHECK(rectangleOptions.shapeOptions->state.style().cornerRadiusDip
            == 0.0F);
        CHECK(!rectangleOptions.shapeOptions->cornerRadiusPanel.has_value());
    }

    platform.cursor = PixelPoint{180, 160};
    CHECK(router.pointerDown(window, {100, 100}));
    router.pointerMove(window, {180, 160});
    router.pointerUp(window, {180, 160});
    CHECK(!router.presentations().front().showActions);
    CHECK(router.annotationDocument().annotations().size() == 1U);
    CHECK(router.annotationDocument().annotations().front().kind
        == xxsnap::win::AnnotationKind::rectangle);
    CHECK(router.annotationDocument().annotations().front()
        .style.cornerRadiusDip == 0.0F);

    CHECK(router.rightPointerDown(window, {360, 420}));
    const auto clearToolbar = router.presentations().front();
    const auto clearAll = std::find_if(
        clearToolbar.toolbarItems.begin(), clearToolbar.toolbarItems.end(),
        [](const auto& item) {
            return item.action == xxsnap::win::ToolbarAction::clearAll;
        });
    CHECK(clearAll != clearToolbar.toolbarItems.end());
    if (clearAll != clearToolbar.toolbarItems.end()) {
        CHECK(router.pointerDown(window, clearAll->centerPhysical));
    }
    CHECK(router.annotationDocument().annotations().empty());
    CHECK(router.status() == OverlayInputStatus::active);
}

void testTeachingPenTextDefaultsToNoOutline()
{
    FakePlatform platform;
    const auto window = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(3));
    OverlayInputRouter router(
        PixelRect{0, 0, 800, 600},
        {{window, PixelRect{0, 0, 800, 600}, 96, 96}},
        platform, [](OverlayInputAction) {}, true, nullptr,
        OverlayMode::teachingPen);

    CHECK(router.rightPointerDown(window, {360, 420}));
    const auto shown = router.presentations().front();
    const auto textTool = std::find_if(
        shown.toolbarItems.begin(), shown.toolbarItems.end(), [](const auto& item) {
            return item.action == xxsnap::win::ToolbarAction::text;
        });
    CHECK(textTool != shown.toolbarItems.end());
    if (textTool == shown.toolbarItems.end()) return;
    CHECK(router.pointerDown(window, textTool->centerPhysical));
    const auto selected = router.presentations().front();
    CHECK(selected.textOptions.has_value());
    if (selected.textOptions.has_value()) {
        CHECK(!selected.textOptions->state.style().textOutlineEnabled);
    }
}

void testTeachingPenEscapeAndCopyUseMacCompletionSemantics()
{
    FakePlatform platform;
    std::vector<OverlayInputAction> actions;
    const auto window = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(3));
    OverlayInputRouter router(
        PixelRect{0, 0, 800, 600},
        {{window, PixelRect{0, 0, 800, 600}, 96, 96}},
        platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true, nullptr, OverlayMode::teachingPen);

    router.escapePressed();
    CHECK(router.status() == OverlayInputStatus::active);
    CHECK(actions.empty());
    router.escapePressed();
    CHECK(router.status() == OverlayInputStatus::cancelled);
    CHECK(actions == std::vector<OverlayInputAction>{OverlayInputAction::cancel});

    actions.clear();
    OverlayInputRouter copyRouter(
        PixelRect{0, 0, 800, 600},
        {{window, PixelRect{0, 0, 800, 600}, 96, 96}},
        platform,
        [&actions](OverlayInputAction action) { actions.push_back(action); },
        true, nullptr, OverlayMode::teachingPen);
    CHECK(copyRouter.rightPointerDown(window, {360, 420}));
    const auto shown = copyRouter.presentations().front();
    const auto copy = std::find_if(
        shown.toolbarItems.begin(), shown.toolbarItems.end(), [](const auto& item) {
            return item.action == xxsnap::win::ToolbarAction::copy;
        });
    CHECK(copy != shown.toolbarItems.end());
    if (copy != shown.toolbarItems.end()) {
        CHECK(copyRouter.pointerDown(window, copy->centerPhysical));
    }
    CHECK(copyRouter.status() == OverlayInputStatus::completed);
    CHECK(actions == std::vector<OverlayInputAction>{OverlayInputAction::copy});
    CHECK((copyRouter.selection() == PixelRect{0, 0, 800, 600}));
}

void testLongImageViewportKeepsAnnotationsInFullImageCoordinates()
{
    FakePlatform platform;
    const auto window = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(4));
    OverlayInputRouter router(
        PixelRect{100, 100, 300, 600},
        {{window, PixelRect{100, 100, 300, 600}, 96, 96}},
        platform, [](OverlayInputAction) {}, true, nullptr,
        OverlayMode::longImageEditor);
    router.lockSelection({100, 100, 300, 600});
    router.setAnnotationViewport(
        {0.0F, 500.0F}, 2.0F,
        {0.0F, 0.0F, 300.0F, 2000.0F}, nullptr);
    CHECK(router.keyPressed(ShapeEditorKey::rectangle, false, false));
    CHECK(router.pointerDown(window, {20, 100}));
    CHECK(platform.captureCalls == 1);
    CHECK(!router.longImageScrollAllowed());
    platform.cursor = PixelPoint{180, 250};
    router.pointerMove(window, {80, 150});
    router.pointerUp(window, {80, 150});
    CHECK(router.longImageScrollAllowed());
    CHECK(router.annotationDocument().annotations().size() == 1U);
    if (router.annotationDocument().annotations().empty()) return;
    CHECK((router.annotationDocument().annotations().front().rect
        == AnnotationRect{10.0F, 550.0F, 30.0F, 25.0F}));
    const auto first = router.presentations().front();
    CHECK(first.annotationPlan.items.size() == 1U);
    if (!first.annotationPlan.items.empty()) {
        CHECK((first.annotationPlan.items.front().annotation.rect
            == AnnotationRect{20.0F, 100.0F, 60.0F, 50.0F}));
    }
    router.setAnnotationViewport(
        {0.0F, 800.0F}, 2.0F,
        {0.0F, 0.0F, 300.0F, 2000.0F}, nullptr);
    const auto scrolled = router.presentations().front();
    CHECK(scrolled.annotationPlan.items.size() == 1U);
    if (!scrolled.annotationPlan.items.empty()) {
        CHECK(scrolled.annotationPlan.items.front().annotation.rect.y == -500.0F);
    }
}

} // namespace

int main()
{
    testCrossWindowRoutingUsesVirtualPhysicalCoordinates();
    testActionHandleBodyAndBlankPriority();
    testAllToolbarActionsFireExactlyOnceWithoutStartingCapture();
    testPinToolbarTransfersTheReadySelection();
    testCtrlOnePinsTheReadySelection();
    testPinnedImageEditorLocksSelectionAndFinishesWithoutCaptureActions();
    testPinnedImageEditorEscapeFinishesInsteadOfCancelling();
    testLongImageEditorEscapeFinishesInsteadOfCancelling();
    testPinnedImageEditorStandaloneShiftRequestsToolbarHideOnRelease();
    testPinnedImageEditorShiftToggleCancelsForMixedInput();
    testPinnedImageEditorAlwaysOnTopShortcutIsNonTerminal();
    testToolbarPresentationUsesSharedPhysicalRects();
    testOnePixelOutsideToolbarItemsDoesNotFireAction();
    testCancelSourcesAreIdempotentAndCaptureFailureFailsClosed();
    testEscapeRegistrationLifecycleIsExplicit();
    testEscapeUnregisterFailureIsObservableAndRetriedOnDestruction();
    testTerminalCallbackMaySynchronouslyDestroyRouter();
    testRestartShutdownReleasesCaptureAndHotKeyWithoutCancelAction();
    testScrollToolbarSuspendsOverlayWithoutCompletingRouter();
    testScrollCapturePreservesOverlayWindowsForSuspensionAndResume();
    testToolbarHoverShowsMacShortcutTipAndRStartsScrollCapture();
    testMacToolShortcutsSelectToolsAndDoNotInterruptInlineText();
    testControlToolbarShortcutsRouteThroughCatalog();
    testShapeToolIsNonTerminalAndEditsThroughSharedPresentation();
    testArrowToolUsesMacOptionsMenuAndCreatesEditableCurve();
    testBrushToolUsesMacOptionsAndShiftStraightLine();
    testDarkSelectionUsesMacLightToolCursors();
    testBrightSelectionKeepsMacDarkToolCursors();
    testMarkerToolUsesMacOptionsAndShiftSnapping();
    testEyedropperSamplesCopiesAndMeasuresLikeMac();
    testShapeCanBeCreatedOutsideLockedSelectionLikeMac();
    testMosaicToolbarOptionsAndLiveComposite();
    testTextToolbarAcceptsUnicodeAndUsesRealPopupMenus();
    testNumberToolbarCreatesSequenceAndSupportsDoubleClickEditing();
    testMagnifierToolbarMatchesMacOptionsAndUsesComposite();
    testEraserToolbarUsesMacLayoutAndModes();
    testRectangleEraserRoutesFromOutsideLockedSelection();
    testTextRecognitionAutoCompletesWithoutCaptureChrome();
    testTeachingPenStartsFullScreenWithBrushAndHiddenToolbar();
    testTeachingPenToolbarSelectionAndCanvasDrawingMatchMac();
    testTeachingPenTextDefaultsToNoOutline();
    testTeachingPenEscapeAndCopyUseMacCompletionSemantics();
    testLongImageViewportKeepsAnnotationsInFullImageCoordinates();
    return failureCount == 0 ? 0 : 1;
}
