#include "overlay/OverlayHost.h"

#include <cstdint>
#include <iostream>
#include <memory>
#include <optional>
#include <vector>

namespace {

using snipory::core::portable::PixelPoint;
using snipory::core::portable::PixelRect;
using xxsnap::win::OverlayInputAction;
using xxsnap::win::OverlayInputPlatform;
using xxsnap::win::OverlayInputRouter;
using xxsnap::win::OverlayInputStatus;
using xxsnap::win::OverlayCursorStyle;
using xxsnap::win::OverlaySurface;
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

    std::optional<AnnotationColor> chooseColor(
        HWND window,
        AnnotationColor) noexcept override
    {
        ++chooseColorCalls;
        chosenColorWindow = window;
        return chosenColor;
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
    int chooseColorCalls = 0;
    HWND chosenColorWindow = nullptr;
    std::optional<AnnotationColor> chosenColor = AnnotationColor{1, 2, 3, 255};
};

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
    CHECK(owner.toolbarItems.size() == 7U);
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
    CHECK(owner.toolbarItems[2].action == xxsnap::win::ToolbarAction::undo);
    CHECK(owner.toolbarItems[2].enabled);
    CHECK(router.pointerDown(rightWindow, owner.toolbarItems[2].centerPhysical));
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
    CHECK(owner.toolbarItems.size() == 7U);
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

void testShapeCanBeCreatedOutsideLockedSelectionOnOverlay()
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

    CHECK(router.pointerDown(rightWindow, PixelPoint{200, 20}));
    CHECK(router.cursorStyle(rightWindow, PixelPoint{320, 60})
        == OverlayCursorStyle::crosshair);
    router.platformPointerMove(PixelPoint{320, 60});
    router.platformPointerUp(PixelPoint{320, 60});

    CHECK(router.annotationDocument().annotations().size() == 1U);
    if (!router.annotationDocument().annotations().empty()) {
        const auto rect = router.annotationDocument().annotations()[0].rect;
        CHECK(rect.y < 0.0F);
        CHECK(rect.width > 70.0F);
        CHECK(rect.height > 20.0F);
    }

    CHECK(router.cursorStyle(rightWindow, PixelPoint{235, 20})
        == OverlayCursorStyle::move);
    CHECK(router.pointerDown(rightWindow, PixelPoint{235, 20}));
    CHECK(router.cursorStyle(rightWindow, PixelPoint{400, 100})
        == OverlayCursorStyle::move);
    router.platformPointerUp(PixelPoint{235, 20});
}

} // namespace

int main()
{
    testCrossWindowRoutingUsesVirtualPhysicalCoordinates();
    testActionHandleBodyAndBlankPriority();
    testAllToolbarActionsFireExactlyOnceWithoutStartingCapture();
    testToolbarPresentationUsesSharedPhysicalRects();
    testOnePixelOutsideToolbarItemsDoesNotFireAction();
    testCancelSourcesAreIdempotentAndCaptureFailureFailsClosed();
    testEscapeRegistrationLifecycleIsExplicit();
    testEscapeUnregisterFailureIsObservableAndRetriedOnDestruction();
    testTerminalCallbackMaySynchronouslyDestroyRouter();
    testRestartShutdownReleasesCaptureAndHotKeyWithoutCancelAction();
    testShapeToolIsNonTerminalAndEditsThroughSharedPresentation();
    testArrowToolUsesMacOptionsMenuAndCreatesEditableCurve();
    testShapeCanBeCreatedOutsideLockedSelectionOnOverlay();
    return failureCount == 0 ? 0 : 1;
}
