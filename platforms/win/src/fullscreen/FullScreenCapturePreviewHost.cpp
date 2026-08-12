#include "fullscreen/FullScreenCapturePreviewHost.h"

#include "capture/DisplayTopology.h"
#include "export/AnnotationComposer.h"
#include "export/ClipboardWriter.h"
#include "export/PngWriter.h"
#include "overlay/OverlayHost.h"
#include "pin/PinnedImageHost.h"

#include <commdlg.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <new>
#include <optional>
#include <utility>
#include <vector>

namespace xxsnap::win {
namespace {

constexpr wchar_t previewWindowClass[] = L"XxSnapFullScreenPreviewWindow";
constexpr std::int64_t previewMaximumWidth = 320;
constexpr std::int64_t previewMaximumHeight = 220;
constexpr std::int64_t previewScreenInset = 20;
constexpr std::uint64_t editorMinimumMemoryBytes = 64ULL * 1024ULL * 1024ULL;

enum PreviewCommand : UINT {
    commandToolbar = 100,
    commandPin,
    commandCopy,
    commandSave,
    commandClose,
};

PixelRect currentWorkArea() noexcept
{
    POINT cursor{};
    GetCursorPos(&cursor);
    const auto monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info)) {
        return {
            info.rcWork.left,
            info.rcWork.top,
            info.rcWork.right - info.rcWork.left,
            info.rcWork.bottom - info.rcWork.top,
        };
    }
    return {0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};
}

} // namespace

PixelRect fullScreenPreviewRect(
    std::int64_t imageWidth,
    std::int64_t imageHeight,
    PixelRect workArea) noexcept
{
    workArea = snipory::core::portable::standardized(workArea);
    if (imageWidth <= 0 || imageHeight <= 0
        || workArea.width <= 0 || workArea.height <= 0) {
        return {};
    }
    const auto availableWidth = (std::max)(
        1LL, workArea.width - previewScreenInset * 2);
    const auto availableHeight = (std::max)(
        1LL, workArea.height - previewScreenInset * 2);
    const auto maximumWidth = (std::min)(previewMaximumWidth, availableWidth);
    const auto maximumHeight = (std::min)(previewMaximumHeight, availableHeight);
    const auto scale = (std::min)({
        static_cast<double>(maximumWidth) / static_cast<double>(imageWidth),
        static_cast<double>(maximumHeight) / static_cast<double>(imageHeight),
        1.0,
    });
    const auto width = (std::max)(1LL, static_cast<std::int64_t>(
        std::llround(static_cast<double>(imageWidth) * scale)));
    const auto height = (std::max)(1LL, static_cast<std::int64_t>(
        std::llround(static_cast<double>(imageHeight) * scale)));
    return {
        workArea.x + workArea.width - previewScreenInset - width,
        workArea.y + workArea.height - previewScreenInset - height,
        width,
        height,
    };
}

struct FullScreenCapturePreviewHost::Impl final {
    HINSTANCE instance = nullptr;
    HWND dialogOwner = nullptr;
    PinnedImageHost& pinnedImages;
    HWND window = nullptr;
    std::optional<PixelBuffer> pixels;
    PixelRect sourceRect{};
    bool shiftToolbarCandidate = false;
    bool alwaysOnTop = true;
    std::unique_ptr<MemoryBudget> editorBudget;
    std::unique_ptr<FrozenDesktop> editorDesktop;
    std::unique_ptr<OverlayHost> editor;

    Impl(HINSTANCE module, HWND owner, PinnedImageHost& pins) noexcept
        : instance(module != nullptr ? module : GetModuleHandleW(nullptr))
        , dialogOwner(owner)
        , pinnedImages(pins)
    {
    }

    ~Impl()
    {
        editor.reset();
        if (window != nullptr) DestroyWindow(window);
        UnregisterClassW(previewWindowClass, instance);
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

    bool registerWindowClass() noexcept
    {
        WNDCLASSEXW value{};
        value.cbSize = sizeof(value);
        value.lpfnWndProc = windowProcedure;
        value.hInstance = instance;
        value.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
        value.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
        value.lpszClassName = previewWindowClass;
        return RegisterClassExW(&value) != 0
            || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
    }

    bool createWindow() noexcept
    {
        if (window != nullptr) return true;
        if (!registerWindowClass()) return false;
        window = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
            previewWindowClass,
            L"",
            WS_POPUP,
            0, 0, 1, 1,
            nullptr, nullptr, instance, this);
        return window != nullptr;
    }

