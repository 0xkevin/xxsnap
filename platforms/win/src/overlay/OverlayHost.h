#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "capture/CaptureBackend.h"
#include "annotation/ShapeEditorController.h"
#include "overlay/OverlayWindow.h"
#include "overlay/SelectionModel.h"
#include "toolbar/ToolbarCatalog.h"

#include <Windows.h>

#include <array>
#include <chrono>
#include <cstddef>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace xxsnap::win {

enum class OverlayInputAction {
    cancel,
    pin,
    save,
    copy,
    scrollCapture,
    finishEditing,
    hideEditingToolbar,
    togglePinnedImageAlwaysOnTop,
    recognizeText,
};

constexpr bool overlayActionPreservesWindows(
    OverlayInputAction action) noexcept
{
    return action == OverlayInputAction::scrollCapture
        || action == OverlayInputAction::togglePinnedImageAlwaysOnTop;
}

enum class OverlayInputStatus {
    active,
    cancelled,
    completed,
};

enum class OverlayInputErrorCode {
    mouseCaptureFailed,
    cursorPositionFailed,
    mouseReleaseFailed,
    escapeHotKeyRegistrationFailed,
    escapeHotKeyUnregistrationFailed,
};

struct OverlaySurface {
    HWND window = nullptr;
    PixelRect physicalBounds{};
    UINT dpiX = 96;
    UINT dpiY = 96;
};

enum class OverlayMode {
    capture,
    pinnedImageEditor,
    longImageEditor,
    textRecognition,
    teachingPen,
};

struct NumberCursorState {
    NumberMarkType type = NumberMarkType::number;
    int value = 1;
    AnnotationColor color{};
};

struct OverlayPresentationToolbarItem {
    ToolbarAction action;
    PixelRect rectPhysical{};
    PixelPoint centerPhysical{};
    bool selected = false;
    bool enabled = true;
};

struct OverlayPresentationShapeOptions {
    ShapeOptionsLayout layout;
    ShapeOptionsState state;
    std::optional<StrokePatternMenuLayout> strokePatternMenu;
    std::optional<CornerRadiusPanelLayout> cornerRadiusPanel;
};

struct OverlayPresentationArrowLineOptions {
    ArrowLineOptionsLayout layout;
    ArrowLineOptionsState state;
    std::optional<StrokePatternMenuLayout> strokePatternMenu;
    std::optional<ArrowTypeMenuLayout> arrowTypeMenu;
    std::optional<ArrowEndpoint> arrowTypeMenuEndpoint;
};

struct OverlayPresentationBrushOptions {
    BrushOptionsLayout layout;
    BrushOptionsState state;
    std::optional<StrokePatternMenuLayout> strokePatternMenu;
};

struct OverlayPresentationMarkerOptions {
    MarkerOptionsLayout layout;
    MarkerOptionsState state;
};

struct OverlayPresentationMosaicOptions {
    MosaicOptionsLayout layout;
    MosaicOptionsState state;
};

struct OverlayPresentationTextOptions {
    TextOptionsLayout layout;
    TextOptionsState state;
    std::optional<PopupMenuLayout> popupMenu;
    std::vector<std::wstring> popupLabels;
    std::optional<std::size_t> selectedPopupIndex;
};

struct OverlayPresentationNumberOptions {
    NumberOptionsLayout layout;
    NumberOptionsState state;
    std::optional<PopupMenuLayout> popupMenu;
    std::optional<NumberPopupMenu> popupKind;
    std::vector<std::wstring> popupLabels;
    std::optional<std::size_t> selectedPopupIndex;
};

struct OverlayPresentationMagnifierOptions {
    MagnifierOptionsLayout layout;
    MagnifierOptionsState state;
    std::optional<PopupMenuLayout> zoomMenu;
};

struct OverlayPresentationEraserOptions {
    EraserOptionsLayout layout;
    EraserMode mode = EraserMode::point;
};

