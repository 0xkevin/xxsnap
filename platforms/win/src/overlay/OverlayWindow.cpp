#include "overlay/OverlayWindow.h"

#include "annotation/NumberAnnotationMetrics.h"
#include "annotation/NumberAnnotationRenderer.h"
#include "resource.h"

#include <imm.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <new>
#include <string>
#include <utility>

namespace xxsnap::win {

namespace {

constexpr wchar_t overlayWindowClassName[] = L"XxSnapCaptureOverlayWindow";
constexpr UINT_PTR colorSamplerCopySuccessTimerIdentifier = 1U;

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
    discardMarkerCursor();
    if (window_ != nullptr) {
        const auto window = std::exchange(window_, nullptr);
        KillTimer(window, colorSamplerCopySuccessTimerIdentifier);
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
    windowClass.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    windowClass.lpfnWndProc = &OverlayWindow::windowProcedure;
    windowClass.hInstance = instance;
    windowClass.hCursor = nullptr;
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

void OverlayWindow::hide() noexcept
{
    if (window_ != nullptr) {
        ShowWindow(window_, SW_HIDE);
    }
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
    updateTextInputActivation(
        state.selectedToolbarAction == ToolbarAction::text);
    renderState_ = std::move(state);
    if (window_ != nullptr) {
        if (renderState_.eyedropper.has_value()
            && renderState_.eyedropper->copySuccessMillisecondsRemaining > 0) {
            SetTimer(
                window_, colorSamplerCopySuccessTimerIdentifier,
                renderState_.eyedropper->copySuccessMillisecondsRemaining,
                nullptr);
        } else {
            KillTimer(window_, colorSamplerCopySuccessTimerIdentifier);
        }
        InvalidateRect(window_, nullptr, FALSE);
    }
}

void OverlayWindow::updateTextInputActivation(bool enabled) noexcept
{
    if (window_ == nullptr) {
        return;
    }
    const auto current = GetWindowLongPtrW(window_, GWL_EXSTYLE);
    const auto desired = enabled
        ? current & ~static_cast<LONG_PTR>(WS_EX_NOACTIVATE)
        : current | static_cast<LONG_PTR>(WS_EX_NOACTIVATE);
    if (desired != current) {
        SetWindowLongPtrW(window_, GWL_EXSTYLE, desired);
        SetWindowPos(window_, nullptr, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER
                | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }
}

void OverlayWindow::setCursorStyle(OverlayCursorStyle style) noexcept
{
    cursorStyle_ = style;
    SetCursor(cursor());
}

void OverlayWindow::setMarkerCursor(
    AnnotationColor color,
    float strokeWidthDip) noexcept
{
    const auto diameter = strokeWidthDip < 16.0F
        ? 10 : strokeWidthDip < 20.0F ? 13 : 16;
    setDotCursor(color, strokeWidthDip, diameter, false);
}

void OverlayWindow::setMosaicCursor(float strokeWidthDip) noexcept
{
    const auto diameter = static_cast<int>(
        (std::max)(6.0F, strokeWidthDip * 0.52F) + 0.5F);
    setDotCursor({211, 211, 211, 255},
        strokeWidthDip, diameter, true);
}

void OverlayWindow::setNumberCursor(
    NumberMarkType type,
    int value,
    AnnotationColor color) noexcept
{
    value = clampedNumberValue(value);
    if (markerCursor_ != nullptr && markerCursorIsNumber_
        && numberCursorType_ == type && numberCursorValue_ == value
        && markerCursorColor_ == color) {
        return;
    }
    constexpr int side = 30;
    BITMAPV5HEADER header{};
    header.bV5Size = sizeof(header);
    header.bV5Width = side;
    header.bV5Height = -side;
    header.bV5Planes = 1;
    header.bV5BitCount = 32;
    header.bV5Compression = BI_BITFIELDS;
    header.bV5RedMask = 0x00FF0000;
    header.bV5GreenMask = 0x0000FF00;
    header.bV5BlueMask = 0x000000FF;
    header.bV5AlphaMask = 0xFF000000;
    void* bits = nullptr;
    const auto screen = GetDC(nullptr);
    const auto colorBitmap = CreateDIBSection(
        screen, reinterpret_cast<BITMAPINFO*>(&header),
        DIB_RGB_COLORS, &bits, nullptr, 0);
    ReleaseDC(nullptr, screen);
    if (colorBitmap == nullptr || bits == nullptr) {
        if (colorBitmap != nullptr) DeleteObject(colorBitmap);
        return;
    }
    auto* pixels = static_cast<std::uint32_t*>(bits);
    const auto opaquePixel = [color]() {
        return 0xFF000000U
            | static_cast<std::uint32_t>(color.red) << 16U
            | static_cast<std::uint32_t>(color.green) << 8U
            | static_cast<std::uint32_t>(color.blue);
    }();
    if (type == NumberMarkType::number) {
        constexpr float center = 14.5F;
        constexpr float radius = 12.0F;
        for (int y = 0; y < side; ++y) {
            for (int x = 0; x < side; ++x) {
                const auto dx = static_cast<float>(x) - center;
                const auto dy = static_cast<float>(y) - center;
                pixels[y * side + x] = dx * dx + dy * dy <= radius * radius
                    ? opaquePixel : 0U;
            }
        }
        const auto dc = CreateCompatibleDC(nullptr);
        const auto previousBitmap = SelectObject(dc, colorBitmap);
        SetBkMode(dc, TRANSPARENT);
        const auto foreground = readableNumberForeground(color);
        SetTextColor(dc, RGB(
            foreground.red, foreground.green, foreground.blue));
        const auto text = std::to_wstring(value);
        const auto fontHeight = text.size() == 1U
            ? 18 : text.size() == 2U ? 15 : 12;
        const auto font = CreateFontW(
            -fontHeight, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            ANTIALIASED_QUALITY, FIXED_PITCH | FF_MODERN, L"Consolas");
        const auto previousFont = SelectObject(dc, font);
        RECT rect{3, 3, 27, 27};
        DrawTextW(dc, text.c_str(), static_cast<int>(text.size()), &rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
        SelectObject(dc, previousFont);
        SelectObject(dc, previousBitmap);
        DeleteObject(font);
        DeleteDC(dc);
        for (int y = 0; y < side; ++y) {
            for (int x = 0; x < side; ++x) {
                const auto dx = static_cast<float>(x) - center;
                const auto dy = static_cast<float>(y) - center;
                if (dx * dx + dy * dy <= radius * radius) {
                    pixels[y * side + x] |= 0xFF000000U;
                }
            }
        }
    } else {
        const auto paintSegment = [&](float x1, float y1, float x2, float y2) {
            const auto dx = x2 - x1;
            const auto dy = y2 - y1;
            const auto lengthSquared = dx * dx + dy * dy;
            for (int y = 0; y < side; ++y) {
                for (int x = 0; x < side; ++x) {
                    const auto px = static_cast<float>(x) - x1;
                    const auto py = static_cast<float>(y) - y1;
                    const auto progress = (std::max)(0.0F, (std::min)(1.0F,
                        (px * dx + py * dy) / lengthSquared));
                    const auto nearestX = x1 + progress * dx;
                    const auto nearestY = y1 + progress * dy;
                    const auto distanceX = static_cast<float>(x) - nearestX;
                    const auto distanceY = static_cast<float>(y) - nearestY;
                    if (distanceX * distanceX + distanceY * distanceY <= 2.25F) {
                        pixels[y * side + x] = opaquePixel;
                    }
                }
            }
        };
        if (type == NumberMarkType::check) {
            paintSegment(6.5F, 15.0F, 12.0F, 20.5F);
            paintSegment(12.0F, 20.5F, 23.5F, 8.5F);
        } else {
            paintSegment(7.5F, 7.5F, 22.5F, 22.5F);
            paintSegment(22.5F, 7.5F, 7.5F, 22.5F);
        }
    }
    const auto maskBitmap = CreateBitmap(side, side, 1, 1, nullptr);
    ICONINFO info{};
    info.fIcon = FALSE;
    info.xHotspot = side / 2;
    info.yHotspot = side / 2;
    info.hbmMask = maskBitmap;
    info.hbmColor = colorBitmap;
    const auto cursor = CreateIconIndirect(&info);
    DeleteObject(maskBitmap);
    DeleteObject(colorBitmap);
    if (cursor != nullptr) {
        discardMarkerCursor();
        markerCursor_ = cursor;
        markerCursorColor_ = color;
        markerCursorStrokeWidthDip_ = 0.0F;
        markerCursorIsMosaic_ = false;
        markerCursorIsNumber_ = true;
        numberCursorType_ = type;
        numberCursorValue_ = value;
    }
}

void OverlayWindow::setDotCursor(
    AnnotationColor color,
    float strokeWidthDip,
    int diameter,
    bool mosaic) noexcept
{
    if (markerCursor_ != nullptr
        && !markerCursorIsNumber_
        && markerCursorColor_ == color
        && markerCursorStrokeWidthDip_ == strokeWidthDip
        && markerCursorIsMosaic_ == mosaic) {
        return;
    }
    constexpr int side = 24;
    BITMAPV5HEADER header{};
    header.bV5Size = sizeof(header);
    header.bV5Width = side;
    header.bV5Height = -side;
    header.bV5Planes = 1;
    header.bV5BitCount = 32;
    header.bV5Compression = BI_BITFIELDS;
    header.bV5RedMask = 0x00FF0000;
    header.bV5GreenMask = 0x0000FF00;
    header.bV5BlueMask = 0x000000FF;
    header.bV5AlphaMask = 0xFF000000;
    void* bits = nullptr;
    const auto screen = GetDC(nullptr);
    const auto colorBitmap = CreateDIBSection(
        screen, reinterpret_cast<BITMAPINFO*>(&header),
        DIB_RGB_COLORS, &bits, nullptr, 0);
    ReleaseDC(nullptr, screen);
    if (colorBitmap == nullptr || bits == nullptr) {
        if (colorBitmap != nullptr) {
            DeleteObject(colorBitmap);
        }
        return;
    }
    auto* pixels = static_cast<std::uint32_t*>(bits);
    const auto center = 11.5F;
    const auto innerRadius = static_cast<float>(diameter) / 2.0F;
    const auto outerRadius = innerRadius + 1.0F;
    for (int y = 0; y < side; ++y) {
        for (int x = 0; x < side; ++x) {
            const auto dx = static_cast<float>(x) - center;
            const auto dy = static_cast<float>(y) - center;
            const auto distanceSquared = dx * dx + dy * dy;
            std::uint32_t pixel = 0;
            if (distanceSquared <= innerRadius * innerRadius) {
                const auto alpha = mosaic ? 0xFFU : 0xF2U;
                pixel = alpha << 24U
                    | (static_cast<std::uint32_t>(color.red) * alpha / 255U)
                        << 16U
                    | (static_cast<std::uint32_t>(color.green) * alpha / 255U)
                        << 8U
                    | static_cast<std::uint32_t>(color.blue) * alpha / 255U;
            } else if (distanceSquared <= outerRadius * outerRadius) {
                const auto alpha = mosaic ? 0xE6U : 0xEBU;
                pixel = alpha << 24U | alpha << 16U | alpha << 8U | alpha;
            }
            pixels[y * side + x] = pixel;
        }
    }
    const auto maskBitmap = CreateBitmap(side, side, 1, 1, nullptr);
    ICONINFO info{};
    info.fIcon = FALSE;
    info.xHotspot = side / 2;
    info.yHotspot = side / 2;
    info.hbmMask = maskBitmap;
    info.hbmColor = colorBitmap;
    const auto cursor = CreateIconIndirect(&info);
    DeleteObject(maskBitmap);
    DeleteObject(colorBitmap);
    if (cursor != nullptr) {
        discardMarkerCursor();
        markerCursor_ = cursor;
        markerCursorColor_ = color;
        markerCursorStrokeWidthDip_ = strokeWidthDip;
        markerCursorIsMosaic_ = mosaic;
        markerCursorIsNumber_ = false;
    }
}

void OverlayWindow::discardMarkerCursor() noexcept
{
    if (markerCursor_ != nullptr) {
        DestroyIcon(std::exchange(markerCursor_, nullptr));
    }
}

HCURSOR OverlayWindow::cursor() const noexcept
{
    HCURSOR result = nullptr;
    switch (cursorStyle_) {
    case OverlayCursorStyle::arrow:
        result = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
        break;
    case OverlayCursorStyle::crosshair:
        result = LoadCursorW(
            instance_, MAKEINTRESOURCEW(IDC_XXSNAP_CROSSHAIR));
        break;
    case OverlayCursorStyle::move:
        result = LoadCursorW(nullptr, MAKEINTRESOURCEW(32646));
        break;
    case OverlayCursorStyle::resizeLeftRight:
        result = LoadCursorW(nullptr, MAKEINTRESOURCEW(32644));
        break;
    case OverlayCursorStyle::resizeUpDown:
        result = LoadCursorW(nullptr, MAKEINTRESOURCEW(32645));
        break;
    case OverlayCursorStyle::resizeTopLeftBottomRight:
        result = LoadCursorW(nullptr, MAKEINTRESOURCEW(32642));
        break;
    case OverlayCursorStyle::resizeTopRightBottomLeft:
        result = LoadCursorW(nullptr, MAKEINTRESOURCEW(32643));
        break;
    case OverlayCursorStyle::rotation:
        result = LoadCursorW(
            instance_, MAKEINTRESOURCEW(IDC_XXSNAP_ROTATION));
        break;
    case OverlayCursorStyle::brush:
        result = LoadCursorW(
            instance_, MAKEINTRESOURCEW(IDC_XXSNAP_BRUSH));
        break;
    case OverlayCursorStyle::marker:
    case OverlayCursorStyle::mosaic:
    case OverlayCursorStyle::numberMark:
    case OverlayCursorStyle::numberCheck:
    case OverlayCursorStyle::numberCross:
        result = markerCursor_;
        break;
    case OverlayCursorStyle::textInput:
        result = LoadCursorW(nullptr, MAKEINTRESOURCEW(32513));
        break;
    case OverlayCursorStyle::eyedropper:
        result = LoadCursorW(
            instance_, MAKEINTRESOURCEW(IDC_XXSNAP_EYEDROPPER));
        break;
    case OverlayCursorStyle::eyedropperLight:
        result = LoadCursorW(
            instance_, MAKEINTRESOURCEW(IDC_XXSNAP_EYEDROPPER_LIGHT));
        break;
    case OverlayCursorStyle::eraser:
        result = LoadCursorW(
            instance_, MAKEINTRESOURCEW(IDC_XXSNAP_ERASER));
        break;
    }
    return result != nullptr
        ? result
        : LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
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
    case WM_SETCURSOR:
        if (LOWORD(lParam) == HTCLIENT) {
            SetCursor(cursor());
            return TRUE;
        }
        return DefWindowProcW(window_, message, wParam, lParam);
    case WM_PAINT:
        paint();
        return 0;
    case WM_TIMER:
        if (wParam == colorSamplerCopySuccessTimerIdentifier) {
            KillTimer(window_, colorSamplerCopySuccessTimerIdentifier);
            if (renderState_.eyedropper.has_value()) {
                renderState_.eyedropper->copySuccessMillisecondsRemaining = 0;
                InvalidateRect(window_, nullptr, FALSE);
            }
            return 0;
        }
        return DefWindowProcW(window_, message, wParam, lParam);
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
        if (renderState_.selectedToolbarAction == ToolbarAction::text
            || renderState_.selectedToolbarAction == ToolbarAction::number) {
            SetForegroundWindow(window_);
            SetFocus(window_);
        }
        dispatchInput({
            OverlayWindowInputKind::pointerDown,
            PixelPoint{
                static_cast<short>(LOWORD(lParam)),
                static_cast<short>(HIWORD(lParam)),
            },
        });
        return 0;
    case WM_LBUTTONDBLCLK: {
        if (renderState_.selectedToolbarAction == ToolbarAction::text
            || renderState_.selectedToolbarAction == ToolbarAction::number) {
            SetForegroundWindow(window_);
            SetFocus(window_);
        }
        OverlayWindowInput input{
            OverlayWindowInputKind::pointerDown,
            PixelPoint{
                static_cast<short>(LOWORD(lParam)),
                static_cast<short>(HIWORD(lParam)),
            },
        };
        input.clickCount = 2;
        dispatchInput(input);
        return 0;
    }
    case WM_MOUSEMOVE:
        dispatchInput({
            OverlayWindowInputKind::pointerMove,
            PixelPoint{
                static_cast<short>(LOWORD(lParam)),
                static_cast<short>(HIWORD(lParam)),
            },
        });
        return 0;
    case WM_MOUSEWHEEL: {
        OverlayWindowInput input{OverlayWindowInputKind::mouseWheel, {}};
        input.wheelDelta = GET_WHEEL_DELTA_WPARAM(wParam);
        dispatchInput(input);
        return 0;
    }
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
        case overlayPinHotKeyIdentifier:
            dispatchInput({
                OverlayWindowInputKind::keyDown,
                {},
                '1',
                true,
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
        if (wParam == 'V'
            && (GetKeyState(VK_CONTROL) & 0x8000) != 0
            && renderState_.selectedToolbarAction == ToolbarAction::text
            && OpenClipboard(window_)) {
            const auto handle = GetClipboardData(CF_UNICODETEXT);
            if (handle != nullptr) {
                const auto* value = static_cast<const wchar_t*>(
                    GlobalLock(handle));
                if (value != nullptr) {
                    OverlayWindowInput input{
                        OverlayWindowInputKind::textInput, {}};
                    input.text = value;
                    dispatchInput(input);
                    GlobalUnlock(handle);
                }
            }
            CloseClipboard();
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
    case WM_CHAR:
        if (wParam >= 0x20U && wParam != 0x7FU
            && (renderState_.selectedToolbarAction == ToolbarAction::text
                || (renderState_.selectedToolbarAction == ToolbarAction::number
                    && wParam >= L'0' && wParam <= L'9'))) {
            OverlayWindowInput input{OverlayWindowInputKind::textInput, {}};
            input.text.push_back(static_cast<wchar_t>(wParam));
            dispatchInput(input);
        }
        return 0;
    case WM_IME_COMPOSITION:
        if ((lParam & GCS_RESULTSTR) != 0
            && renderState_.selectedToolbarAction == ToolbarAction::text) {
            const auto context = ImmGetContext(window_);
            if (context != nullptr) {
                const auto byteCount = ImmGetCompositionStringW(
                    context, GCS_RESULTSTR, nullptr, 0U);
                if (byteCount > 0) {
                    OverlayWindowInput input{
                        OverlayWindowInputKind::textInput, {}};
                    input.text.resize(
                        static_cast<std::size_t>(byteCount) / sizeof(wchar_t));
                    ImmGetCompositionStringW(context, GCS_RESULTSTR,
                        input.text.data(), static_cast<DWORD>(byteCount));
                    dispatchInput(input);
                }
                ImmReleaseContext(window_, context);
            }
            return 0;
        }
        return DefWindowProcW(window_, message, wParam, lParam);
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
