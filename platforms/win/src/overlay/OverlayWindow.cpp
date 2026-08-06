#include "overlay/OverlayWindow.h"

#include <algorithm>
#include <limits>
#include <new>
#include <utility>

namespace xxsnap::win {

namespace {

constexpr wchar_t overlayWindowClassName[] = L"XxSnapCaptureOverlayWindow";

bool fitsWin32Coordinate(std::int64_t value) noexcept
{
    return value >= (std::numeric_limits<int>::min)()
        && value <= (std::numeric_limits<int>::max)();
}

bool validWindowBounds(PixelRect bounds) noexcept
{
    bounds = snipory::core::portable::standardized(bounds);
    return bounds.width > 0
        && bounds.height > 0
        && fitsWin32Coordinate(bounds.x)
        && fitsWin32Coordinate(bounds.y)
        && bounds.width <= (std::numeric_limits<int>::max)()
        && bounds.height <= (std::numeric_limits<int>::max)();
}

} // namespace

struct DpiRestartDecision::Status final {
    DpiRestartState state = DpiRestartState::waiting;
    std::optional<OverlayWindowError> error;
};

DpiRestartDecision::DpiRestartDecision()
    : status_(std::make_shared<Status>())
{
}

DpiRestartResult DpiRestartDecision::notify(
    UINT message,
    std::function<void()> callback) noexcept
{
    const auto status = status_;
    if (message != WM_DPICHANGED
        || status->state != DpiRestartState::waiting) {
        return DpiRestartResult::ignored;
    }

    status->state = DpiRestartState::notifying;
    try {
        if (!callback) {
            status->state = DpiRestartState::failedClosed;
            status->error = OverlayWindowError{
                OverlayWindowErrorCode::dpiRestartCallbackFailed,
                ERROR_INVALID_FUNCTION,
                std::nullopt,
            };
            return DpiRestartResult::closeOverlay;
        }
        callback();
        status->state = DpiRestartState::notified;
        return DpiRestartResult::notified;
    } catch (...) {
        status->state = DpiRestartState::failedClosed;
        status->error = OverlayWindowError{
            OverlayWindowErrorCode::dpiRestartCallbackFailed,
            ERROR_UNHANDLED_EXCEPTION,
            std::nullopt,
        };
        return DpiRestartResult::closeOverlay;
    }
}

DpiRestartState DpiRestartDecision::state() const noexcept
{
    return status_->state;
}

const std::optional<OverlayWindowError>& DpiRestartDecision::error() const noexcept
{
    return status_->error;
}

OverlayWindow::OverlayWindow(
    HINSTANCE instance,
    const FrozenDisplay& display,
    RestartCallback restartCallback,
    InputCallback inputCallback)
    : instance_(instance)
    , display_(&display)
    , restartCallback_(std::move(restartCallback))
    , inputCallback_(std::move(inputCallback))
    , renderer_(instance)
{
}

OverlayWindow::~OverlayWindow()
{
    if (window_ != nullptr) {
        const auto window = std::exchange(window_, nullptr);
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        DestroyWindow(window);
    }
}

OverlayWindowCreateResult OverlayWindow::create(
    HINSTANCE instance,
    const FrozenDisplay& display,
    RestartCallback restartCallback,
    InputCallback inputCallback)
{
    if (instance == nullptr) {
        instance = GetModuleHandleW(nullptr);
    }
    auto bounds = snipory::core::portable::standardized(
        display.descriptor.pixelBounds);
    if (instance == nullptr || !validWindowBounds(bounds)) {
        return {
            nullptr,
            OverlayWindowError{
                OverlayWindowErrorCode::invalidDisplayBounds,
                ERROR_INVALID_PARAMETER,
                std::nullopt,
            },
        };
    }

    WNDCLASSEXW windowClass{};
    windowClass.cbSize = sizeof(windowClass);
    windowClass.style = CS_HREDRAW | CS_VREDRAW;
    windowClass.lpfnWndProc = &OverlayWindow::windowProcedure;
    windowClass.hInstance = instance;
    windowClass.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32515));
    windowClass.lpszClassName = overlayWindowClassName;
    if (RegisterClassExW(&windowClass) == 0U) {
        const auto systemError = GetLastError();
        if (systemError != ERROR_CLASS_ALREADY_EXISTS) {
            return {
                nullptr,
                OverlayWindowError{
                    OverlayWindowErrorCode::classRegistrationFailed,
                    systemError,
                    std::nullopt,
                },
            };
        }
    }

    try {
        auto value = std::unique_ptr<OverlayWindow>(new OverlayWindow(
            instance,
            display,
            std::move(restartCallback),
            std::move(inputCallback)));
        const auto window = CreateWindowExW(
            overlayWindowExtendedStyle(),
            overlayWindowClassName,
            L"",
            overlayWindowStyle(),
            static_cast<int>(bounds.x),
            static_cast<int>(bounds.y),
            static_cast<int>(bounds.width),
            static_cast<int>(bounds.height),
            nullptr,
            nullptr,
            instance,
            value.get());
        if (window == nullptr) {
            return {
                nullptr,
                OverlayWindowError{
                    OverlayWindowErrorCode::windowCreationFailed,
                    GetLastError(),
                    std::nullopt,
                },
            };
        }
        value->window_ = window;
        if (const auto rendererError = value->renderer_.initialize(window, display)) {
            return {
                nullptr,
                OverlayWindowError{
                    OverlayWindowErrorCode::rendererInitializationFailed,
                    ERROR_SUCCESS,
                    rendererError,
                },
            };
        }
        return {std::move(value), std::nullopt};
    } catch (const std::bad_alloc&) {
        return {
            nullptr,
            OverlayWindowError{
                OverlayWindowErrorCode::windowCreationFailed,
                ERROR_NOT_ENOUGH_MEMORY,
                std::nullopt,
            },
        };
    }
}

