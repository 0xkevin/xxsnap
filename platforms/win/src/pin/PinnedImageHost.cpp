#include "pin/PinnedImageHost.h"

#include "export/ClipboardWriter.h"
#include "export/PngWriter.h"
#include "pin/PinnedImageGeometry.h"
#include "capture/DisplayTopology.h"
#include "export/AnnotationComposer.h"
#include "overlay/OverlayHost.h"

#include <commdlg.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace xxsnap::win {
namespace {

constexpr wchar_t pinnedImageWindowClass[] = L"XxSnapPinnedImageWindow";
constexpr COLORREF transparentColor = RGB(1, 2, 3);
constexpr wchar_t editCompositionFailureText[] =
    L"\u65e0\u6cd5\u5e94\u7528\u8d34\u56fe\u7f16\u8f91\uff0c\u539f\u56fe\u5df2\u4fdd\u7559\u3002";

enum PinCommand : UINT {
    commandToolbar = 100,
    commandCopy,
    commandSave,
    commandReset,
    commandOpacity100,
    commandOpacity80,
    commandOpacity60,
    commandOpacity40,
    commandAlwaysOnTop,
    commandClose,
    commandCloseAll,
};

PixelRect monitorWorkArea(PixelRect rect) noexcept
{
    RECT native{
        static_cast<LONG>(rect.x), static_cast<LONG>(rect.y),
        static_cast<LONG>(rect.x + rect.width),
        static_cast<LONG>(rect.y + rect.height),
    };
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    const auto monitor = MonitorFromRect(&native, MONITOR_DEFAULTTONEAREST);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info)) {
        return {
            info.rcWork.left,
            info.rcWork.top,
            info.rcWork.right - info.rcWork.left,
            info.rcWork.bottom - info.rcWork.top,
        };
    }
    return rect;
}

bool fitsWindowCoordinate(std::int64_t value) noexcept
{
    return value >= (std::numeric_limits<int>::min)()
        && value <= (std::numeric_limits<int>::max)();
}

} // namespace

struct PinnedImageHost::Impl final {
    struct Pin final {
        Impl* owner = nullptr;
        HWND window = nullptr;
        PixelBuffer pixels;
        PixelRect initialImageRect{};
        PixelRect imageRect{};
        POINT dragOffset{};
        BYTE opacity = 255U;
        bool dragging = false;
        bool alwaysOnTop = true;
        bool shiftToolbarShortcutCandidate = false;
        std::optional<std::uint64_t> hiddenOrder;
        std::unique_ptr<MemoryBudget> editorBudget;
        std::unique_ptr<FrozenDesktop> editorDesktop;
        std::unique_ptr<OverlayHost> editor;

        Pin(Impl* host, PixelBuffer source) noexcept
            : owner(host), pixels(std::move(source))
        {
        }
    };

    HINSTANCE instance = nullptr;
    HWND dialogOwner = nullptr;
    std::vector<std::unique_ptr<Pin>> pins;
    std::uint64_t nextHiddenOrder = 1U;

    Impl(HINSTANCE module, HWND owner) noexcept
        : instance(module != nullptr ? module : GetModuleHandleW(nullptr))
        , dialogOwner(owner)
    {
    }

    ~Impl()
    {
        for (const auto& pin : pins) {
            if (pin->window != nullptr) DestroyWindow(pin->window);
        }
    }

