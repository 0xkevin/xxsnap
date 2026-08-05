#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "capture/CaptureBackend.h"
#include "overlay/VisualStyleCatalog.h"
#include "resource.h"

#include <Windows.h>

#include <array>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>

namespace xxsnap::win {

using snipory::core::portable::PixelRect;

struct DipRect {
    float x;
    float y;
    float width;
    float height;
};

struct OverlayLayoutInput {
    PixelRect displayRectPhysical;
    PixelRect selectionRectPhysical;
    std::uint32_t dpiX;
    std::uint32_t dpiY;
    float sizeLabelTextWidthDip;
    bool showActions = true;
};

struct OverlayLayout {
    DipRect overlayBounds{};
    std::array<DipRect, 4> mask{};
    DipRect border{};
    DipRect sizeLabel{};
    DipRect toolbar{};
    DipRect cancel{};
    DipRect save{};
    DipRect copy{};
    std::array<DipRect, 8> handles{};
    std::wstring sizeLabelText;
    bool showActions = true;
};

struct OverlayButtonResource {
    MvpToolbarAction action;
    int resourceId;
};

inline constexpr std::array<OverlayButtonResource, 3> mvpOverlayButtonResources() noexcept
{
    return {{
        {MvpToolbarAction::cancel, IDR_CANCEL_CAPTURE_PNG},
        {MvpToolbarAction::save, IDR_SAVE_TO_FILE_PNG},
        {MvpToolbarAction::copy, IDR_COPY_TO_CLIPBOARD_PNG},
    }};
}

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
    void discardDeviceResources() noexcept;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace xxsnap::win
