#include "ocr/OcrResultPresenter.h"
#include "app/CaptureSound.h"
#include "app/PreferencesSettings.h"
#include "resource.h"

#include <algorithm>

namespace xxsnap::win {
namespace {

constexpr wchar_t resultWindowClass[] = L"XxSnap.OcrResultWindow.v1";
constexpr int panelWidth = 176;
constexpr int panelHeight = 124;
constexpr UINT_PTR dismissTimer = 1;

PixelRect targetWorkArea(PixelRect selection) noexcept
{
    selection = snipory::core::portable::standardized(selection);
    POINT center{
        static_cast<LONG>(selection.x + selection.width / 2),
        static_cast<LONG>(selection.y + selection.height / 2),
    };
    const auto monitor = MonitorFromPoint(center, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info)) {
        return {info.rcWork.left, info.rcWork.top,
            info.rcWork.right - info.rcWork.left,
            info.rcWork.bottom - info.rcWork.top};
    }
    return {0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};
}

} // namespace

struct OcrResultPresenter::Impl final {
    HINSTANCE instance = nullptr;
    HWND owner = nullptr;
    HWND window = nullptr;
    bool success = false;

    Impl(HINSTANCE module, HWND sourceOwner) noexcept
        : instance(module != nullptr ? module : GetModuleHandleW(nullptr))
        , owner(sourceOwner)
    {
    }

    ~Impl()
    {
        close();
        UnregisterClassW(resultWindowClass, instance);
    }

    static LRESULT CALLBACK windowProcedure(
        HWND window, UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        auto* self = reinterpret_cast<Impl*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lParam);
            self = static_cast<Impl*>(create->lpCreateParams);
            self->window = window;
            SetWindowLongPtrW(
                window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
        return self != nullptr
            ? self->handle(message, wParam, lParam)
            : DefWindowProcW(window, message, wParam, lParam);
    }