struct OverlayPresentationEyedropper {
    AnnotationPoint pointer{};
    AnnotationColor color{};
    std::array<AnnotationColor, 81> magnifier{};
    EyedropperCopyMode copyMode = EyedropperCopyMode::hex;
    std::uint32_t copySuccessMillisecondsRemaining = 0;
    std::optional<AnnotationPoint> measurementStart;
    std::optional<AnnotationPoint> measurementEnd;
    std::wstring measurementLabel;
};

struct OverlayPresentationToolbarTooltip {
    std::wstring text;
    PixelRect anchor{};
};

struct OverlayPresentation {
    std::optional<PixelRect> selection;
    bool showActions = false;
    bool pinnedImageEditor = false;
    bool textRecognition = false;
    bool teachingPen = false;
    std::optional<MainToolbarLayout> teachingPenToolbar;
    std::vector<OverlayPresentationToolbarItem> toolbarItems;
    std::optional<OverlayPresentationToolbarTooltip> toolbarTooltip;
    AnnotationRenderPlan annotationPlan;
    std::shared_ptr<const PixelBuffer> annotationComposite;
    bool annotationPlanOutsideSelectionOnly = false;
    std::optional<OverlayPresentationShapeOptions> shapeOptions;
    std::optional<OverlayPresentationArrowLineOptions> arrowLineOptions;
    std::optional<OverlayPresentationBrushOptions> brushOptions;
    std::optional<OverlayPresentationMarkerOptions> markerOptions;
    std::optional<OverlayPresentationMosaicOptions> mosaicOptions;
    std::optional<OverlayPresentationTextOptions> textOptions;
    std::optional<OverlayPresentationNumberOptions> numberOptions;
    std::optional<OverlayPresentationMagnifierOptions> magnifierOptions;
    std::optional<OverlayPresentationEraserOptions> eraserOptions;
    std::optional<OverlayPresentationEyedropper> eyedropper;
};

class OverlayInputPlatform {
public:
    virtual ~OverlayInputPlatform() = default;

    virtual bool captureMouse(HWND window) noexcept = 0;
    virtual bool releaseMouse() noexcept = 0;
    virtual std::optional<PixelPoint> cursorPosition() noexcept = 0;
    virtual bool registerEscapeHotKey(HWND window, int identifier) noexcept = 0;
    virtual bool unregisterEscapeHotKey(HWND window, int identifier) noexcept = 0;
    virtual bool registerEditorHotKeys(HWND) noexcept { return true; }
    virtual bool unregisterEditorHotKeys(HWND) noexcept { return true; }
    virtual bool registerToolbarHotKeys(HWND) noexcept { return true; }
    virtual bool unregisterToolbarHotKeys(HWND) noexcept { return true; }
    virtual std::optional<AnnotationColor> chooseColor(
        HWND, AnnotationColor) noexcept
    {
        return std::nullopt;
    }
    virtual bool copyText(const std::wstring&) noexcept { return false; }
    virtual bool shiftPressed() noexcept
    {
        return (GetKeyState(VK_SHIFT) & 0x8000) != 0;
    }
};

class OverlayInputRouter final {
public:
    using ActionCallback = std::function<void(OverlayInputAction)>;

    OverlayInputRouter(
        PixelRect virtualBounds,
        std::vector<OverlaySurface> surfaces,
        OverlayInputPlatform& platform,
        ActionCallback actionCallback,
        bool shapeAnnotationsEnabled = false,
        const FrozenDesktop* desktop = nullptr,
        OverlayMode mode = OverlayMode::capture);
    void lockSelection(PixelRect selection) noexcept;
    void setAnnotationViewport(
        AnnotationPoint origin,
        float scale,
        AnnotationRect canvasBounds,
        const FrozenDesktop* desktop) noexcept;
    ~OverlayInputRouter();

    OverlayInputRouter(const OverlayInputRouter&) = delete;
    OverlayInputRouter& operator=(const OverlayInputRouter&) = delete;

