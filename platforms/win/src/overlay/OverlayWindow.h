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
#include <string>

namespace xxsnap::win {

using snipory::core::portable::PixelPoint;

constexpr DWORD overlayWindowStyle() noexcept
{
    return WS_POPUP;
}

constexpr DWORD overlayWindowExtendedStyle() noexcept
{
    return WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
}

inline constexpr int overlayEscapeHotKeyIdentifier = 0x5853;
inline constexpr int overlayUndoHotKeyIdentifier = 0x5854;
inline constexpr int overlayRedoHotKeyIdentifier = 0x5855;
inline constexpr int overlaySaveHotKeyIdentifier = 0x5856;
inline constexpr int overlayCopyHotKeyIdentifier = 0x5857;
inline constexpr int overlayDeleteHotKeyIdentifier = 0x5858;
inline constexpr int overlayPinHotKeyIdentifier = 0x5859;

constexpr bool isOverlayEscapeHotKey(WPARAM identifier) noexcept
{
    return identifier == static_cast<WPARAM>(overlayEscapeHotKeyIdentifier);
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

enum class OverlayCursorStyle : std::uint8_t {
    arrow,
    crosshair,
    move,
    resizeLeftRight,
    resizeUpDown,
    resizeTopLeftBottomRight,
    resizeTopRightBottomLeft,
    rotation,
    brush,
    marker,
    mosaic,
    numberMark,
    numberCheck,
    numberCross,
    textInput,
    eyedropper,
    eyedropperLight,
    eraser,
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

enum class OverlayWindowInputKind {
    pointerDown,
    pointerMove,
    pointerUp,
    captureChanged,
    cancelMode,
    escape,
    keyDown,
    keyUp,
    textInput,
    mouseWheel,
    cancelShiftShortcut,
};

struct OverlayWindowInput {
    OverlayWindowInputKind kind;
    PixelPoint clientPoint{};
    WPARAM virtualKey = 0;
    bool control = false;
    bool shift = false;
    bool alt = false;
    std::wstring text;
    int wheelDelta = 0;
    int clickCount = 1;
};

struct OverlayWindowCreateResult;

class OverlayWindow final {
public:
    using RestartCallback = std::function<void()>;
    using InputCallback = std::function<void(HWND, const OverlayWindowInput&)>;

    ~OverlayWindow();

    OverlayWindow(const OverlayWindow&) = delete;
    OverlayWindow& operator=(const OverlayWindow&) = delete;
    OverlayWindow(OverlayWindow&&) = delete;
    OverlayWindow& operator=(OverlayWindow&&) = delete;

    static OverlayWindowCreateResult create(
        HINSTANCE instance,
        const FrozenDisplay& display,
        RestartCallback restartCallback,
        InputCallback inputCallback = {});

    HWND handle() const noexcept;
    void show() noexcept;
    void hide() noexcept;
    void setAlwaysOnTop(bool enabled) noexcept;
    void setKeyboardInputAlwaysEnabled(bool enabled) noexcept;
    void setSelection(
        std::optional<PixelRect> selection,
        bool showActions = true) noexcept;
    void setRenderState(OverlayRenderState state) noexcept;
    void setCursorStyle(OverlayCursorStyle style) noexcept;
    void setMarkerCursor(AnnotationColor color, float strokeWidthDip) noexcept;
    void setMosaicCursor(float strokeWidthDip) noexcept;
    void setNumberCursor(
        NumberMarkType type, int value, AnnotationColor color) noexcept;
    DpiRestartState dpiRestartState() const noexcept;
    const std::optional<OverlayWindowError>& lastWindowError() const noexcept;
    const std::optional<OverlayRendererError>& lastRendererError() const noexcept;

private:
    OverlayWindow(
        HINSTANCE instance,
        const FrozenDisplay& display,
        RestartCallback restartCallback,
        InputCallback inputCallback);

    static LRESULT CALLBACK windowProcedure(
        HWND window,
        UINT message,
        WPARAM wParam,
        LPARAM lParam) noexcept;
    LRESULT handleMessage(UINT message, WPARAM wParam, LPARAM lParam) noexcept;
    void paint() noexcept;
    HCURSOR cursor() const noexcept;
    void discardMarkerCursor() noexcept;
    void updateTextInputActivation(bool enabled) noexcept;
    void setDotCursor(
        AnnotationColor color,
        float strokeWidthDip,
        int diameter,
        bool mosaic) noexcept;

    HINSTANCE instance_ = nullptr;
    HWND window_ = nullptr;
    const FrozenDisplay* display_ = nullptr;
    RestartCallback restartCallback_;
    InputCallback inputCallback_;
    DpiRestartDecision dpiRestartDecision_;
    OverlayRenderer renderer_;
    OverlayRenderState renderState_;
    OverlayCursorStyle cursorStyle_ = OverlayCursorStyle::crosshair;
    HCURSOR markerCursor_ = nullptr;
    bool alwaysOnTop_ = true;
    bool keyboardInputAlwaysEnabled_ = false;
    AnnotationColor markerCursorColor_{};
    float markerCursorStrokeWidthDip_ = 0.0F;
    bool markerCursorIsMosaic_ = false;
    bool markerCursorIsNumber_ = false;
    NumberMarkType numberCursorType_ = NumberMarkType::number;
    int numberCursorValue_ = 1;
    std::optional<OverlayRendererError> lastRendererError_;
};

struct OverlayWindowCreateResult {
    std::unique_ptr<OverlayWindow> value;
    std::optional<OverlayWindowError> error;
};

} // namespace xxsnap::win