    bool ensureWindow() noexcept
    {
        if (window != nullptr) return true;
        WNDCLASSEXW value{};
        value.cbSize = sizeof(value);
        value.lpfnWndProc = windowProcedure;
        value.hInstance = instance;
        value.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
        value.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
        value.lpszClassName = resultWindowClass;
        if (RegisterClassExW(&value) == 0
            && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            return false;
        }
        window = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
                | WS_EX_LAYERED,
            resultWindowClass,
            L"",
            WS_POPUP,
            0, 0, panelWidth, panelHeight,
            owner, nullptr, instance, this);
        return window != nullptr;
    }

    void show(bool value, PixelRect selection) noexcept
    {
        if (!ensureWindow()) return;
        success = value;
        SetWindowTextW(window, success
            ? L"\u8bc6\u522b\u6210\u529f\n\u5df2\u590d\u5236\u5230\u526a\u5207\u677f"
            : L"\u8bc6\u522b\u5931\u8d25");
        KillTimer(window, dismissTimer);
        const auto work = targetWorkArea(selection);
        const auto x = work.x + (work.width - panelWidth) / 2;
        const auto y = work.y + work.height - panelHeight - 100;
        SetLayeredWindowAttributes(window, 0, 245, LWA_ALPHA);
        const auto region = CreateRoundRectRgn(
            0, 0, panelWidth + 1, panelHeight + 1, 24, 24);
        if (region != nullptr && SetWindowRgn(window, region, FALSE) == 0) {
            DeleteObject(region);
        }
        SetWindowPos(window, HWND_TOPMOST,
            static_cast<int>(x), static_cast<int>(y), panelWidth, panelHeight,
            SWP_NOACTIVATE | SWP_SHOWWINDOW);
        SetTimer(window, dismissTimer, 3000, nullptr);
        InvalidateRect(window, nullptr, FALSE);
        UpdateWindow(window);
    }

    void close() noexcept
    {
        if (window == nullptr) return;
        KillTimer(window, dismissTimer);
        const auto stale = window;
        window = nullptr;
        DestroyWindow(stale);
    }

    void paint() noexcept
    {
        PAINTSTRUCT paint{};
        const auto dc = BeginPaint(window, &paint);
        RECT client{};
        GetClientRect(window, &client);
        const auto background = CreateSolidBrush(RGB(255, 255, 255));
        FillRect(dc, &client, background);
        DeleteObject(background);
        const auto border = CreatePen(PS_SOLID, 1, RGB(205, 205, 205));
        const auto previousPen = SelectObject(dc, border);
        const auto previousBrush = SelectObject(dc, GetStockObject(NULL_BRUSH));
        RoundRect(dc, 0, 0, panelWidth, panelHeight, 24, 24);
        SelectObject(dc, previousBrush);
        SelectObject(dc, previousPen);
        DeleteObject(border);

        SetBkMode(dc, TRANSPARENT);
        const auto titleFont = CreateFontW(
            16, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
            L"Microsoft YaHei");
        const auto detailFont = CreateFontW(
            13, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
            L"Microsoft YaHei");
        const auto bitmap = reinterpret_cast<HBITMAP>(LoadImageW(
            instance,
            MAKEINTRESOURCEW(success ? IDB_OCR_CORRECT : IDB_OCR_FAILED),
            IMAGE_BITMAP, 30, 30, LR_CREATEDIBSECTION));
        if (bitmap != nullptr) {
            const auto source = CreateCompatibleDC(dc);
            const auto previous = SelectObject(source, bitmap);
            BitBlt(dc, (panelWidth - 30) / 2, 15, 30, 30,
                source, 0, 0, SRCCOPY);
            SelectObject(source, previous);
            DeleteDC(source);
            DeleteObject(bitmap);
        }
        RECT title{8, 53, panelWidth - 8, 80};
        SelectObject(dc, titleFont);
        SetTextColor(dc, RGB(30, 30, 30));
        DrawTextW(dc, success ? L"\u8bc6\u522b\u6210\u529f" : L"\u8bc6\u522b\u5931\u8d25",
            -1, &title, DT_CENTER | DT_SINGLELINE | DT_VCENTER);
        if (success) {
            RECT detail{8, 82, panelWidth - 8, 105};
            SelectObject(dc, detailFont);
            SetTextColor(dc, RGB(110, 110, 110));
            DrawTextW(dc, L"\u5df2\u590d\u5236\u5230\u526a\u5207\u677f", -1, &detail,
                DT_CENTER | DT_SINGLELINE | DT_VCENTER);
        }
        DeleteObject(titleFont);
        DeleteObject(detailFont);
        EndPaint(window, &paint);
    }

    LRESULT handle(UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        switch (message) {
        case WM_PAINT: paint(); return 0;
        case WM_ERASEBKGND: return 1;
        case WM_TIMER: close(); return 0;
        case WM_NCDESTROY:
            window = nullptr;
            return 0;
        default:
            return DefWindowProcW(window, message, wParam, lParam);
        }
    }
};

OcrResultPresenter::OcrResultPresenter(
    HINSTANCE instance, HWND owner)
    : impl_(std::make_unique<Impl>(instance, owner))
{
}

OcrResultPresenter::~OcrResultPresenter() = default;

void OcrResultPresenter::showSuccess(PixelRect selection) noexcept
{
    SystemPreferencesRegistry registry;
    const auto settings = PreferencesSettingsStore(registry).load();
    if (shouldPlayTextRecognitionSuccessSound(settings)) {
        playTextRecognitionSuccessSound(impl_->instance);
    }
    if (shouldShowTextRecognitionSuccessNotification(settings)) {
        impl_->show(true, selection);
    }
}

void OcrResultPresenter::showFailure(PixelRect selection) noexcept
{
    impl_->show(false, selection);
}

void OcrResultPresenter::close() noexcept
{
    impl_->close();
}

} // namespace xxsnap::win
