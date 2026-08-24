#include "scroll/ScrollCaptureHost.h"

#include "capture/DisplayTopology.h"
#include "export/AnnotationComposer.h"
#include "overlay/OverlayHost.h"
#include "overlay/VisualStyleCatalog.h"
#include "scroll/LongImageEditorGeometry.h"
#include "scroll/ScrollCaptureSamplingState.h"
#include "scroll/ScrollCaptureSession.h"
#include "scroll/ScrollCaptureTargetDetector.h"
#include "scroll/ScrollRegionCapturer.h"
#include "toolbar/ToolbarCatalog.h"
#include "toolbar/ToolbarLayout.h"

#include <Windows.h>
#include <wincodec.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <limits>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace xxsnap::win
{
namespace
{

constexpr wchar_t scrollCaptureWindowClass[] = L"XxSnapScrollCaptureChromeWindow";
constexpr UINT scrollWheelMessage = WM_APP + 0x41U;
constexpr UINT scrollFinishMessage = WM_APP + 0x42U;
constexpr UINT scrollCancelMessage = WM_APP + 0x43U;
constexpr UINT scrollPointerDownMessage = WM_APP + 0x44U;
constexpr UINT scrollPointerMoveMessage = WM_APP + 0x45U;
constexpr UINT scrollPointerUpMessage = WM_APP + 0x46U;
constexpr UINT_PTR captureTimerIdentifier = 1U;
constexpr UINT captureSettleMilliseconds = 110U;

template <typename T> class ComPtr final
{
  public:
    ~ComPtr() { reset(); }
    T *get() const noexcept { return value_; }
    T **put() noexcept
    {
        reset();
        return &value_;
    }
    T *operator->() const noexcept { return value_; }
    void reset() noexcept
    {
        if (value_ != nullptr) value_->Release();
        value_ = nullptr;
    }

  private:
    T *value_ = nullptr;
};

struct IconBitmap final
{
    HBITMAP bitmap = nullptr;
    int width = 0;
    int height = 0;

    IconBitmap() = default;
    ~IconBitmap()
    {
        if (bitmap != nullptr) DeleteObject(bitmap);
    }
    IconBitmap(const IconBitmap &) = delete;
    IconBitmap &operator=(const IconBitmap &) = delete;
    IconBitmap(IconBitmap &&other) noexcept
        : bitmap(std::exchange(other.bitmap, nullptr)), width(other.width),
          height(other.height)
    {
    }
    IconBitmap &operator=(IconBitmap &&other) noexcept
    {
        if (this != &other) {
            if (bitmap != nullptr) DeleteObject(bitmap);
            bitmap = std::exchange(other.bitmap, nullptr);
            width = other.width;
            height = other.height;
        }
        return *this;
    }
};

bool pointInside(PixelRect rect, POINT point) noexcept
{
    rect = snipory::core::portable::standardized(rect);
    return point.x >= rect.x && point.x < rect.x + rect.width && point.y >= rect.y &&
           point.y < rect.y + rect.height;
}

int scaledDip(float dip, UINT dpi) noexcept
{
    return static_cast<int>(
        std::lround(dip * static_cast<float>(dpi == 0U ? 96U : dpi) / 96.0F));
}

RECT pixelRect(PixelRect rect) noexcept
{
    return {
        static_cast<LONG>(rect.x),
        static_cast<LONG>(rect.y),
        static_cast<LONG>(rect.x + rect.width),
        static_cast<LONG>(rect.y + rect.height),
    };
}

PixelRect monitorWorkArea(PixelRect selection) noexcept
{
    const auto native = pixelRect(selection);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    const auto monitor = MonitorFromRect(&native, MONITOR_DEFAULTTONEAREST);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info)) {
        return {
            info.rcWork.left,
            info.rcWork.top,
            static_cast<std::int64_t>(info.rcWork.right) - info.rcWork.left,
            static_cast<std::int64_t>(info.rcWork.bottom) - info.rcWork.top,
        };
    }
    return selection;
}

std::optional<PixelRect> detectTargetWithTimeout(PixelRect selection,
                                                 DWORD targetProcessId, UINT dpiX,
                                                 UINT dpiY) noexcept
{
    struct State final
    {
        std::mutex mutex;
        std::condition_variable changed;
        bool finished = false;
        std::optional<PixelRect> result;
    };
    try {
        const auto state = std::make_shared<State>();
        std::thread([state, selection, targetProcessId, dpiX, dpiY] {
            std::optional<PixelRect> result;
            try {
                result = ScrollCaptureTargetDetector{}.detect(
                    selection, targetProcessId, dpiX, dpiY);
            } catch (...) {
            }
            {
                std::lock_guard<std::mutex> lock(state->mutex);
                state->result = result;
                state->finished = true;
            }
            state->changed.notify_one();
        }).detach();
        std::unique_lock<std::mutex> lock(state->mutex);
        if (!state->changed.wait_for(lock, std::chrono::milliseconds(700),
                                     [&state] { return state->finished; })) {
            return std::nullopt;
        }
        return state->result;
    } catch (...) {
        return std::nullopt;
    }
}

