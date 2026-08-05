#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "capture/CaptureBackend.h"
#include "overlay/OverlayRenderer.h"

#include <Windows.h>

#include <functional>
#include <memory>
#include <optional>

namespace xxsnap::win {

constexpr DWORD overlayWindowStyle() noexcept
{
    return WS_POPUP;
}

constexpr DWORD overlayWindowExtendedStyle() noexcept
{
    return WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
}

enum class OverlayWindowErrorCode {
    invalidDisplayBounds,
    classRegistrationFailed,
    windowCreationFailed,
    rendererInitializationFailed,
    dpiRestartCallbackFailed,
};

struct OverlayWindowError {
    OverlayWindowErrorCode code;
    DWORD systemError = ERROR_SUCCESS;
    std::optional<OverlayRendererError> rendererError;
};

enum class DpiRestartState {
    waiting,
    notifying,
    notified,
    failedClosed,
};

enum class DpiRestartResult {
    ignored,
    notified,
    closeOverlay,
};

class DpiRestartDecision final {
public:
    DpiRestartDecision();

    DpiRestartResult notify(
        UINT message,
        std::function<void()> callback) noexcept;
    DpiRestartState state() const noexcept;
    const std::optional<OverlayWindowError>& error() const noexcept;

private:
    struct Status;
    std::shared_ptr<Status> status_;
};

struct OverlayWindowCreateResult;

class OverlayWindow final {
public:
    using RestartCallback = std::function<void()>;

    ~OverlayWindow();

    OverlayWindow(const OverlayWindow&) = delete;
    OverlayWindow& operator=(const OverlayWindow&) = delete;
    OverlayWindow(OverlayWindow&&) = delete;
    OverlayWindow& operator=(OverlayWindow&&) = delete;

    static OverlayWindowCreateResult create(
        HINSTANCE instance,
        const FrozenDisplay& display,
        RestartCallback restartCallback);

    HWND handle() const noexcept;
    void show() noexcept;
    void setSelection(
        std::optional<PixelRect> selection,
        bool showActions = true) noexcept;
    DpiRestartState dpiRestartState() const noexcept;
    const std::optional<OverlayWindowError>& lastWindowError() const noexcept;
    const std::optional<OverlayRendererError>& lastRendererError() const noexcept;

private:
    OverlayWindow(
        HINSTANCE instance,
        const FrozenDisplay& display,
        RestartCallback restartCallback);

    static LRESULT CALLBACK windowProcedure(
        HWND window,
        UINT message,
        WPARAM wParam,
        LPARAM lParam) noexcept;
    LRESULT handleMessage(UINT message, WPARAM wParam, LPARAM lParam) noexcept;
    void paint() noexcept;

    HINSTANCE instance_ = nullptr;
    HWND window_ = nullptr;
    const FrozenDisplay* display_ = nullptr;
    RestartCallback restartCallback_;
    DpiRestartDecision dpiRestartDecision_;
    OverlayRenderer renderer_;
    std::optional<PixelRect> selection_;
    bool showActions_ = true;
    std::optional<OverlayRendererError> lastRendererError_;
};

struct OverlayWindowCreateResult {
    std::unique_ptr<OverlayWindow> value;
    std::optional<OverlayWindowError> error;
};

} // namespace xxsnap::win