    bool activateEscapeHotKey(HWND owner) noexcept;
    bool deactivateEscapeHotKey() noexcept;
    bool pointerDown(HWND source, PixelPoint clientPoint,
        int clickCount = 1) noexcept;
    bool rightPointerDown(HWND source, PixelPoint clientPoint) noexcept;
    void pointerMove(HWND source, PixelPoint clientPoint) noexcept;
    void pointerLeave(HWND source) noexcept;
    void pointerUp(HWND source, PixelPoint clientPoint) noexcept;
    OverlayCursorStyle cursorStyle(
        HWND source, PixelPoint clientPoint) const noexcept;
    void platformPointerMove(PixelPoint virtualPoint) noexcept;
    void platformPointerUp(PixelPoint virtualPoint) noexcept;
    void captureChanged() noexcept;
    void cancelMode() noexcept;
    void escapePressed() noexcept;
    void cancelPressed() noexcept;
    bool keyPressed(
        ShapeEditorKey key,
        bool control,
        bool shift) noexcept;
    bool toolbarShortcutPressed(
        std::uint32_t virtualKey,
        bool control,
        bool shift,
        bool alt) noexcept;
    void synchronizeToolbarHotKeys() noexcept;
    bool textInput(std::wstring text);
    bool mouseWheel(int delta) noexcept;
    bool longImageScrollAllowed() const noexcept;
    bool isEditingInlineValue() const noexcept;
    bool eyedropperShiftPressed() noexcept;
    bool pinnedImageShiftChanged(
        bool pressed, bool control, bool alt) noexcept;
    void cancelPinnedImageShiftShortcut() noexcept;
    bool togglePinnedImageAlwaysOnTop() noexcept;
    void shutdownForRestart() noexcept;

    OverlayInputStatus status() const noexcept;
    std::optional<OverlayInputErrorCode> lastError() const noexcept;
    SelectionPhase phase() const noexcept;
    std::optional<PixelRect> selection() const noexcept;
    std::vector<OverlayPresentation> presentations() const;
    const AnnotationDocument& annotationDocument() const noexcept;
    std::pair<UINT, UINT> annotationDpi() const noexcept;
    std::optional<AnnotationStyle> markerCursorStyle(
        bool light = false) const noexcept;
    std::optional<AnnotationStyle> mosaicCursorStyle() const noexcept;
    std::optional<NumberCursorState> numberCursorState() const noexcept;

private:
    const OverlaySurface* surfaceFor(HWND window) const noexcept;
    PixelPoint toVirtual(
        const OverlaySurface& surface, PixelPoint clientPoint) const noexcept;
    SelectionHandle selectionResizeHandleAt(
        const OverlaySurface& surface, PixelPoint virtualPoint) const noexcept;
    std::optional<std::size_t> actionOwner() const noexcept;
    std::optional<ToolbarAction> hitToolbarAction(
        const OverlaySurface& surface, PixelPoint clientPoint) const noexcept;
    std::optional<MainToolbarLayout> teachingPenToolbarLayout(
        const OverlaySurface& surface) const;
    std::optional<AnnotationPoint> teachingPenOptionsOrigin(
        const OverlaySurface& surface, float height) const noexcept;
    std::vector<ToolbarAction> toolbarActions() const;
    bool toolbarActionEnabled(ToolbarAction action) const noexcept;
    bool performToolbarAction(ToolbarAction action) noexcept;
    void ensureEditor() noexcept;
    void updateSelectionInteraction(PixelPoint virtualPoint) noexcept;
    std::optional<AnnotationPoint> annotationPoint(
        PixelPoint virtualPoint) const noexcept;
    std::optional<ShapeOptionsLayout> currentShapeOptionsLayout(
        const OverlaySurface& surface) const;
    std::optional<ArrowLineOptionsLayout> currentArrowLineOptionsLayout(
        const OverlaySurface& surface) const;
    std::optional<BrushOptionsLayout> currentBrushOptionsLayout(
        const OverlaySurface& surface) const;
    std::optional<MarkerOptionsLayout> currentMarkerOptionsLayout(
        const OverlaySurface& surface) const;
    std::optional<MosaicOptionsLayout> currentMosaicOptionsLayout(
        const OverlaySurface& surface) const;
    std::optional<TextOptionsLayout> currentTextOptionsLayout(
        const OverlaySurface& surface) const;
    std::optional<NumberOptionsLayout> currentNumberOptionsLayout(
        const OverlaySurface& surface) const;
    std::optional<MagnifierOptionsLayout> currentMagnifierOptionsLayout(
        const OverlaySurface& surface) const;
    std::optional<EraserOptionsLayout> currentEraserOptionsLayout(
        const OverlaySurface& surface) const;
    bool handleCornerRadiusPanelPointer(
        const OverlaySurface& surface,
        PixelPoint clientPoint) noexcept;
    void cancelOnce() noexcept;
    void completeOnce(OverlayInputAction action) noexcept;
    void emitTerminal(OverlayInputAction action) noexcept;
    void releaseInteraction() noexcept;
    std::optional<PixelBuffer> composeCurrentSelection() const noexcept;
    void refreshEyedropperComposite() noexcept;
    void clearEyedropperState() noexcept;
    void updateEyedropper(PixelPoint virtualPoint, bool shift) noexcept;
    bool eyedropperPointIsValid(PixelPoint virtualPoint) const noexcept;
    bool selectionPrefersLightCursor() const noexcept;
    bool pointPrefersLightCursor(PixelPoint virtualPoint) const noexcept;
    bool shouldUseLightCursor(
        PixelPoint virtualPoint,
        const OverlaySurface& surface) const noexcept;
    OverlayCursorStyle backgroundAwareCursorStyle(
        OverlayCursorStyle style,
        PixelPoint virtualPoint,
        const OverlaySurface& surface) const noexcept;