HWND OverlayWindow::handle() const noexcept
{
    return window_;
}

void OverlayWindow::show() noexcept
{
    if (window_ == nullptr
        || display_ == nullptr
        || dpiRestartDecision_.state() != DpiRestartState::waiting) {
        return;
    }
    const auto bounds = snipory::core::portable::standardized(
        display_->descriptor.pixelBounds);
    ShowWindow(window_, SW_SHOWNOACTIVATE);
    SetWindowPos(
        window_,
        HWND_TOPMOST,
        static_cast<int>(bounds.x),
        static_cast<int>(bounds.y),
        static_cast<int>(bounds.width),
        static_cast<int>(bounds.height),
        SWP_NOACTIVATE | SWP_SHOWWINDOW);
    UpdateWindow(window_);
}

void OverlayWindow::setSelection(
    std::optional<PixelRect> selection,
    bool showActions) noexcept
{
    renderState_ = {};
    renderState_.selection = selection;
    renderState_.showActions = showActions;
    if (window_ != nullptr) {
        InvalidateRect(window_, nullptr, FALSE);
    }
}

void OverlayWindow::setRenderState(OverlayRenderState state) noexcept
{
    renderState_ = std::move(state);
    if (window_ != nullptr) {
        InvalidateRect(window_, nullptr, FALSE);
    }
}

DpiRestartState OverlayWindow::dpiRestartState() const noexcept
{
    return dpiRestartDecision_.state();
}

const std::optional<OverlayWindowError>& OverlayWindow::lastWindowError() const noexcept
{
    return dpiRestartDecision_.error();
}

const std::optional<OverlayRendererError>& OverlayWindow::lastRendererError() const noexcept
{
    return lastRendererError_;
}

LRESULT CALLBACK OverlayWindow::windowProcedure(
    HWND window,
    UINT message,
    WPARAM wParam,
    LPARAM lParam) noexcept
{
    OverlayWindow* instance = reinterpret_cast<OverlayWindow*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lParam);
        instance = static_cast<OverlayWindow*>(create->lpCreateParams);
        if (instance != nullptr) {
            instance->window_ = window;
            SetWindowLongPtrW(
                window,
                GWLP_USERDATA,
                reinterpret_cast<LONG_PTR>(instance));
        }
    }
    if (instance == nullptr) {
        return DefWindowProcW(window, message, wParam, lParam);
    }
    return instance->handleMessage(message, wParam, lParam);
}

