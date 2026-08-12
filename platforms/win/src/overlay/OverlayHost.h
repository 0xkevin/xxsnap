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
    save,
    copy,
};

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

struct OverlayPresentation {
    std::optional<PixelRect> selection;
    bool showActions = false;
    std::vector<OverlayPresentationToolbarItem> toolbarItems;
    AnnotationRenderPlan annotationPlan;
    std::shared_ptr<const PixelBuffer> annotationComposite;
    std::optional<OverlayPresentationShapeOptions> shapeOptions;
    std::optional<OverlayPresentationArrowLineOptions> arrowLineOptions;
    std::optional<OverlayPresentationBrushOptions> brushOptions;
    std::optional<OverlayPresentationMarkerOptions> markerOptions;
    std::optional<OverlayPresentationMosaicOptions> mosaicOptions;
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
        const FrozenDesktop* desktop = nullptr);
    ~OverlayInputRouter();

    OverlayInputRouter(const OverlayInputRouter&) = delete;
    OverlayInputRouter& operator=(const OverlayInputRouter&) = delete;

    bool activateEscapeHotKey(HWND owner) noexcept;
    bool deactivateEscapeHotKey() noexcept;
    bool pointerDown(HWND source, PixelPoint clientPoint) noexcept;
    void pointerMove(HWND source, PixelPoint clientPoint) noexcept;
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
    bool eyedropperShiftPressed() noexcept;
    void shutdownForRestart() noexcept;

    OverlayInputStatus status() const noexcept;
    std::optional<OverlayInputErrorCode> lastError() const noexcept;
    SelectionPhase phase() const noexcept;
    std::optional<PixelRect> selection() const noexcept;
    std::vector<OverlayPresentation> presentations() const;
    const AnnotationDocument& annotationDocument() const noexcept;
    std::pair<UINT, UINT> annotationDpi() const noexcept;
    std::optional<AnnotationStyle> markerCursorStyle() const noexcept;
    std::optional<AnnotationStyle> mosaicCursorStyle() const noexcept;

private:
    const OverlaySurface* surfaceFor(HWND window) const noexcept;
    PixelPoint toVirtual(
        const OverlaySurface& surface, PixelPoint clientPoint) const noexcept;
    std::optional<std::size_t> actionOwner() const noexcept;
    std::optional<ToolbarAction> hitToolbarAction(
        const OverlaySurface& surface, PixelPoint clientPoint) const noexcept;
    std::vector<ToolbarAction> toolbarActions() const;
    bool toolbarActionEnabled(ToolbarAction action) const noexcept;
    void ensureEditor() noexcept;
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
    void cancelOnce() noexcept;
    void completeOnce(OverlayInputAction action) noexcept;
    void emitTerminal(OverlayInputAction action) noexcept;
    void releaseInteraction() noexcept;
    std::optional<PixelBuffer> composeCurrentSelection() const noexcept;
    void refreshEyedropperComposite() noexcept;
    void clearEyedropperState() noexcept;
    void updateEyedropper(PixelPoint virtualPoint, bool shift) noexcept;
    bool eyedropperPointIsValid(PixelPoint virtualPoint) const noexcept;

    SelectionModel model_;
    std::vector<OverlaySurface> surfaces_;
    OverlayInputPlatform& platform_;
    ActionCallback actionCallback_;
    OverlayInputStatus status_ = OverlayInputStatus::active;
    HWND escapeHotKeyWindow_ = nullptr;
    bool editorHotKeysRegistered_ = false;
    HWND captureWindow_ = nullptr;
    bool dragging_ = false;
    bool annotationDragging_ = false;
    bool mosaicValueDragging_ = false;
    bool releasingCapture_ = false;
    bool shapeAnnotationsEnabled_ = false;
    std::optional<std::size_t> editorOwnerIndex_;
    std::unique_ptr<ShapeEditorController> editor_;
    const FrozenDesktop* desktop_ = nullptr;
    std::unique_ptr<PixelBuffer> eyedropperComposite_;
    mutable std::shared_ptr<const PixelBuffer> mosaicCompositeCache_;
    mutable std::optional<PixelRect> mosaicCompositeSelection_;
    mutable std::uint64_t mosaicCompositeDocumentRevision_ = 0;
    mutable std::uint64_t mosaicCompositeInteractionRevision_ = 0;
    std::optional<PixelPoint> eyedropperSamplePoint_;
    std::optional<AnnotationColor> eyedropperSampleColor_;
    std::array<AnnotationColor, 81> eyedropperMagnifier_{};
    std::optional<PixelPoint> eyedropperMeasurementStart_;
    std::optional<PixelPoint> eyedropperMeasurementEnd_;
    bool eyedropperMeasurementInProgress_ = false;
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
    UINT dpiX = 96;
    UINT dpiY = 96;
};

class OverlayHost final {
public:
    using ActionCallback = OverlayInputRouter::ActionCallback;
    using RestartCallback = OverlayWindow::RestartCallback;

    ~OverlayHost();
    OverlayHost(const OverlayHost&) = delete;
    OverlayHost& operator=(const OverlayHost&) = delete;

    static OverlayHostCreateResult create(
        HINSTANCE instance,
        const FrozenDesktop& desktop,
        RestartCallback restartCallback,
        ActionCallback actionCallback);

    void show() noexcept;
    std::optional<PixelRect> selection() const noexcept;
    OverlayAnnotationSnapshot annotationSnapshot() const;
    SelectionPhase phase() const noexcept;
    std::optional<OverlayInputErrorCode> lastInputError() const noexcept;

private:
    struct Impl;
    explicit OverlayHost(std::shared_ptr<Impl> impl) noexcept;
    std::shared_ptr<Impl> impl_;
};

struct OverlayHostCreateResult {
    std::unique_ptr<OverlayHost> value;
    std::optional<OverlayHostError> error;
};

} // namespace xxsnap::win