    static LRESULT CALLBACK windowProcedure(
        HWND window, UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        auto* pin = reinterpret_cast<Pin*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lParam);
            pin = static_cast<Pin*>(create->lpCreateParams);
            pin->window = window;
            SetWindowLongPtrW(
                window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(pin));
        }
        return pin != nullptr
            ? pin->owner->handle(*pin, message, wParam, lParam)
            : DefWindowProcW(window, message, wParam, lParam);
    }

    bool registerWindowClass() noexcept
    {
        WNDCLASSEXW value{};
        value.cbSize = sizeof(value);
        value.style = CS_HREDRAW | CS_VREDRAW;
        value.lpfnWndProc = &Impl::windowProcedure;
        value.hInstance = instance;
        value.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
        value.lpszClassName = pinnedImageWindowClass;
        return RegisterClassExW(&value) != 0U
            || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
    }

    void discardClosedPins()
    {
        pins.erase(std::remove_if(pins.begin(), pins.end(),
            [](const auto& pin) { return pin->window == nullptr; }), pins.end());
    }

    bool add(PixelBuffer pixels, PixelRect sourceRect) noexcept
    {
        try {
            discardClosedPins();
            if (!registerWindowClass() || pixels.width() <= 0
                || pixels.height() <= 0) {
                return false;
            }
            sourceRect = snipory::core::portable::standardized(sourceRect);
            if (sourceRect.width <= 0 || sourceRect.height <= 0) {
                sourceRect = {0, 0, pixels.width(), pixels.height()};
            }
            const auto workArea = monitorWorkArea(sourceRect);
            const auto imageRect = initialPinnedImageRect(
                {pixels.width(), pixels.height()}, sourceRect, workArea);
            if (!fitsWindowCoordinate(imageRect.x - pinnedImageShadowOutset)
                || !fitsWindowCoordinate(imageRect.y - pinnedImageShadowOutset)
                || imageRect.width > (std::numeric_limits<int>::max)()
                || imageRect.height > (std::numeric_limits<int>::max)()) {
                return false;
            }
            auto pin = std::make_unique<Pin>(this, std::move(pixels));
            pin->initialImageRect = imageRect;
            pin->imageRect = imageRect;
            const auto window = CreateWindowExW(
                WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
                pinnedImageWindowClass, L"", WS_POPUP,
                static_cast<int>(imageRect.x - pinnedImageShadowOutset),
                static_cast<int>(imageRect.y - pinnedImageShadowOutset),
                static_cast<int>(imageRect.width + pinnedImageShadowOutset * 2),
                static_cast<int>(imageRect.height + pinnedImageShadowOutset * 2),
                nullptr, nullptr, instance, pin.get());
            if (window == nullptr) return false;
            SetLayeredWindowAttributes(
                window, transparentColor, pin->opacity,
                LWA_COLORKEY | LWA_ALPHA);
            pins.push_back(std::move(pin));
            ShowWindow(window, SW_SHOWNORMAL);
            SetWindowPos(window, HWND_TOPMOST, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
            SetForegroundWindow(window);
            UpdateWindow(window);
            return true;
        } catch (...) {
            return false;
        }
    }

    void paint(Pin& pin) noexcept
    {
        PAINTSTRUCT paint{};
        const auto dc = BeginPaint(pin.window, &paint);
        RECT client{};
        GetClientRect(pin.window, &client);
        const auto transparent = CreateSolidBrush(transparentColor);
        FillRect(dc, &client, transparent);
        DeleteObject(transparent);

        const RECT image{
            static_cast<LONG>(pinnedImageShadowOutset),
            static_cast<LONG>(pinnedImageShadowOutset),
            client.right - static_cast<LONG>(pinnedImageShadowOutset),
            client.bottom - static_cast<LONG>(pinnedImageShadowOutset),
        };
        const std::array<COLORREF, 5> glow{
            RGB(63, 127, 205), RGB(58, 130, 220), RGB(52, 137, 231),
            RGB(72, 153, 240), RGB(92, 166, 235),
        };
        for (std::size_t index = 0; index < glow.size(); ++index) {
            const auto inset = static_cast<int>(index * 3U + 2U);
            const auto pen = CreatePen(PS_SOLID, 2, glow[index]);
            const auto oldPen = SelectObject(dc, pen);
            const auto oldBrush = SelectObject(dc, GetStockObject(HOLLOW_BRUSH));
            Rectangle(dc, image.left - inset, image.top - inset,
                image.right + inset, image.bottom + inset);
            SelectObject(dc, oldBrush);
            SelectObject(dc, oldPen);
            DeleteObject(pen);
        }

        if (pin.pixels.stride() <= (std::numeric_limits<UINT>::max)()) {
            BITMAPINFO info{};
            info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
            info.bmiHeader.biWidth = static_cast<LONG>(pin.pixels.width());
            info.bmiHeader.biHeight = -static_cast<LONG>(pin.pixels.height());
            info.bmiHeader.biPlanes = 1U;
            info.bmiHeader.biBitCount = 32U;
            info.bmiHeader.biCompression = BI_RGB;
            SetStretchBltMode(dc, HALFTONE);
            StretchDIBits(dc,
                image.left, image.top,
                image.right - image.left, image.bottom - image.top,
                0, 0,
                static_cast<int>(pin.pixels.width()),
                static_cast<int>(pin.pixels.height()),
                pin.pixels.data(), &info, DIB_RGB_COLORS, SRCCOPY);
        }
        const auto edgePen = CreatePen(PS_SOLID, 1, RGB(92, 166, 235));
        const auto oldPen = SelectObject(dc, edgePen);
        const auto oldBrush = SelectObject(dc, GetStockObject(HOLLOW_BRUSH));
        Rectangle(dc, image.left, image.top, image.right, image.bottom);
        SelectObject(dc, oldBrush);
        SelectObject(dc, oldPen);
        DeleteObject(edgePen);
        EndPaint(pin.window, &paint);
    }

    void applyImageRect(Pin& pin, PixelRect imageRect) noexcept
    {
        pin.imageRect = imageRect;
        SetWindowPos(pin.window, pin.alwaysOnTop ? HWND_TOPMOST : HWND_NOTOPMOST,
            static_cast<int>(imageRect.x - pinnedImageShadowOutset),
            static_cast<int>(imageRect.y - pinnedImageShadowOutset),
            static_cast<int>(imageRect.width + pinnedImageShadowOutset * 2),
            static_cast<int>(imageRect.height + pinnedImageShadowOutset * 2),
            SWP_SHOWWINDOW);
        InvalidateRect(pin.window, nullptr, FALSE);
    }

    void scale(Pin& pin, double factor) noexcept
    {
        POINT anchor{};
        if (!GetCursorPos(&anchor)) {
            anchor.x = static_cast<LONG>(pin.imageRect.x + pin.imageRect.width / 2);
            anchor.y = static_cast<LONG>(pin.imageRect.y + pin.imageRect.height / 2);
        }
        const auto workArea = monitorWorkArea(pin.imageRect);
        const auto size = scaledPinnedImageSize(
            {pin.imageRect.width, pin.imageRect.height},
            static_cast<double>(pin.pixels.width())
                / static_cast<double>((std::max)(1LL, pin.pixels.height())),
            factor, workArea);
        const auto xRatio = static_cast<double>(anchor.x - pin.imageRect.x)
            / static_cast<double>((std::max)(1LL, pin.imageRect.width));
        const auto yRatio = static_cast<double>(anchor.y - pin.imageRect.y)
            / static_cast<double>((std::max)(1LL, pin.imageRect.height));
        applyImageRect(pin, {
            static_cast<std::int64_t>(std::llround(
                static_cast<double>(anchor.x) - size.width * xRatio)),
            static_cast<std::int64_t>(std::llround(
                static_cast<double>(anchor.y) - size.height * yRatio)),
            size.width,
            size.height,
        });
    }

    void copy(Pin& pin) noexcept
    {
        writeClipboard(pin.pixels, pin.window);
    }

    void finishEditing(Pin& pin, OverlayInputAction action) noexcept
    {
        bool compositionSucceeded = true;
        if (pin.editor != nullptr) {
            auto annotations = pin.editor->annotationSnapshot();
            const auto xScale = static_cast<float>(pin.pixels.width())
                / static_cast<float>((std::max)(1LL, pin.imageRect.width));
            const auto yScale = static_cast<float>(pin.pixels.height())
                / static_cast<float>((std::max)(1LL, pin.imageRect.height));
            for (auto& item : annotations.plan.items) {
                item.annotation = scaled(
                    std::move(item.annotation), xScale, yScale);
            }
            for (auto& mask : annotations.eraserMasks) {
                mask = scaled(std::move(mask), xScale, yScale);
            }
            MemoryBudget compositionBudget(pin.pixels.byteCount());
            auto staged = PixelBuffer::allocate(
                pin.pixels.width(), pin.pixels.height(), compositionBudget);
            if (!staged.value) {
                compositionSucceeded = false;
            } else {
                std::memcpy(staged.value->data(), pin.pixels.data(),
                    pin.pixels.byteCount());
                compositionSucceeded = !composeAnnotations(
                    *staged.value, annotations.plan, 96U, 96U,
                    0, 0, &pin.pixels, annotations.eraserMasks).has_value();
                if (compositionSucceeded) {
                    pin.pixels = std::move(*staged.value);
                }
            }
            if (compositionSucceeded) {
                if (action == OverlayInputAction::copy) copy(pin);
                else if (action == OverlayInputAction::save) save(pin);
            }
        }
        pin.editor.reset();
        pin.editorDesktop.reset();
        pin.editorBudget.reset();
        ShowWindow(pin.window, SW_SHOWNORMAL);
        SetForegroundWindow(pin.window);
        InvalidateRect(pin.window, nullptr, FALSE);
        if (!compositionSucceeded) {
            MessageBoxW(pin.window, editCompositionFailureText, L"XxSnap",
                MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
        }
    }

    void showEditor(Pin& pin) noexcept
    {
        if (pin.editor != nullptr) {
            pin.editor->show();
            return;
        }
        try {
            const auto bytes = static_cast<std::uint64_t>(pin.pixels.byteCount());
            pin.editorBudget = std::make_unique<MemoryBudget>((std::max)(
                bytes * 2U, 64ULL * 1024ULL * 1024ULL));
            const DisplayDescriptor descriptor{
                L"XXSNAP_PINNED_IMAGE_EDITOR",
                {pin.imageRect.x, pin.imageRect.y,
                    pin.imageRect.width, pin.imageRect.height},
                96U, 96U, DISPLAYCONFIG_ROTATION_IDENTITY,
            };
            const auto topology = buildDisplayTopologySnapshot({descriptor});
            if (!topology.hasValue()) {
                pin.editorBudget.reset();
                return;
            }
            std::vector<FrozenDisplay> displays;
            auto displayPixels = PixelBuffer::allocate(
                pin.imageRect.width, pin.imageRect.height, *pin.editorBudget);
            if (!displayPixels.value) {
                pin.editorBudget.reset();
                return;
            }
            if (pin.imageRect.width == pin.pixels.width()
                && pin.imageRect.height == pin.pixels.height()) {
                std::memcpy(displayPixels.value->data(), pin.pixels.data(),
                    pin.pixels.byteCount());
            } else {
                std::vector<std::uint64_t> sourceOffsets(
                    static_cast<std::size_t>(pin.imageRect.width));
                for (std::int64_t column = 0;
                     column < pin.imageRect.width; ++column) {
                    const auto sourceX = (std::min)(pin.pixels.width() - 1,
                        column * pin.pixels.width() / pin.imageRect.width);
                    sourceOffsets[static_cast<std::size_t>(column)]
                        = static_cast<std::uint64_t>(sourceX) * 4U;
                }
                for (std::int64_t row = 0; row < pin.imageRect.height; ++row) {
                    auto* destination = displayPixels.value->data()
                        + static_cast<std::uint64_t>(row)
                            * displayPixels.value->stride();
                    const auto sourceY = (std::min)(pin.pixels.height() - 1,
                        row * pin.pixels.height() / pin.imageRect.height);
                    const auto* source = pin.pixels.data()
                        + static_cast<std::uint64_t>(sourceY)
                            * pin.pixels.stride();
                    for (std::int64_t column = 0;
                         column < pin.imageRect.width; ++column) {
                        std::memcpy(destination + column * 4,
                            source + sourceOffsets[
                                static_cast<std::size_t>(column)],
                            4U);
                    }
                }
            }
            displays.emplace_back(descriptor, std::move(*displayPixels.value));
            pin.editorDesktop = std::make_unique<FrozenDesktop>(
                *topology.value(), std::move(displays),
                std::chrono::steady_clock::now());
            auto created = OverlayHost::createPinnedImageEditor(
                instance, *pin.editorDesktop,
                [this, &pin](OverlayInputAction action) {
                    if (action == OverlayInputAction::hideEditingToolbar) {
                        hideEditor(pin);
                    } else if (action
                        == OverlayInputAction::togglePinnedImageAlwaysOnTop) {
                        toggleAlwaysOnTop(pin);
                    } else {
                        finishEditing(pin, action);
                    }
                }, pin.alwaysOnTop);
            pin.editor = std::move(created.value);
            if (pin.editor == nullptr) {
                pin.editorDesktop.reset();
                pin.editorBudget.reset();
                return;
            }
            ShowWindow(pin.window, SW_HIDE);
            pin.editor->show();
        } catch (...) {
            pin.editor.reset();
            pin.editorDesktop.reset();
            pin.editorBudget.reset();
        }
    }

    void hideEditor(Pin& pin) noexcept
    {
        pin.editor.reset();
        pin.editorDesktop.reset();
        pin.editorBudget.reset();
        ShowWindow(pin.window, SW_SHOWNORMAL);
        SetForegroundWindow(pin.window);
    }

    void toggleAlwaysOnTop(Pin& pin) noexcept
    {
        pin.alwaysOnTop = !pin.alwaysOnTop;
        SetWindowPos(pin.window,
            pin.alwaysOnTop ? HWND_TOPMOST : HWND_NOTOPMOST,
            0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
        if (pin.editor != nullptr) {
            pin.editor->setAlwaysOnTop(pin.alwaysOnTop);
        }
    }

    void save(Pin& pin) noexcept
    {
        wchar_t path[MAX_PATH] = L"XxSnap.png";
        OPENFILENAMEW dialog{};
        dialog.lStructSize = sizeof(dialog);
        dialog.hwndOwner = pin.window != nullptr ? pin.window : dialogOwner;
        dialog.lpstrFilter = L"PNG 图像 (*.png)\0*.png\0\0";
        dialog.lpstrFile = path;
        dialog.nMaxFile = static_cast<DWORD>(std::size(path));
        dialog.lpstrDefExt = L"png";
        dialog.lpstrTitle = L"保存贴图";
        dialog.Flags = OFN_NOCHANGEDIR | OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST;
        if (GetSaveFileNameW(&dialog)) savePngAtomically(pin.pixels, path);
    }

    void setOpacity(Pin& pin, BYTE opacity) noexcept
    {
        pin.opacity = opacity;
        SetLayeredWindowAttributes(
            pin.window, transparentColor, pin.opacity,
            LWA_COLORKEY | LWA_ALPHA);
    }

    void closeAll() noexcept
    {
        std::vector<HWND> windows;
        windows.reserve(pins.size());
        for (const auto& pin : pins) {
            if (pin->window != nullptr) windows.push_back(pin->window);
        }
        for (const auto window : windows) DestroyWindow(window);
    }

    bool restoreMostRecentlyHidden() noexcept
    {
        Pin* found = nullptr;
        for (const auto& pin : pins) {
            if (pin->window != nullptr && pin->editor == nullptr
                && pin->hiddenOrder.has_value()
                && (found == nullptr
                    || *pin->hiddenOrder > *found->hiddenOrder)) {
                found = pin.get();
            }
        }
        if (found == nullptr) return false;
        found->hiddenOrder.reset();
        ShowWindow(found->window, SW_SHOWNORMAL);
        SetWindowPos(found->window,
            found->alwaysOnTop ? HWND_TOPMOST : HWND_NOTOPMOST,
            0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
        SetForegroundWindow(found->window);
        return true;
    }

    void showContextMenu(Pin& pin) noexcept
    {
        const auto menu = CreatePopupMenu();
        const auto opacityMenu = CreatePopupMenu();
        if (menu == nullptr || opacityMenu == nullptr) {
            if (opacityMenu != nullptr) DestroyMenu(opacityMenu);
            if (menu != nullptr) DestroyMenu(menu);
            return;
        }
        AppendMenuW(menu, MF_STRING, commandToolbar,
            L"显示工具条 (Shift)");
        AppendMenuW(menu, MF_STRING, commandCopy, L"复制图片\tCtrl+C");
        AppendMenuW(menu, MF_STRING, commandSave, L"保存图片\tCtrl+S");
        AppendMenuW(menu, MF_SEPARATOR, 0U, nullptr);
        AppendMenuW(menu, MF_STRING, commandReset, L"重置大小\tCtrl+R");
        AppendMenuW(opacityMenu,
            MF_STRING | (pin.opacity == 255U ? MF_CHECKED : 0U),
            commandOpacity100, L"100%");
        AppendMenuW(opacityMenu,
            MF_STRING | (pin.opacity == 204U ? MF_CHECKED : 0U),
            commandOpacity80, L"80%");
        AppendMenuW(opacityMenu,
            MF_STRING | (pin.opacity == 153U ? MF_CHECKED : 0U),
            commandOpacity60, L"60%");
        AppendMenuW(opacityMenu,
            MF_STRING | (pin.opacity == 102U ? MF_CHECKED : 0U),
            commandOpacity40, L"40%");
        AppendMenuW(menu, MF_POPUP,
            reinterpret_cast<UINT_PTR>(opacityMenu), L"透明度");
        AppendMenuW(menu,
            MF_STRING | (pin.alwaysOnTop ? MF_CHECKED : 0U),
            commandAlwaysOnTop, L"置顶\tCtrl+T");
        AppendMenuW(menu, MF_SEPARATOR, 0U, nullptr);
        AppendMenuW(menu, MF_STRING, commandClose, L"关闭\tCtrl+W");
        AppendMenuW(menu, MF_STRING, commandCloseAll,
            L"关闭全部贴图\tCtrl+Shift+W");
        POINT point{};
        GetCursorPos(&point);
        const auto command = TrackPopupMenu(menu,
            TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0,
            pin.window, nullptr);
        DestroyMenu(menu);
        if (command != 0U) perform(pin, command);
    }

    void perform(Pin& pin, UINT command) noexcept
    {
        switch (command) {
        case commandToolbar:
            if (pin.editor != nullptr) {
                hideEditor(pin);
            } else {
                showEditor(pin);
            }
            break;
        case commandCopy: copy(pin); break;
        case commandSave: save(pin); break;
        case commandReset: applyImageRect(pin, pin.initialImageRect); break;
        case commandOpacity100: setOpacity(pin, 255U); break;
        case commandOpacity80: setOpacity(pin, 204U); break;
        case commandOpacity60: setOpacity(pin, 153U); break;
        case commandOpacity40: setOpacity(pin, 102U); break;
        case commandAlwaysOnTop: toggleAlwaysOnTop(pin); break;
        case commandClose: DestroyWindow(pin.window); break;
        case commandCloseAll: closeAll(); break;
        default: break;
        }
    }

    LRESULT handle(
        Pin& pin, UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        switch (message) {
        case WM_PAINT:
            paint(pin);
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_LBUTTONDOWN: {
            pin.shiftToolbarShortcutCandidate = false;
            SetForegroundWindow(pin.window);
            SetCapture(pin.window);
            pin.dragging = true;
            POINT cursor{};
            RECT window{};
            GetCursorPos(&cursor);
            GetWindowRect(pin.window, &window);
            pin.dragOffset = {cursor.x - window.left, cursor.y - window.top};
            return 0;
        }
        case WM_MOUSEMOVE:
            if (pin.dragging && (wParam & MK_LBUTTON) != 0U) {
                pin.shiftToolbarShortcutCandidate = false;
                POINT cursor{};
                if (GetCursorPos(&cursor)) {
                    const auto x = cursor.x - pin.dragOffset.x;
                    const auto y = cursor.y - pin.dragOffset.y;
                    SetWindowPos(pin.window, nullptr, x, y, 0, 0,
                        SWP_NOSIZE | SWP_NOZORDER);
                    pin.imageRect.x = static_cast<std::int64_t>(x)
                        + pinnedImageShadowOutset;
                    pin.imageRect.y = static_cast<std::int64_t>(y)
                        + pinnedImageShadowOutset;
                }
            }
            return 0;
        case WM_LBUTTONUP:
            pin.shiftToolbarShortcutCandidate = false;
            if (pin.dragging) {
                pin.dragging = false;
                ReleaseCapture();
            }
            return 0;
        case WM_CAPTURECHANGED:
            pin.dragging = false;
            pin.shiftToolbarShortcutCandidate = false;
            return 0;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
            pin.shiftToolbarShortcutCandidate = false;
            showContextMenu(pin);
            return 0;
        case WM_MOUSEWHEEL:
            pin.shiftToolbarShortcutCandidate = false;
            scale(pin, GET_WHEEL_DELTA_WPARAM(wParam) > 0 ? 1.08 : 0.92);
            return 0;
        case WM_SYSKEYDOWN:
        case WM_KEYDOWN: {
            const auto control = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
            const auto shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
            const auto alt = (GetKeyState(VK_MENU) & 0x8000) != 0;
            if (wParam != VK_SHIFT || control || alt) {
                pin.shiftToolbarShortcutCandidate = false;
            }
            if (control && !shift && !alt && wParam == 'C') perform(pin, commandCopy);
            else if (control && !shift && !alt && wParam == 'S') perform(pin, commandSave);
            else if (control && !shift && !alt && wParam == 'R') perform(pin, commandReset);
            else if (control && !shift && !alt && wParam == 'T') perform(pin, commandAlwaysOnTop);
            else if (control && !shift && !alt && wParam == 'W') perform(pin, commandClose);
            else if (control && shift && !alt && wParam == 'W') perform(pin, commandCloseAll);
            else if (!control && !shift && wParam == VK_ESCAPE) {
                pin.hiddenOrder = nextHiddenOrder++;
                ShowWindow(pin.window, SW_HIDE);
            }
            else if (!control && !alt && wParam == VK_SHIFT
                && !pin.dragging) {
                pin.shiftToolbarShortcutCandidate = true;
            }
            else if (!control && !shift
                && (wParam == VK_DELETE || wParam == VK_BACK)) {
                perform(pin, commandClose);
            } else {
                break;
            }
            return 0;
        }
        case WM_SYSKEYUP:
        case WM_KEYUP:
            if (wParam == VK_SHIFT && pin.shiftToolbarShortcutCandidate
                && (GetKeyState(VK_CONTROL) & 0x8000) == 0
                && (GetKeyState(VK_MENU) & 0x8000) == 0) {
                pin.shiftToolbarShortcutCandidate = false;
                perform(pin, commandToolbar);
                return 0;
            }
            pin.shiftToolbarShortcutCandidate = false;
            break;
        case WM_NCDESTROY:
            {
            const auto window = pin.window;
            SetWindowLongPtrW(window, GWLP_USERDATA, 0);
            pin.window = nullptr;
            return DefWindowProcW(window, message, wParam, lParam);
            }
        default:
            break;
        }
        return DefWindowProcW(pin.window, message, wParam, lParam);
    }
};

PinnedImageHost::PinnedImageHost(HINSTANCE instance, HWND dialogOwner)
    : impl_(std::make_unique<Impl>(instance, dialogOwner))
{
}

PinnedImageHost::~PinnedImageHost() = default;

bool PinnedImageHost::pin(PixelBuffer pixels, PixelRect sourceRect) noexcept
{
    return impl_ != nullptr && impl_->add(std::move(pixels), sourceRect);
}

std::size_t PinnedImageHost::count() const noexcept
{
    if (impl_ == nullptr) return 0U;
    return static_cast<std::size_t>(std::count_if(
        impl_->pins.begin(), impl_->pins.end(),
        [](const auto& pin) { return pin->window != nullptr; }));
}

bool PinnedImageHost::restoreMostRecentlyHidden() noexcept
{
    return impl_ != nullptr && impl_->restoreMostRecentlyHidden();
}

} // namespace xxsnap::win