    void paint() noexcept
    {
        PAINTSTRUCT paint{};
        const auto dc = BeginPaint(window, &paint);
        RECT client{};
        GetClientRect(window, &client);
        FillRect(dc, &client, reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1));
        if (pixels.has_value()
            && pixels->stride() <= (std::numeric_limits<UINT>::max)()) {
            BITMAPINFO info{};
            info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
            info.bmiHeader.biWidth = static_cast<LONG>(pixels->width());
            info.bmiHeader.biHeight = -static_cast<LONG>(pixels->height());
            info.bmiHeader.biPlanes = 1;
            info.bmiHeader.biBitCount = 32;
            info.bmiHeader.biCompression = BI_RGB;
            SetStretchBltMode(dc, HALFTONE);
            StretchDIBits(dc,
                1, 1, (std::max)(0L, client.right - 2),
                (std::max)(0L, client.bottom - 2),
                0, 0,
                static_cast<int>(pixels->width()),
                static_cast<int>(pixels->height()),
                pixels->data(), &info, DIB_RGB_COLORS, SRCCOPY);
        }
        FrameRect(dc, &client, reinterpret_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
        EndPaint(window, &paint);
    }

    std::optional<PixelBuffer> copyPixels() noexcept
    {
        if (!pixels.has_value()) return std::nullopt;
        try {
            MemoryBudget budget(pixels->byteCount());
            auto copy = PixelBuffer::allocate(
                pixels->width(), pixels->height(), budget);
            if (!copy.value) return std::nullopt;
            std::memcpy(copy.value->data(), pixels->data(), pixels->byteCount());
            return std::move(*copy.value);
        } catch (...) {
            return std::nullopt;
        }
    }

    void replacePixels(PixelBuffer replacement) noexcept
    {
        pixels = std::move(replacement);
        if (window == nullptr) return;
        const auto preview = fullScreenPreviewRect(
            pixels->width(), pixels->height(), currentWorkArea());
        if (preview.width <= 0 || preview.height <= 0) return;
        SetWindowPos(window, HWND_TOPMOST,
            static_cast<int>(preview.x), static_cast<int>(preview.y),
            static_cast<int>(preview.width), static_cast<int>(preview.height),
            SWP_NOACTIVATE);
        InvalidateRect(window, nullptr, FALSE);
    }

    void copy() noexcept
    {
        if (pixels.has_value()) writeClipboard(*pixels, dialogOwner);
    }

    void save() noexcept
    {
        if (!pixels.has_value()) return;
        wchar_t path[MAX_PATH] = L"XxSnap.png";
        OPENFILENAMEW dialog{};
        dialog.lStructSize = sizeof(dialog);
        dialog.hwndOwner = window != nullptr ? window : dialogOwner;
        dialog.lpstrFilter = L"PNG \u56fe\u50cf (*.png)\0*.png\0\0";
        dialog.lpstrFile = path;
        dialog.nMaxFile = static_cast<DWORD>(std::size(path));
        dialog.lpstrDefExt = L"png";
        dialog.lpstrTitle = L"\u4fdd\u5b58\u5168\u5c4f\u622a\u56fe";
        dialog.Flags = OFN_NOCHANGEDIR | OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST;
        if (GetSaveFileNameW(&dialog)) savePngAtomically(*pixels, path);
    }

    void pin() noexcept
    {
        if (auto copy = copyPixels()) {
            RECT rect{};
            GetWindowRect(window, &rect);
            pinnedImages.pin(std::move(*copy), {
                rect.left, rect.top,
                rect.right - rect.left,
                rect.bottom - rect.top,
            });
        }
    }

