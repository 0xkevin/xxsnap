#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "capture/CaptureBackend.h"
#include "annotation/AnnotationRenderer.h"
#include "annotation/ShapeOptions.h"
#include "overlay/VisualStyleCatalog.h"
#include "toolbar/ToolbarLayout.h"

#include <Windows.h>

#include <array>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace xxsnap::win {

using snipory::core::portable::PixelRect;

using DipRect = ToolbarRect;

struct OverlayLayoutInput {
    PixelRect displayRectPhysical;
    PixelRect selectionRectPhysical;
    std::uint32_t dpiX;
    std::uint32_t dpiY;
    float sizeLabelTextWidthDip;
    bool showActions = true;
    std::vector<ToolbarAction> toolbarActions{
        terminalToolbarActions().begin(),
        terminalToolbarActions().end(),
    };
};

struct OverlayToolbarItem {
    ToolbarAction action;
    DipRect rect;
    bool selected = false;
    bool enabled = true;
};

struct OverlayLayout {
    DipRect overlayBounds{};
    std::array<DipRect, 4> mask{};
    DipRect border{};
    DipRect sizeLabel{};
    MainToolbarLayout toolbar{};
    std::vector<OverlayToolbarItem> toolbarItems;
    std::array<DipRect, 8> handles{};
    std::wstring sizeLabelText;
    bool showActions = true;
};

struct OverlayShapeOptionsRenderState {
    ShapeOptionsLayout layout;
    ShapeOptionsState state;
    std::optional<StrokePatternMenuLayout> strokePatternMenu;
    std::optional<CornerRadiusPanelLayout> cornerRadiusPanel;
};

struct OverlayArrowLineOptionsRenderState {
    ArrowLineOptionsLayout layout;
    ArrowLineOptionsState state;
    std::optional<StrokePatternMenuLayout> strokePatternMenu;
    std::optional<ArrowTypeMenuLayout> arrowTypeMenu;
    std::optional<ArrowEndpoint> arrowTypeMenuEndpoint;
};

struct OverlayBrushOptionsRenderState {
    BrushOptionsLayout layout;
    BrushOptionsState state;
    std::optional<StrokePatternMenuLayout> strokePatternMenu;
};

struct OverlayMarkerOptionsRenderState {
    MarkerOptionsLayout layout;
    MarkerOptionsState state;
};

struct OverlayRenderState {
    std::optional<PixelRect> selection;
    bool showActions = true;
    std::vector<ToolbarAction> toolbarActions{
        terminalToolbarActions().begin(),
        terminalToolbarActions().end(),
    };
    std::optional<ToolbarAction> selectedToolbarAction;
    bool canUndo = false;
    bool canRedo = false;
    AnnotationRenderPlan annotationPlan;
    std::optional<OverlayShapeOptionsRenderState> shapeOptions;
    std::optional<OverlayArrowLineOptionsRenderState> arrowLineOptions;
    std::optional<OverlayBrushOptionsRenderState> brushOptions;
    std::optional<OverlayMarkerOptionsRenderState> markerOptions;
};

float physicalPixelsToDip(std::int64_t pixels, std::uint32_t dpi) noexcept;
std::int64_t dipLengthToPhysicalPixels(float dips, std::uint32_t dpi) noexcept;
OverlayLayout computeOverlayLayout(const OverlayLayoutInput& input);
std::string overlayLayoutManifestJson(const OverlayLayout& layout);

enum class OverlayRendererErrorCode {
    invalidArgument,
    comInitializationFailed,
    d2dFactoryFailed,
    dwriteFactoryFailed,
    textFormatConfigurationFailed,
    wicFactoryFailed,
    renderTargetFailed,
    backgroundBitmapFailed,
    resourceNotFound,
    resourceDecodeFailed,
    drawFailed,
    deviceLost,
};

struct OverlayRendererError {
    OverlayRendererErrorCode code;
    HRESULT nativeCode;
    int resourceId = 0;
};

std::optional<OverlayRendererError> checkTextFormatConfigurationResult(
    HRESULT result) noexcept;

class OverlayRenderer final {
public:
    explicit OverlayRenderer(HMODULE resourceModule);
    ~OverlayRenderer();

    OverlayRenderer(const OverlayRenderer&) = delete;
    OverlayRenderer& operator=(const OverlayRenderer&) = delete;
    OverlayRenderer(OverlayRenderer&&) = delete;
    OverlayRenderer& operator=(OverlayRenderer&&) = delete;

    std::optional<OverlayRendererError> initialize(
        HWND window,
        const FrozenDisplay& display) noexcept;
    std::optional<OverlayRendererError> resize(
        std::uint32_t width,
        std::uint32_t height) noexcept;
    std::optional<OverlayRendererError> render(
        const FrozenDisplay& display,
        const std::optional<PixelRect>& selection,
        bool showActions = true) noexcept;
    std::optional<OverlayRendererError> render(
        const FrozenDisplay& display,
        const OverlayRenderState& state) noexcept;
    void discardDeviceResources() noexcept;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace xxsnap::win