    PixelRect virtualBounds_{};
    SelectionModel model_;
    std::vector<OverlaySurface> surfaces_;
    OverlayInputPlatform& platform_;
    ActionCallback actionCallback_;
    OverlayInputStatus status_ = OverlayInputStatus::active;
    HWND escapeHotKeyWindow_ = nullptr;
    bool editorHotKeysRegistered_ = false;
    bool toolbarHotKeysRegistered_ = false;
    HWND captureWindow_ = nullptr;
    bool dragging_ = false;
    bool annotationDragging_ = false;
    bool mosaicValueDragging_ = false;
    HWND hoveredToolbarWindow_ = nullptr;
    std::optional<ToolbarAction> hoveredToolbarAction_;
    std::wstring hoveredToolbarTooltipText_;
    bool releasingCapture_ = false;
    bool shapeAnnotationsEnabled_ = false;
    OverlayMode mode_ = OverlayMode::capture;
    std::optional<std::size_t> editorOwnerIndex_;
    std::unique_ptr<ShapeEditorController> editor_;
    const FrozenDesktop* desktop_ = nullptr;
    AnnotationPoint annotationViewportOrigin_{};
    float annotationViewportScale_ = 1.0F;
    std::optional<AnnotationRect> annotationCanvasBounds_;
    mutable std::shared_ptr<const PixelBuffer> rawSelectionCache_;
    mutable std::optional<PixelRect> rawSelectionCacheSelection_;
    mutable std::optional<PixelRect> cursorContrastSelection_;
    mutable std::optional<bool> cursorContrastPrefersLight_;
    std::unique_ptr<PixelBuffer> eyedropperComposite_;
    mutable std::shared_ptr<const PixelBuffer> annotationCompositeCache_;
    mutable std::optional<PixelRect> annotationCompositeSelection_;
    mutable std::uint64_t annotationCompositeDocumentRevision_ = 0;
    mutable std::uint64_t annotationCompositeInteractionRevision_ = 0;
    std::optional<PixelPoint> eyedropperSamplePoint_;
    std::optional<AnnotationColor> eyedropperSampleColor_;
    std::array<AnnotationColor, 81> eyedropperMagnifier_{};
    std::optional<PixelPoint> eyedropperMeasurementStart_;
    std::optional<PixelPoint> eyedropperMeasurementEnd_;
    bool eyedropperMeasurementInProgress_ = false;
    bool pinnedImageShiftShortcutCandidate_ = false;
    std::optional<PixelPoint> teachingPenToolbarAnchor_;
    EyedropperCopyMode eyedropperCopyMode_ = EyedropperCopyMode::hex;
    std::optional<std::chrono::steady_clock::time_point>
        eyedropperCopySuccessUntil_;
    std::optional<OverlayInputErrorCode> lastError_;
};