IconBitmap decodeResourcePng(HINSTANCE instance, int resourceId,
                             int targetEdge) noexcept
{
    IconBitmap result;
    const auto resource =
        FindResourceW(instance, MAKEINTRESOURCEW(resourceId), MAKEINTRESOURCEW(10));
    if (resource == nullptr) return result;
    const auto size = SizeofResource(instance, resource);
    const auto loaded = LoadResource(instance, resource);
    auto *bytes = static_cast<BYTE *>(LockResource(loaded));
    if (bytes == nullptr || size == 0U) return result;

    ComPtr<IWICImagingFactory> factory;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(factory.put())))) {
        return result;
    }
    ComPtr<IWICStream> stream;
    if (FAILED(factory->CreateStream(stream.put())) ||
        FAILED(stream->InitializeFromMemory(bytes, size))) {
        return result;
    }
    ComPtr<IWICBitmapDecoder> decoder;
    if (FAILED(factory->CreateDecoderFromStream(
            stream.get(), nullptr, WICDecodeMetadataCacheOnLoad, decoder.put()))) {
        return result;
    }
    ComPtr<IWICBitmapFrameDecode> frame;
    UINT width = 0U;
    UINT height = 0U;
    if (FAILED(decoder->GetFrame(0U, frame.put())) ||
        FAILED(frame->GetSize(&width, &height)) || width == 0U || height == 0U ||
        width > static_cast<UINT>((std::numeric_limits<int>::max)()) ||
        height > static_cast<UINT>((std::numeric_limits<int>::max)())) {
        return result;
    }
    ComPtr<IWICBitmapScaler> scaler;
    IWICBitmapSource *source = frame.get();
    if (targetEdge > 0 && (width != static_cast<UINT>(targetEdge) ||
                           height != static_cast<UINT>(targetEdge))) {
        if (FAILED(factory->CreateBitmapScaler(scaler.put())) ||
            FAILED(scaler->Initialize(frame.get(), static_cast<UINT>(targetEdge),
                                      static_cast<UINT>(targetEdge),
                                      WICBitmapInterpolationModeFant))) {
            return result;
        }
        source = scaler.get();
        width = static_cast<UINT>(targetEdge);
        height = static_cast<UINT>(targetEdge);
    }
    ComPtr<IWICFormatConverter> converter;
    if (FAILED(factory->CreateFormatConverter(converter.put())) ||
        FAILED(converter->Initialize(source, GUID_WICPixelFormat32bppPBGRA,
                                     WICBitmapDitherTypeNone, nullptr, 0.0,
                                     WICBitmapPaletteTypeCustom))) {
        return result;
    }
    BITMAPINFO bitmapInfo{};
    bitmapInfo.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bitmapInfo.bmiHeader.biWidth = static_cast<LONG>(width);
    bitmapInfo.bmiHeader.biHeight = -static_cast<LONG>(height);
    bitmapInfo.bmiHeader.biPlanes = 1U;
    bitmapInfo.bmiHeader.biBitCount = 32U;
    bitmapInfo.bmiHeader.biCompression = BI_RGB;
    void *dibBits = nullptr;
    const auto screen = GetDC(nullptr);
    const auto bitmap =
        CreateDIBSection(screen, &bitmapInfo, DIB_RGB_COLORS, &dibBits, nullptr, 0U);
    if (screen != nullptr) ReleaseDC(nullptr, screen);
    if (bitmap == nullptr || dibBits == nullptr) return result;
    const auto stride = width * 4U;
    if (FAILED(converter->CopyPixels(nullptr, stride, stride * height,
                                     static_cast<BYTE *>(dibBits)))) {
        DeleteObject(bitmap);
        return result;
    }
    result.bitmap = bitmap;
    result.width = static_cast<int>(width);
    result.height = static_cast<int>(height);
    return result;
}

} // namespace

struct ScrollCaptureHost::Impl final
{
    HINSTANCE instance = nullptr;
    PixelRect originalSelection{};
    PixelRect selection{};
    PixelRect workArea{};
    DWORD targetProcessId = 0U;
    UINT dpiX = 96U;
    UINT dpiY = 96U;
    std::size_t maximumAcceptedBytes = 0U;
    CompletionCallback callback;
    ScrollCaptureSession session;
    ScrollRegionCapturer capturer;
    HWND borderWindow = nullptr;
    HWND toolbarWindow = nullptr;
    HWND previewWindow = nullptr;
    HHOOK mouseHook = nullptr;
    HHOOK keyboardHook = nullptr;
    PixelRect toolbarBounds{};
    PixelRect previewBounds{};
    RECT finishButton{};
    ScrollCaptureSamplingState sampling;
    snipory::core::scroll::ScrollDirection direction =
        snipory::core::scroll::ScrollDirection::Undetermined;
    std::optional<snipory::core::scroll::ScrollFrame> preview;
    std::optional<PixelBuffer> finalPixels;
    std::unique_ptr<MemoryBudget> editorBudget;
    std::unique_ptr<FrozenDesktop> editorDesktop;
    std::unique_ptr<OverlayHost> longImageEditor;
    LongImageEditorLayout editorLayout{};
    std::vector<std::int64_t> editorSampleX0;
    std::vector<std::int64_t> editorSampleX1;
    std::vector<double> editorSampleXFraction;
    std::wstring captureNotice;
    std::int64_t reviewOffset = 0;
    std::vector<IconBitmap> icons;
    IconBitmap finishIcon;
    bool targetResolved = false;
    bool reviewing = false;
    bool terminal = false;
    bool captureTimerScheduled = false;

    static Impl *active;

    Impl(std::size_t maximumBytes) : session(maximumBytes), capturer(maximumBytes) {}

    ~Impl()
    {
        terminal = true;
        if (toolbarWindow != nullptr) KillTimer(toolbarWindow, captureTimerIdentifier);
        captureTimerScheduled = false;
        if (mouseHook != nullptr) UnhookWindowsHookEx(mouseHook);
        if (keyboardHook != nullptr) UnhookWindowsHookEx(keyboardHook);
        mouseHook = nullptr;
        keyboardHook = nullptr;
        if (active == this) active = nullptr;
        if (borderWindow != nullptr) DestroyWindow(borderWindow);
        if (toolbarWindow != nullptr) DestroyWindow(toolbarWindow);
        if (previewWindow != nullptr) DestroyWindow(previewWindow);
        borderWindow = nullptr;
        toolbarWindow = nullptr;
        previewWindow = nullptr;
    }