LRESULT OverlayWindow::handleMessage(
    UINT message,
    WPARAM wParam,
    LPARAM lParam) noexcept
{
    const auto dispatchInput = [this](OverlayWindowInput input) noexcept {
        InputCallback callback;
        try {
            callback = inputCallback_;
        } catch (...) {
            return;
        }
        const auto sourceWindow = window_;
        if (callback && sourceWindow != nullptr) {
            callback(sourceWindow, input);
        }
    };
    switch (message) {
    case WM_PAINT:
        paint();
        return 0;
    case WM_SIZE: {
        RECT client{};
        if (GetClientRect(window_, &client)) {
            lastRendererError_ = renderer_.resize(
                static_cast<std::uint32_t>((std::max)(0L, client.right - client.left)),
                static_cast<std::uint32_t>((std::max)(0L, client.bottom - client.top)));
        }
        return 0;
    }
    case WM_LBUTTONDOWN:
        dispatchInput({
            OverlayWindowInputKind::pointerDown,
            PixelPoint{
                static_cast<short>(LOWORD(lParam)),
                static_cast<short>(HIWORD(lParam)),
            },
        });
        return 0;
    case WM_MOUSEMOVE:
        dispatchInput({
            OverlayWindowInputKind::pointerMove,
            PixelPoint{
                static_cast<short>(LOWORD(lParam)),
                static_cast<short>(HIWORD(lParam)),
            },
        });
        return 0;
    case WM_LBUTTONUP:
        dispatchInput({
            OverlayWindowInputKind::pointerUp,
            PixelPoint{
                static_cast<short>(LOWORD(lParam)),
                static_cast<short>(HIWORD(lParam)),
            },
        });
        return 0;
    case WM_CAPTURECHANGED:
        dispatchInput({OverlayWindowInputKind::captureChanged, {}});
        return 0;
    case WM_CANCELMODE:
        dispatchInput({OverlayWindowInputKind::cancelMode, {}});
        return 0;
    case WM_HOTKEY:
        if (isOverlayEscapeHotKey(wParam)) {
            dispatchInput({OverlayWindowInputKind::escape, {}});
            return 0;
        }
        switch (static_cast<int>(wParam)) {
        case overlayUndoHotKeyIdentifier:
            dispatchInput({
                OverlayWindowInputKind::keyDown,
                {},
                'Z',
                true,
                false,
            });
            return 0;
        case overlayRedoHotKeyIdentifier:
            dispatchInput({
                OverlayWindowInputKind::keyDown,
                {},
                'Z',
                true,
                true,
            });
            return 0;
        case overlaySaveHotKeyIdentifier:
            dispatchInput({
                OverlayWindowInputKind::keyDown,
                {},
                'S',
                true,
                false,
            });
            return 0;
        case overlayCopyHotKeyIdentifier:
            dispatchInput({
                OverlayWindowInputKind::keyDown,
                {},
                'C',
                true,
                false,
            });
            return 0;
        case overlayDeleteHotKeyIdentifier:
            dispatchInput({
                OverlayWindowInputKind::keyDown,
                {},
                VK_DELETE,
                false,
                false,
            });
            return 0;
        default:
            break;
        }
        return DefWindowProcW(window_, message, wParam, lParam);
    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) {
            dispatchInput({OverlayWindowInputKind::escape, {}});
            return 0;
        }
        dispatchInput({
            OverlayWindowInputKind::keyDown,
            {},
            wParam,
            (GetKeyState(VK_CONTROL) & 0x8000) != 0,
            (GetKeyState(VK_SHIFT) & 0x8000) != 0,
        });
        return 0;
    case WM_DPICHANGED: {
        RestartCallback callback;
        try {
            callback = restartCallback_;
        } catch (...) {
        }
        const auto staleWindow = window_;
        if (staleWindow != nullptr) {
            ShowWindow(staleWindow, SW_HIDE);
        }
        // notify owns its callback and retains status independently. The callback may
        // synchronously destroy this window/host, so this branch never touches this
        // object again after notification begins.
        dpiRestartDecision_.notify(message, std::move(callback));
        // The suggested rectangle in lParam deliberately belongs to a new frozen session.
        return 0;
    }
    case WM_ERASEBKGND:
        return 1;
    case WM_NCDESTROY: {
        const auto destroyedWindow = window_;
        SetWindowLongPtrW(destroyedWindow, GWLP_USERDATA, 0);
        window_ = nullptr;
        return DefWindowProcW(destroyedWindow, message, wParam, lParam);
    }
    default:
        return DefWindowProcW(window_, message, wParam, lParam);
    }
}

void OverlayWindow::paint() noexcept
{
    PAINTSTRUCT paint{};
    BeginPaint(window_, &paint);
    if (display_ != nullptr) {
        lastRendererError_ = renderer_.render(
            *display_, renderState_);
        if (lastRendererError_.has_value()
            && lastRendererError_->code == OverlayRendererErrorCode::deviceLost) {
            InvalidateRect(window_, nullptr, FALSE);
        }
    }
    EndPaint(window_, &paint);
}

} // namespace xxsnap::win