    void finishEditing(OverlayInputAction action) noexcept
    {
        bool composed = true;
        if (editor != nullptr && pixels.has_value()) {
            auto annotations = editor->annotationSnapshot();
            auto staged = copyPixels();
            composed = staged.has_value()
                && !composeAnnotations(*staged, annotations.plan,
                    annotations.dpiX, annotations.dpiY,
                    0, 0,
                    &*pixels, annotations.eraserMasks).has_value();
            if (composed) replacePixels(std::move(*staged));
        }
        editor.reset();
        editorDesktop.reset();
        editorBudget.reset();
        if (window != nullptr) {
            ShowWindow(window, SW_SHOWNOACTIVATE);
            InvalidateRect(window, nullptr, FALSE);
        }
        if (!composed) {
            MessageBoxW(window,
                L"\u65e0\u6cd5\u5e94\u7528\u5168\u5c4f\u622a\u56fe\u7f16\u8f91\uff0c\u539f\u56fe\u5df2\u4fdd\u7559\u3002",
                L"XxSnap", MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
            return;
        }
        if (action == OverlayInputAction::copy) copy();
        else if (action == OverlayInputAction::save) save();
        else if (action == OverlayInputAction::pin) pin();
    }

    void hideEditor() noexcept
    {
        editor.reset();
        editorDesktop.reset();
        editorBudget.reset();
        if (window != nullptr) ShowWindow(window, SW_SHOWNOACTIVATE);
    }

    void showEditor() noexcept
    {
        if (!pixels.has_value() || editor != nullptr) return;
        try {
            const auto bytes = static_cast<std::uint64_t>(pixels->byteCount());
            if (bytes > (std::numeric_limits<std::uint64_t>::max)() / 3U) {
                return;
            }
            editorBudget = std::make_unique<MemoryBudget>((std::max)(
                bytes * 3U, bytes + editorMinimumMemoryBytes));
            auto displayPixels = PixelBuffer::allocate(
                pixels->width(), pixels->height(), *editorBudget);
            if (!displayPixels.value) {
                editorBudget.reset();
                return;
            }
            std::memcpy(displayPixels.value->data(),
                pixels->data(), pixels->byteCount());
            DisplayDescriptor descriptor{
                L"XxSnapFullScreenCapture",
                sourceRect,
                96, 96,
                DISPLAYCONFIG_ROTATION_IDENTITY,
            };
            auto topology = buildDisplayTopologySnapshot({descriptor});
            if (!topology.hasValue()) {
                editorBudget.reset();
                return;
            }
            std::vector<FrozenDisplay> displays;
            displays.emplace_back(descriptor, std::move(*displayPixels.value));
            editorDesktop = std::make_unique<FrozenDesktop>(
                *topology.value(), std::move(displays),
                std::chrono::steady_clock::now());
            auto created = OverlayHost::createPinnedImageEditor(
                instance, *editorDesktop,
                [this](OverlayInputAction action) {
                    if (action == OverlayInputAction::hideEditingToolbar) {
                        hideEditor();
                    } else if (action
                        == OverlayInputAction::togglePinnedImageAlwaysOnTop) {
                        alwaysOnTop = !alwaysOnTop;
                        if (editor != nullptr) editor->setAlwaysOnTop(alwaysOnTop);
                    } else {
                        finishEditing(action);
                    }
                }, alwaysOnTop);
            editor = std::move(created.value);
            if (editor == nullptr) {
                editorDesktop.reset();
                editorBudget.reset();
                return;
            }
            ShowWindow(window, SW_HIDE);
            editor->show();
        } catch (...) {
            hideEditor();
        }
    }

    void showContextMenu() noexcept
    {
        const auto menu = CreatePopupMenu();
        if (menu == nullptr) return;
        AppendMenuW(menu, MF_STRING, commandToolbar, L"\u663e\u793a\u5de5\u5177\u6761\tShift");
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(menu, MF_STRING, commandPin, L"\u8d34\u56fe");
        AppendMenuW(menu, MF_STRING, commandCopy, L"\u590d\u5236\u56fe\u7247\tCtrl+C");
        AppendMenuW(menu, MF_STRING, commandSave, L"\u4fdd\u5b58\u56fe\u7247\tCtrl+S");
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(menu, MF_STRING, commandClose, L"\u5173\u95ed\tCtrl+W");
        POINT point{};
        GetCursorPos(&point);
        const auto command = TrackPopupMenu(menu,
            TPM_RETURNCMD | TPM_RIGHTBUTTON,
            point.x, point.y, 0, window, nullptr);
        DestroyMenu(menu);
        perform(command);
    }

    void perform(UINT command) noexcept
    {
        switch (command) {
        case commandToolbar: showEditor(); break;
        case commandPin: pin(); break;
        case commandCopy: copy(); break;
        case commandSave: save(); break;
        case commandClose:
            if (window != nullptr) DestroyWindow(window);
            break;
        default: break;
        }
    }

    LRESULT handle(UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        switch (message) {
        case WM_PAINT: paint(); return 0;
        case WM_ERASEBKGND: return 1;
        case WM_LBUTTONUP: showEditor(); return 0;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU: showContextMenu(); return 0;
        case WM_KEYDOWN: {
            const auto control = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
            const auto shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
            const auto alt = (GetKeyState(VK_MENU) & 0x8000) != 0;
            if (wParam != VK_SHIFT || control || alt) shiftToolbarCandidate = false;
            if (control && !shift && !alt && wParam == 'C') copy();
            else if (control && !shift && !alt && wParam == 'S') save();
            else if (control && !shift && !alt && wParam == 'W') perform(commandClose);
            else if (!control && !alt && wParam == VK_SHIFT) {
                shiftToolbarCandidate = true;
            } else {
                break;
            }
            return 0;
        }
        case WM_KEYUP:
            if (wParam == VK_SHIFT && shiftToolbarCandidate) {
                shiftToolbarCandidate = false;
                showEditor();
                return 0;
            }
            shiftToolbarCandidate = false;
            break;
        case WM_NCDESTROY: {
            const auto stale = window;
            SetWindowLongPtrW(stale, GWLP_USERDATA, 0);
            window = nullptr;
            pixels.reset();
            return DefWindowProcW(stale, message, wParam, lParam);
        }
        default: break;
        }
        return DefWindowProcW(window, message, wParam, lParam);
    }

    bool show(PixelBuffer source, PixelRect rect) noexcept
    {
        editor.reset();
        editorDesktop.reset();
        editorBudget.reset();
        if (window != nullptr) DestroyWindow(window);
        pixels.reset();
        sourceRect = snipory::core::portable::standardized(rect);
        if (source.width() <= 0 || source.height() <= 0
            || sourceRect.width != source.width()
            || sourceRect.height != source.height()
            || !createWindow()) {
            return false;
        }
        pixels = std::move(source);
        const auto preview = fullScreenPreviewRect(
            pixels->width(), pixels->height(), currentWorkArea());
        if (preview.width <= 0 || preview.height <= 0) return false;
        SetWindowPos(window, HWND_TOPMOST,
            static_cast<int>(preview.x), static_cast<int>(preview.y),
            static_cast<int>(preview.width), static_cast<int>(preview.height),
            SWP_SHOWWINDOW);
        UpdateWindow(window);
        return true;
    }
};

FullScreenCapturePreviewHost::FullScreenCapturePreviewHost(
    HINSTANCE instance, HWND dialogOwner, PinnedImageHost& pinnedImages)
    : impl_(std::make_unique<Impl>(instance, dialogOwner, pinnedImages))
{
}

FullScreenCapturePreviewHost::~FullScreenCapturePreviewHost() = default;

bool FullScreenCapturePreviewHost::show(
    PixelBuffer pixels, PixelRect sourceRect) noexcept
{
    return impl_ && impl_->show(std::move(pixels), sourceRect);
}

void FullScreenCapturePreviewHost::close() noexcept
{
    if (impl_ && impl_->window != nullptr) DestroyWindow(impl_->window);
}

bool FullScreenCapturePreviewHost::visible() const noexcept
{
    return impl_ && impl_->window != nullptr && IsWindowVisible(impl_->window);
}

} // namespace xxsnap::win