    static LRESULT CALLBACK hookMouse(int code, WPARAM wParam, LPARAM lParam)
    {
        auto *self = active;
        if (code >= 0 && self != nullptr && !self->terminal) {
            const auto *data = reinterpret_cast<const MSLLHOOKSTRUCT *>(lParam);
            if (data == nullptr) {
                return CallNextHookEx(nullptr, code, wParam, lParam);
            }
            if (wParam == WM_MOUSEWHEEL && pointInside(self->selection, data->pt)) {
                const auto delta = GET_WHEEL_DELTA_WPARAM(data->mouseData);
                PostMessageW(self->toolbarWindow, scrollWheelMessage,
                             static_cast<WPARAM>(static_cast<INT_PTR>(delta)), 0);
            } else if (wParam == WM_LBUTTONDOWN) {
                const auto capturesTarget = pointInside(self->selection, data->pt)
                    || self->pointTargetsCaptureProcess(data->pt);
                PostMessageW(self->toolbarWindow, scrollPointerDownMessage,
                             capturesTarget ? 1U : 0U, 0);
            } else if (wParam == WM_MOUSEMOVE
                       && (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0) {
                PostMessageW(self->toolbarWindow, scrollPointerMoveMessage, 0, 0);
            } else if (wParam == WM_LBUTTONUP) {
                PostMessageW(self->toolbarWindow, scrollPointerUpMessage, 0, 0);
            }
        }
        return CallNextHookEx(nullptr, code, wParam, lParam);
    }

    static LRESULT CALLBACK hookKeyboard(int code, WPARAM wParam, LPARAM lParam)
    {
        auto *self = active;
        if (code >= 0 && self != nullptr && !self->terminal &&
            (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) {
            const auto *data = reinterpret_cast<const KBDLLHOOKSTRUCT *>(lParam);
            if (data != nullptr && data->vkCode == VK_ESCAPE) {
                PostMessageW(self->toolbarWindow, scrollCancelMessage, 0, 0);
                return 1;
            }
            if (data != nullptr &&
                (data->vkCode == VK_RETURN || data->vkCode == VK_EXECUTE)) {
                PostMessageW(self->toolbarWindow, scrollFinishMessage, 0, 0);
                return 1;
            }
        }
        return CallNextHookEx(nullptr, code, wParam, lParam);
    }

    static LRESULT CALLBACK windowProcedure(HWND window, UINT message, WPARAM wParam,
                                            LPARAM lParam) noexcept
    {
        auto *self = reinterpret_cast<Impl *>(GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto *create = reinterpret_cast<const CREATESTRUCTW *>(lParam);
            self = static_cast<Impl *>(create->lpCreateParams);
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
        return self != nullptr ? self->handleMessage(window, message, wParam, lParam)
                               : DefWindowProcW(window, message, wParam, lParam);
    }

    LRESULT handleMessage(HWND window, UINT message, WPARAM wParam,
                          LPARAM lParam) noexcept
    {
        switch (message) {
        case WM_PAINT:
            paint(window);
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_LBUTTONUP:
            if (window == toolbarWindow) {
                POINT point{
                    static_cast<short>(LOWORD(lParam)),
                    static_cast<short>(HIWORD(lParam)),
                };
                if (PtInRect(&finishButton, point)) {
                    finish();
                }
            }
            return 0;
        case scrollWheelMessage:
            if (session.phase() == ScrollCapturePhase::paused) return 0;
            sampling.noteWheel(static_cast<int>(static_cast<INT_PTR>(wParam)));
            scheduleCapture();
            return 0;
        case scrollPointerDownMessage:
            sampling.beginPointerDrag(wParam != 0U);
            return 0;
        case scrollPointerMoveMessage:
            sampling.notePointerMove();
            scheduleCapture();
            return 0;
        case scrollPointerUpMessage:
            sampling.endPointerDrag();
            scheduleCapture();
            return 0;
        case WM_TIMER:
            if (wParam == captureTimerIdentifier) {
                KillTimer(toolbarWindow, captureTimerIdentifier);
                captureTimerScheduled = false;
                if (const auto wheelDelta = sampling.takePendingWheelDelta()) {
                    captureNextFrame(*wheelDelta);
                }
                return 0;
            }
            break;
        case scrollFinishMessage:
            if (!reviewing) finish();
            return 0;
        case scrollCancelMessage:
            complete({ScrollCaptureHostStatus::cancelled, std::nullopt});
            return 0;
        case WM_NCDESTROY:
            SetWindowLongPtrW(window, GWLP_USERDATA, 0);
            return DefWindowProcW(window, message, wParam, lParam);
        default:
            break;
        }
        return DefWindowProcW(window, message, wParam, lParam);
    }

    bool initialize() noexcept
    {
        originalSelection = snipory::core::portable::standardized(originalSelection);
        if (originalSelection.width <= 0 || originalSelection.height <= 0 ||
            active != nullptr) {
            return false;
        }
        if (const auto detected = detectTargetWithTimeout(
                originalSelection, targetProcessId, dpiX, dpiY)) {
            selection = *detected;
            targetResolved = true;
        } else {
            selection = originalSelection;
        }
        workArea = monitorWorkArea(selection);
        auto seed = capturer.capture(selection);
        ScrollCaptureUpdate update;
        if (!seed.has_value() || !session.start(std::move(*seed), update) ||
            !update.preview.has_value()) {
            return false;
        }
        preview = std::move(update.preview);
        if (!registerWindowClasses() || !createWindows()) return false;
        loadIcons();
        active = this;
        mouseHook = SetWindowsHookExW(WH_MOUSE_LL, &Impl::hookMouse, instance, 0U);
        keyboardHook =
            SetWindowsHookExW(WH_KEYBOARD_LL, &Impl::hookKeyboard, instance, 0U);
        if (mouseHook == nullptr || keyboardHook == nullptr) return false;
        showChrome();
        return true;
    }

    bool registerWindowClasses() noexcept
    {
        WNDCLASSEXW value{};
        value.cbSize = sizeof(value);
        value.lpfnWndProc = &Impl::windowProcedure;
        value.hInstance = instance;
        value.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
        value.lpszClassName = scrollCaptureWindowClass;
        if (RegisterClassExW(&value) == 0U &&
            GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            return false;
        }
        return true;
    }

    bool pointTargetsCaptureProcess(POINT point) const noexcept
    {
        if (targetProcessId == 0U) return false;
        const auto window = WindowFromPoint(point);
        if (window == nullptr) return false;
        DWORD processId = 0U;
        GetWindowThreadProcessId(window, &processId);
        return processId == targetProcessId;
    }

    void scheduleCapture() noexcept
    {
        if (terminal || captureTimerScheduled || !sampling.hasPendingSample()
            || session.phase() == ScrollCapturePhase::paused) {
            return;
        }
        captureTimerScheduled = SetTimer(
            toolbarWindow, captureTimerIdentifier, captureSettleMilliseconds, nullptr)
            != 0U;
    }

    bool createWindows() noexcept
    {
        const auto scaleX = static_cast<double>(dpiX == 0U ? 96U : dpiX) / 96.0;
        const auto toolbarWidth = static_cast<std::int64_t>(
            std::lround((toolbarWidthDip() + ToolbarMetrics::buttonStepDip) * scaleX));
        const auto toolbarHeight = scaledDip(ToolbarMetrics::heightDip, dpiY);
        auto toolbarX = selection.x + (selection.width - toolbarWidth) / 2;
        toolbarX =
            (std::max)(workArea.x, (std::min)(toolbarX, workArea.x + workArea.width -
                                                            toolbarWidth));
        auto toolbarY = selection.y + selection.height + scaledDip(8.0F, dpiY);
        if (toolbarY + toolbarHeight > workArea.y + workArea.height) {
            toolbarY = selection.y - scaledDip(8.0F, dpiY) - toolbarHeight;
        }
        toolbarY =
            (std::max)(workArea.y, (std::min)(toolbarY, workArea.y + workArea.height -
                                                            toolbarHeight));
        toolbarBounds = {toolbarX, toolbarY, toolbarWidth, toolbarHeight};

        const auto previewWidth = scaledDip(300.0F, dpiX);
        const auto previewHeight = scaledDip(480.0F, dpiY);
        auto previewX = selection.x + selection.width + scaledDip(8.0F, dpiX);
        if (previewX + previewWidth > workArea.x + workArea.width) {
            previewX = selection.x - scaledDip(8.0F, dpiX) - previewWidth;
        }
        previewX =
            (std::max)(workArea.x, (std::min)(previewX, workArea.x + workArea.width -
                                                            previewWidth));
        auto previewY = selection.y + selection.height - previewHeight;
        previewY =
            (std::max)(workArea.y, (std::min)(previewY, workArea.y + workArea.height -
                                                            previewHeight));
        previewBounds = {previewX, previewY, previewWidth, previewHeight};

        const auto common = WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
        borderWindow = createWindow(common | WS_EX_TRANSPARENT, selection);
        toolbarWindow = createWindow(common, toolbarBounds);
        previewWindow = createWindow(common | WS_EX_TRANSPARENT, previewBounds);
        if (borderWindow == nullptr || toolbarWindow == nullptr ||
            previewWindow == nullptr) {
            return false;
        }
        const auto border = (std::max)(1, scaledDip(2.0F, dpiX));
        const auto outer = CreateRectRgn(0, 0, static_cast<int>(selection.width),
                                         static_cast<int>(selection.height));
        const auto inner =
            CreateRectRgn(border, border, static_cast<int>(selection.width) - border,
                          static_cast<int>(selection.height) - border);
        CombineRgn(outer, outer, inner, RGN_DIFF);
        DeleteObject(inner);
        SetWindowRgn(borderWindow, outer, FALSE);
        const auto radius = scaledDip(6.0F, dpiX);
        SetWindowRgn(toolbarWindow,
                     CreateRoundRectRgn(0, 0, static_cast<int>(toolbarBounds.width) + 1,
                                        static_cast<int>(toolbarBounds.height) + 1,
                                        radius, radius),
                     FALSE);
        computeFinishButton();
        return true;
    }

    HWND createWindow(DWORD extendedStyle, PixelRect bounds) noexcept
    {
        return CreateWindowExW(extendedStyle, scrollCaptureWindowClass, L"", WS_POPUP,
                               static_cast<int>(bounds.x), static_cast<int>(bounds.y),
                               static_cast<int>(bounds.width),
                               static_cast<int>(bounds.height), nullptr, nullptr,
                               instance, this);
    }

    float toolbarWidthDip() const noexcept
    {
        return toolbarWidth(std::vector<ToolbarAction>{fullToolbarActions().begin(),
                                                       fullToolbarActions().end()});
    }

    void computeFinishButton() noexcept
    {
        int x = scaledDip(
            ToolbarMetrics::horizontalPaddingDip + ToolbarMetrics::buttonStepDip, dpiX);
        const auto step = scaledDip(ToolbarMetrics::buttonStepDip, dpiX);
        const auto side = scaledDip(ToolbarMetrics::buttonSizeDip, dpiX);
        const auto y = (static_cast<int>(toolbarBounds.height) - side) / 2;
        for (const auto action : fullToolbarActions()) {
            RECT actionButton{x, y, x + side, y + side};
            x += step;
            if (action == ToolbarAction::scroll) {
                finishButton = {x, y, x + side, y + side};
                x += step + scaledDip(ToolbarMetrics::groupGapDip, dpiX);
            } else {
                x += scaledDip(extraGapAfter(action), dpiX);
            }
        }
    }

    void loadIcons()
    {
        icons.reserve(fullToolbarActions().size() + 2U);
        const auto loadIcon = [this](const ToolbarIconSpec &icon) {
            return decodeResourcePng(instance, toolbarResourceId(icon, dpiX),
                                     toolbarIconPixelEdge(icon, dpiX));
        };
        icons.push_back(loadIcon(dragHandleIcon()));
        for (const auto action : fullToolbarActions()) {
            const auto &icon =
                action == ToolbarAction::undo || action == ToolbarAction::redo
                    ? disabledToolbarIcon(action)
                    : toolbarIcon(action);
            icons.push_back(loadIcon(icon));
        }
        icons.push_back(loadIcon(dragHandleIcon()));
        finishIcon = loadIcon(toolbarIcon(ToolbarAction::finishEditing));
    }

    void hideChrome() noexcept
    {
        for (const auto window : {borderWindow, toolbarWindow, previewWindow}) {
            if (window != nullptr) ShowWindow(window, SW_HIDE);
        }
        GdiFlush();
    }

    void showChrome() noexcept
    {
        for (const auto window : {borderWindow, previewWindow, toolbarWindow}) {
            if (window != nullptr) {
                ShowWindow(window, SW_SHOWNOACTIVATE);
                SetWindowPos(window, HWND_TOPMOST, 0, 0, 0, 0,
                             SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
                InvalidateRect(window, nullptr, FALSE);
            }
        }
    }

    void captureNextFrame(int wheelDelta) noexcept
    {
        if (terminal || session.phase() == ScrollCapturePhase::paused) {
            return;
        }
        hideChrome();
        auto frame = capturer.capture(selection);
        showChrome();
        if (!frame.has_value()) {
            session.pause(ScrollCapturePauseReason::captureFailure);
            updateCaptureNotice();
            InvalidateRect(previewWindow, nullptr, FALSE);
            return;
        }
        ScrollCaptureUpdate update;
        if (!session.append(std::move(*frame), wheelDelta, update)) {
            if (session.phase() != ScrollCapturePhase::paused) {
                session.pause(ScrollCapturePauseReason::captureFailure);
            }
            updateCaptureNotice();
            InvalidateRect(previewWindow, nullptr, FALSE);
            return;
        }
        if (update.append.direction
            != snipory::core::scroll::ScrollDirection::Undetermined) {
            direction = update.append.direction;
        }
        if (update.preview.has_value()) preview = std::move(update.preview);
        updateCaptureNotice();
        InvalidateRect(previewWindow, nullptr, FALSE);
    }

    void updateCaptureNotice()
    {
        captureNotice.clear();
        if (session.phase() == ScrollCapturePhase::paused) {
            switch (session.pauseReason().value_or(
                ScrollCapturePauseReason::captureFailure)) {
            case ScrollCapturePauseReason::captureFailure:
                captureNotice = L"画面采集失败，按 Enter 完成或 Esc 取消";
                break;
            case ScrollCapturePauseReason::resourceLimit:
                captureNotice = L"已达到内存上限，按 Enter 完成";
                break;
            case ScrollCapturePauseReason::maximumHeightReached:
                captureNotice = L"已达到 200,000 px 上限，按 Enter 完成";
                break;
            }
        } else if (session.warning() == ScrollCaptureWarning::lowConfidence) {
            captureNotice = L"本帧匹配置信度较低，已自动跳过";
        } else if (ScrollCaptureSession::requiresSaveOnlyForHeight(
                       session.outputHeight())) {
            captureNotice = L"已进入超长截图模式，完成后将直接保存";
        }
    }

    bool prepareEditorSampling() noexcept
    {
        try {
            if (!finalPixels.has_value() || editorLayout.bounds.width <= 0) {
                return false;
            }
            const auto width = static_cast<std::size_t>(editorLayout.bounds.width);
            editorSampleX0.resize(width);
            editorSampleX1.resize(width);
            editorSampleXFraction.resize(width);
            const auto scale = (std::max)(editorLayout.displayScale, 0.0001);
            for (std::size_t column = 0; column < width; ++column) {
                const auto sourceX =
                    (std::max)(0.0,
                               (std::min)(static_cast<double>(finalPixels->width() - 1),
                                          (static_cast<double>(column) + 0.5) / scale -
                                              0.5));
                const auto x0 = static_cast<std::int64_t>(std::floor(sourceX));
                editorSampleX0[column] = x0;
                editorSampleX1[column] = (std::min)(finalPixels->width() - 1, x0 + 1);
                editorSampleXFraction[column] = sourceX - x0;
            }
            return true;
        } catch (...) {
            return false;
        }
    }

    bool renderEditorViewport(PixelBuffer &viewport, std::int64_t sourceOffset) noexcept
    {
        if (!finalPixels.has_value() || viewport.width() != editorLayout.bounds.width ||
            viewport.height() != editorLayout.bounds.height ||
            editorSampleX0.size() != static_cast<std::size_t>(viewport.width())) {
            return false;
        }
        sourceOffset = clampedLongImageOffset(sourceOffset, editorLayout);
        const auto scale = (std::max)(editorLayout.displayScale, 0.0001);
        for (std::int64_t row = 0; row < viewport.height(); ++row) {
            auto *destination =
                viewport.data() + static_cast<std::uint64_t>(row) * viewport.stride();
            const auto sourceY =
                (std::max)(0.0,
                           (std::min)(static_cast<double>(finalPixels->height() - 1),
                                      sourceOffset +
                                          (static_cast<double>(row) + 0.5) / scale -
                                          0.5));
            const auto y0 = static_cast<std::int64_t>(std::floor(sourceY));
            const auto y1 = (std::min)(finalPixels->height() - 1, y0 + 1);
            const auto yFraction = sourceY - y0;
            for (std::size_t column = 0; column < editorSampleX0.size(); ++column) {
                const auto x0 = editorSampleX0[column];
                const auto x1 = editorSampleX1[column];
                const auto xFraction = editorSampleXFraction[column];
                const auto *topLeft =
                    finalPixels->data() +
                    static_cast<std::uint64_t>(y0) * finalPixels->stride() +
                    static_cast<std::uint64_t>(x0) * 4U;
                const auto *topRight =
                    finalPixels->data() +
                    static_cast<std::uint64_t>(y0) * finalPixels->stride() +
                    static_cast<std::uint64_t>(x1) * 4U;
                const auto *bottomLeft =
                    finalPixels->data() +
                    static_cast<std::uint64_t>(y1) * finalPixels->stride() +
                    static_cast<std::uint64_t>(x0) * 4U;
                const auto *bottomRight =
                    finalPixels->data() +
                    static_cast<std::uint64_t>(y1) * finalPixels->stride() +
                    static_cast<std::uint64_t>(x1) * 4U;
                for (std::size_t channel = 0; channel < 4U; ++channel) {
                    const auto top =
                        std::to_integer<unsigned int>(topLeft[channel]) *
                            (1.0 - xFraction) +
                        std::to_integer<unsigned int>(topRight[channel]) * xFraction;
                    const auto bottom =
                        std::to_integer<unsigned int>(bottomLeft[channel]) *
                            (1.0 - xFraction) +
                        std::to_integer<unsigned int>(bottomRight[channel]) * xFraction;
                    destination[column * 4U + channel] =
                        static_cast<std::byte>(static_cast<unsigned char>(
                            std::lround(top * (1.0 - yFraction) + bottom * yFraction)));
                }
            }
        }
        return true;
    }

    std::unique_ptr<FrozenDesktop> makeEditorDesktop(std::int64_t sourceOffset) noexcept
    {
        try {
            if (editorBudget == nullptr || !prepareEditorSampling()) return nullptr;
            auto viewport = PixelBuffer::allocate(
                editorLayout.bounds.width, editorLayout.bounds.height, *editorBudget);
            if (!viewport.value ||
                !renderEditorViewport(*viewport.value, sourceOffset)) {
                return nullptr;
            }
            const DisplayDescriptor descriptor{
                L"XXSNAP_LONG_IMAGE_EDITOR",     editorLayout.bounds, dpiX, dpiY,
                DISPLAYCONFIG_ROTATION_IDENTITY,
            };
            const auto topology = buildDisplayTopologySnapshot({descriptor});
            if (!topology.hasValue()) return nullptr;
            std::vector<FrozenDisplay> displays;
            displays.emplace_back(descriptor, std::move(*viewport.value));
            return std::make_unique<FrozenDesktop>(*topology.value(),
                                                   std::move(displays),
                                                   std::chrono::steady_clock::now());
        } catch (...) {
            return nullptr;
        }
    }

    void scrollEditor(int wheelDelta) noexcept
    {
        if (!reviewing || longImageEditor == nullptr || editorDesktop == nullptr ||
            wheelDelta == 0) {
            return;
        }
        const auto sourceDelta = static_cast<std::int64_t>(
            std::lround(static_cast<double>(wheelDelta) /
                        (std::max)(editorLayout.displayScale, 0.0001)));
        const auto next =
            clampedLongImageOffset(reviewOffset - sourceDelta, editorLayout);
        if (next == reviewOffset ||
            !renderEditorViewport(editorDesktop->displays.front().pixels, next) ||
            !longImageEditor->updateLongImageViewport(
                *editorDesktop, longImageAnnotationOrigin(next, dpiY))) {
            return;
        }
        reviewOffset = next;
    }

    void exportEdited(OverlayInputAction action) noexcept
    {
        try {
            if (!reviewing || !finalPixels.has_value() || longImageEditor == nullptr) {
                return;
            }
            if (action == OverlayInputAction::cancel) {
                complete({ScrollCaptureHostStatus::cancelled, std::nullopt});
                return;
            }
            if (action == OverlayInputAction::finishEditing) {
                action = OverlayInputAction::copy;
            }
            if (action != OverlayInputAction::copy &&
                action != OverlayInputAction::pin &&
                action != OverlayInputAction::save) {
                return;
            }
            const auto annotations = longImageEditor->annotationSnapshot();
            if (composeAnnotations(*finalPixels, annotations.plan, annotations.dpiX,
                                   annotations.dpiY, 0, 0, nullptr,
                                   annotations.eraserMasks)
                    .has_value()) {
                complete({ScrollCaptureHostStatus::failed, std::nullopt});
                return;
            }
            exportFinal(action == OverlayInputAction::save
                            ? ScrollCaptureHostExportAction::save
                        : action == OverlayInputAction::pin
                            ? ScrollCaptureHostExportAction::pin
                            : ScrollCaptureHostExportAction::copy);
        } catch (...) {
            complete({ScrollCaptureHostStatus::failed, std::nullopt});
        }
    }

    void finish() noexcept
    {
        if (terminal) return;
        KillTimer(toolbarWindow, captureTimerIdentifier);
        captureTimerScheduled = false;
        auto final = session.finish(maximumAcceptedBytes);
        if (!final.has_value()) {
            updateCaptureNotice();
            if (captureNotice.empty()) {
                captureNotice = L"生成长截图失败，请按 Enter 重试或 Esc 取消";
            }
            InvalidateRect(previewWindow, nullptr, FALSE);
            return;
        }
        finalPixels.emplace(std::move(*final));
        reviewing = true;
        if (ScrollCaptureSession::requiresSaveOnlyForHeight(
                static_cast<int>(finalPixels->height()))) {
            exportFinal(ScrollCaptureHostExportAction::save);
            return;
        }
        reviewOffset = 0;
        if (mouseHook != nullptr) {
            UnhookWindowsHookEx(mouseHook);
            mouseHook = nullptr;
        }
        if (keyboardHook != nullptr) {
            UnhookWindowsHookEx(keyboardHook);
            keyboardHook = nullptr;
        }
        hideChrome();
        editorLayout = longImageEditorLayout(workArea, finalPixels->width(),
                                             finalPixels->height(), dpiX, dpiY);
        try {
            editorBudget = std::make_unique<MemoryBudget>(
                (std::max<std::size_t>)(maximumAcceptedBytes,
                                        static_cast<std::size_t>(
                                            finalPixels->byteCount()) *
                                            2U));
        } catch (...) {
            complete({ScrollCaptureHostStatus::failed, std::nullopt});
            return;
        }
        editorDesktop = makeEditorDesktop(0);
        if (editorDesktop == nullptr) {
            complete({ScrollCaptureHostStatus::failed, std::nullopt});
            return;
        }
        const AnnotationRect canvasBounds{
            0.0F,
            0.0F,
            physicalPixelsToDip(finalPixels->width(), dpiX),
            physicalPixelsToDip(finalPixels->height(), dpiY),
        };
        auto created = OverlayHost::createLongImageEditor(
            instance, *editorDesktop, canvasBounds,
            [this](int delta) { scrollEditor(delta); },
            [this](OverlayInputAction action) { exportEdited(action); });
        longImageEditor = std::move(created.value);
        if (longImageEditor == nullptr) {
            complete({ScrollCaptureHostStatus::failed, std::nullopt});
            return;
        }
        longImageEditor->show();
    }

    void exportFinal(ScrollCaptureHostExportAction action) noexcept
    {
        if (!reviewing || !finalPixels.has_value()) return;
        ScrollCaptureHostResult result;
        result.status = ScrollCaptureHostStatus::completed;
        result.pixels.emplace(std::move(*finalPixels));
        result.action = action;
        complete(std::move(result));
    }

    void complete(ScrollCaptureHostResult result) noexcept
    {
        if (terminal) return;
        terminal = true;
        hideChrome();
        if (mouseHook != nullptr) {
            UnhookWindowsHookEx(mouseHook);
            mouseHook = nullptr;
        }
        if (keyboardHook != nullptr) {
            UnhookWindowsHookEx(keyboardHook);
            keyboardHook = nullptr;
        }
        if (active == this) active = nullptr;
        auto completion = std::move(callback);
        if (completion) completion(std::move(result));
    }

    void paint(HWND window) noexcept
    {
        PAINTSTRUCT paint{};
        const auto dc = BeginPaint(window, &paint);
        RECT client{};
        GetClientRect(window, &client);
        if (window == borderWindow) {
            const auto color = targetResolved ? RGB(52, 199, 89) : RGB(83, 120, 232);
            const auto brush = CreateSolidBrush(color);
            FillRect(dc, &client, brush);
            DeleteObject(brush);
        } else if (window == toolbarWindow) {
            paintToolbar(dc, client);
        } else if (window == previewWindow) {
            paintPreview(dc, client);
        }
        EndPaint(window, &paint);
    }

    void drawIcon(HDC target, const IconBitmap &icon, RECT destination,
                  BYTE alpha) noexcept
    {
        if (icon.bitmap == nullptr) return;
        const auto source = CreateCompatibleDC(target);
        const auto previous = SelectObject(source, icon.bitmap);
        BLENDFUNCTION blend{AC_SRC_OVER, 0, alpha, AC_SRC_ALPHA};
        AlphaBlend(target, destination.left, destination.top,
                   destination.right - destination.left,
                   destination.bottom - destination.top, source, 0, 0, icon.width,
                   icon.height, blend);
        SelectObject(source, previous);
        DeleteDC(source);
    }

    RECT iconRect(RECT button, const IconBitmap &icon) const noexcept
    {
        const auto x = button.left + ((button.right - button.left) - icon.width) / 2;
        const auto y = button.top + ((button.bottom - button.top) - icon.height) / 2;
        return {x, y, x + icon.width, y + icon.height};
    }

    void paintToolbar(HDC dc, RECT client) noexcept
    {
        const auto background =
            CreateSolidBrush(RGB(VisualStyleCatalog::toolbarBackgroundColor.red,
                                 VisualStyleCatalog::toolbarBackgroundColor.green,
                                 VisualStyleCatalog::toolbarBackgroundColor.blue));
        FillRect(dc, &client, background);
        DeleteObject(background);
        const auto step = scaledDip(ToolbarMetrics::buttonStepDip, dpiX);
        const auto side = scaledDip(ToolbarMetrics::buttonSizeDip, dpiX);
        const auto y = (client.bottom - side) / 2;
        int x = scaledDip(ToolbarMetrics::horizontalPaddingDip, dpiX);
        if (!icons.empty()) {
            const RECT button{x, y, x + side, y + side};
            drawIcon(dc, icons.front(), iconRect(button, icons.front()), 255U);
        }
        x += step;
        std::size_t iconIndex = 1U;
        const auto separatorBrush = CreateSolidBrush(RGB(172, 172, 172));
        for (const auto action : fullToolbarActions()) {
            RECT button{x, y, x + side, y + side};
            if (action == ToolbarAction::scroll) {
                const auto selected = CreateSolidBrush(RGB(210, 228, 255));
                const auto region = CreateRoundRectRgn(
                    button.left, button.top, button.right, button.bottom,
                    scaledDip(4.0F, dpiX), scaledDip(4.0F, dpiY));
                FillRgn(dc, region, selected);
                DeleteObject(region);
                DeleteObject(selected);
            }
            if (iconIndex < icons.size()) {
                drawIcon(dc, icons[iconIndex], iconRect(button, icons[iconIndex]),
                         action == ToolbarAction::scroll ? 255U : 64U);
            }
            ++iconIndex;
            x += step;
            if (action == ToolbarAction::scroll) {
                drawIcon(dc, finishIcon, iconRect(finishButton, finishIcon), 255U);
                x += step + scaledDip(ToolbarMetrics::groupGapDip, dpiX);
            } else {
                const auto gap = scaledDip(extraGapAfter(action), dpiX);
                if (gap > 0) {
                    RECT separator{
                        x + gap / 2 - 1,
                        scaledDip(8.0F, dpiY),
                        x + gap / 2 + 1,
                        client.bottom - scaledDip(8.0F, dpiY),
                    };
                    FillRect(dc, &separator, separatorBrush);
                }
                x += gap;
            }
        }
        if (iconIndex < icons.size()) {
            const RECT button{x, y, x + side, y + side};
            drawIcon(dc, icons[iconIndex], iconRect(button, icons[iconIndex]), 255U);
        }
        DeleteObject(separatorBrush);
    }

    void paintPreview(HDC dc, RECT client) noexcept
    {
        const auto background = CreateSolidBrush(RGB(246, 246, 246));
        FillRect(dc, &client, background);
        DeleteObject(background);
        if (!preview.has_value() || !preview->isValid()) return;
        const auto availableWidth = (std::max)(1L, client.right - client.left - 16L);
        const auto availableHeight = (std::max)(1L, client.bottom - client.top - 34L);
        const auto scale =
            (std::min)(static_cast<double>(availableWidth) / preview->width,
                       static_cast<double>(availableHeight) / preview->height);
        const auto width = (std::max)(1, static_cast<int>(preview->width * scale));
        const auto height = (std::max)(1, static_cast<int>(preview->height * scale));
        const auto x = (client.right - width) / 2;
        const auto y = client.bottom - 26 - height;
        BITMAPINFO info{};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = preview->width;
        info.bmiHeader.biHeight = -preview->height;
        info.bmiHeader.biPlanes = 1U;
        info.bmiHeader.biBitCount = 32U;
        info.bmiHeader.biCompression = BI_RGB;
        SetStretchBltMode(dc, HALFTONE);
        StretchDIBits(dc, x, y, width, height, 0, 0, preview->width, preview->height,
                      preview->pixels.data(), &info, DIB_RGB_COLORS, SRCCOPY);
        const auto outputHeight = (std::max)(1, session.outputHeight());
        const auto viewportHeight =
            (std::max)(2,
                       static_cast<int>(height * static_cast<double>(selection.height) /
                                        outputHeight));
        const auto viewportY = direction == snipory::core::scroll::ScrollDirection::Up
                                   ? y
                                   : y + height - (std::min)(height, viewportHeight);
        const auto blue =
            CreatePen(PS_SOLID, (std::max)(1, scaledDip(2.0F, dpiX)), RGB(0, 122, 255));
        const auto oldPen = SelectObject(dc, blue);
        const auto oldBrush = SelectObject(dc, GetStockObject(HOLLOW_BRUSH));
        Rectangle(dc, x, viewportY, x + width,
                  viewportY + (std::min)(height, viewportHeight));
        SelectObject(dc, oldBrush);
        SelectObject(dc, oldPen);
        DeleteObject(blue);
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, RGB(40, 40, 40));
        const auto font =
            CreateFontW(-scaledDip(12.0F, dpiY), 0, 0, 0, FW_MEDIUM, FALSE, FALSE,
                        FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                        CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei");
        const auto oldFont = SelectObject(dc, font);
        const auto label = std::to_wstring(outputHeight) + L" px";
        RECT labelRect{0, client.bottom - 24, client.right, client.bottom};
        DrawTextW(dc, label.data(), static_cast<int>(label.size()), &labelRect,
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        SelectObject(dc, oldFont);
        DeleteObject(font);
        paintCaptureNotice(dc, client);
    }

    void paintCaptureNotice(HDC dc, RECT client) noexcept
    {
        if (captureNotice.empty()) return;
        const auto margin = scaledDip(8.0F, dpiX);
        const auto height = scaledDip(44.0F, dpiY);
        const auto width =
            (std::min)(scaledDip(292.0F, dpiX),
                       (std::max)(1, static_cast<int>(client.right - client.left) -
                                         margin * 2));
        RECT panel{margin, margin, margin + width, margin + height};
        const auto radius = scaledDip(11.0F, dpiX);
        const auto region = CreateRoundRectRgn(panel.left, panel.top, panel.right,
                                               panel.bottom, radius, radius);
        const auto background = CreateSolidBrush(RGB(28, 28, 30));
        FillRgn(dc, region, background);
        DeleteObject(background);
        DeleteObject(region);

        RECT accent{
            panel.left,
            panel.top,
            panel.left + scaledDip(4.0F, dpiX),
            panel.bottom,
        };
        const auto accentBrush = CreateSolidBrush(RGB(255, 159, 10));
        FillRect(dc, &accent, accentBrush);
        DeleteObject(accentBrush);

        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, RGB(255, 255, 255));
        const auto font =
            CreateFontW(-scaledDip(12.0F, dpiY), 0, 0, 0, FW_MEDIUM, FALSE, FALSE,
                        FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                        CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei");
        const auto oldFont = SelectObject(dc, font);
        RECT textRect{
            panel.left + scaledDip(14.0F, dpiX),
            panel.top,
            panel.right - scaledDip(8.0F, dpiX),
            panel.bottom,
        };
        DrawTextW(dc, captureNotice.data(), static_cast<int>(captureNotice.size()),
                  &textRect, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
        SelectObject(dc, oldFont);
        DeleteObject(font);
    }
};

ScrollCaptureHost::Impl *ScrollCaptureHost::Impl::active = nullptr;

ScrollCaptureHost::ScrollCaptureHost(std::unique_ptr<Impl> impl) noexcept
    : impl_(std::move(impl))
{
}

ScrollCaptureHost::~ScrollCaptureHost() = default;

std::unique_ptr<ScrollCaptureHost> ScrollCaptureHost::create(
    HINSTANCE instance, PixelRect selection, DWORD targetProcessId, UINT dpiX,
    UINT dpiY, std::size_t maximumAcceptedBytes, CompletionCallback callback) noexcept
{
    try {
        auto impl = std::make_unique<Impl>(maximumAcceptedBytes);
        impl->instance = instance != nullptr ? instance : GetModuleHandleW(nullptr);
        impl->originalSelection = selection;
        impl->targetProcessId = targetProcessId;
        impl->dpiX = dpiX == 0U ? 96U : dpiX;
        impl->dpiY = dpiY == 0U ? 96U : dpiY;
        impl->maximumAcceptedBytes = maximumAcceptedBytes;
        impl->callback = std::move(callback);
        if (impl->instance == nullptr || !impl->callback || !impl->initialize()) {
            return nullptr;
        }
        return std::unique_ptr<ScrollCaptureHost>(
            new ScrollCaptureHost(std::move(impl)));
    } catch (...) {
        return nullptr;
    }
}

} // namespace xxsnap::win