enum class OverlayHostErrorCode {
    noDisplays,
    windowCreationFailed,
    escapeHotKeyRegistrationFailed,
    outOfMemory,
};

struct OverlayHostError {
    OverlayHostErrorCode code;
    DWORD systemError = ERROR_SUCCESS;
    std::optional<OverlayWindowError> windowError;
};

struct OverlayHostCreateResult;

struct OverlayAnnotationSnapshot {
    AnnotationRenderPlan plan;
    std::vector<EraserMask> eraserMasks;
    UINT dpiX = 96;
    UINT dpiY = 96;
};

class OverlayHost final {
public:
    using ActionCallback = OverlayInputRouter::ActionCallback;
    using RestartCallback = OverlayWindow::RestartCallback;
    using ScrollCallback = std::function<void(int)>;

    ~OverlayHost();
    OverlayHost(const OverlayHost&) = delete;
    OverlayHost& operator=(const OverlayHost&) = delete;

    static OverlayHostCreateResult create(
        HINSTANCE instance,
        const FrozenDesktop& desktop,
        RestartCallback restartCallback,
        ActionCallback actionCallback);
    static OverlayHostCreateResult createPinnedImageEditor(
        HINSTANCE instance,
        const FrozenDesktop& desktop,
        ActionCallback actionCallback,
        bool alwaysOnTop = true);
    static OverlayHostCreateResult createLongImageEditor(
        HINSTANCE instance,
        const FrozenDesktop& desktop,
        AnnotationRect canvasBounds,
        ScrollCallback scrollCallback,
        ActionCallback actionCallback);
    static OverlayHostCreateResult createTextRecognition(
        HINSTANCE instance,
        const FrozenDesktop& desktop,
        RestartCallback restartCallback,
        ActionCallback actionCallback);
    static OverlayHostCreateResult createTeachingPen(
        HINSTANCE instance,
        const FrozenDesktop& desktop,
        RestartCallback restartCallback,
        ActionCallback actionCallback);

    void show() noexcept;
    void setAlwaysOnTop(bool enabled) noexcept;
    bool updateLongImageViewport(
        const FrozenDesktop& desktop,
        AnnotationPoint origin) noexcept;
    bool suspendForScrollCapture() noexcept;
    bool resumeAfterScrollCapture() noexcept;
    bool suspendInputForRecognition() noexcept;
    bool resumeInputAfterRecognition() noexcept;
    std::optional<PixelRect> selection() const noexcept;
    OverlayAnnotationSnapshot annotationSnapshot() const;
    SelectionPhase phase() const noexcept;
    std::optional<OverlayInputErrorCode> lastInputError() const noexcept;

private:
    struct Impl;
    static OverlayHostCreateResult createWithMode(
        HINSTANCE instance,
        const FrozenDesktop& desktop,
        RestartCallback restartCallback,
        ActionCallback actionCallback,
        bool shapeAnnotationsEnabled,
        OverlayMode mode);
    explicit OverlayHost(std::shared_ptr<Impl> impl) noexcept;
    std::shared_ptr<Impl> impl_;
};

struct OverlayHostCreateResult {
    std::unique_ptr<OverlayHost> value;
    std::optional<OverlayHostError> error;
};

} // namespace xxsnap::win
