#include "app/ShortcutFeedback.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <utility>

namespace xxsnap::win {
namespace {

constexpr wchar_t feedbackWindowClass[] = L"XxSnap.ShortcutFeedback.v1";
constexpr UINT_PTR holdTimer = 1;
constexpr UINT_PTR fadeTimer = 2;
constexpr UINT fadeTickMilliseconds = 50;
constexpr BYTE maximumAlpha = 240;
constexpr int cornerRadius = 17;
constexpr int horizontalTextInset = 22;
constexpr int shortcutFontSize = 26;

UINT normalizedModifiers(UINT modifiers) noexcept
{
    return modifiers & (MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_WIN);
}

bool isModifierKey(UINT virtualKey) noexcept
{
    switch (virtualKey) {
    case VK_SHIFT:
    case VK_LSHIFT:
    case VK_RSHIFT:
    case VK_CONTROL:
    case VK_LCONTROL:
    case VK_RCONTROL:
    case VK_MENU:
    case VK_LMENU:
    case VK_RMENU:
    case VK_LWIN:
    case VK_RWIN:
        return true;
    default:
        return false;
    }
}

UINT modifierForKey(UINT virtualKey) noexcept
{
    switch (virtualKey) {
    case VK_SHIFT:
    case VK_LSHIFT:
    case VK_RSHIFT: return MOD_SHIFT;
    case VK_CONTROL:
    case VK_LCONTROL:
    case VK_RCONTROL: return MOD_CONTROL;
    case VK_MENU:
    case VK_LMENU:
    case VK_RMENU: return MOD_ALT;
    case VK_LWIN:
    case VK_RWIN: return MOD_WIN;
    default: return 0U;
    }
}

std::wstring virtualKeyDisplayText(UINT virtualKey)
{
    if ((virtualKey >= '0' && virtualKey <= '9')
        || (virtualKey >= 'A' && virtualKey <= 'Z')) {
        return std::wstring(1, static_cast<wchar_t>(virtualKey));
    }
    if (virtualKey >= VK_F1 && virtualKey <= VK_F24) {
        return L"F" + std::to_wstring(virtualKey - VK_F1 + 1U);
    }
    switch (virtualKey) {
    case VK_ESCAPE: return L"Esc";
    case VK_RETURN: return L"Enter";
    case VK_SPACE: return L"Space";
    case VK_TAB: return L"Tab";
    case VK_BACK: return L"Backspace";
    case VK_DELETE: return L"Delete";
    case VK_INSERT: return L"Insert";
    case VK_HOME: return L"Home";
    case VK_END: return L"End";
    case VK_PRIOR: return L"Page Up";
    case VK_NEXT: return L"Page Down";
    case VK_LEFT: return L"Left";
    case VK_RIGHT: return L"Right";
    case VK_UP: return L"Up";
    case VK_DOWN: return L"Down";
    case VK_OEM_3: return L"`";
    case VK_OEM_MINUS: return L"-";
    case VK_OEM_PLUS: return L"=";
    case VK_OEM_4: return L"[";
    case VK_OEM_6: return L"]";
    case VK_OEM_5: return L"\\";
    case VK_OEM_1: return L";";
    case VK_OEM_7: return L"'";
    case VK_OEM_COMMA: return L",";
    case VK_OEM_PERIOD: return L".";
    case VK_OEM_2: return L"/";
    default: break;
    }

    wchar_t name[64]{};
    const auto scan = MapVirtualKeyW(virtualKey, MAPVK_VK_TO_VSC);
    LONG parameter = static_cast<LONG>(scan << 16U);
    if (virtualKey == VK_LEFT || virtualKey == VK_RIGHT
        || virtualKey == VK_UP || virtualKey == VK_DOWN
        || virtualKey == VK_INSERT || virtualKey == VK_DELETE
        || virtualKey == VK_HOME || virtualKey == VK_END
        || virtualKey == VK_PRIOR || virtualKey == VK_NEXT) {
        parameter |= 1L << 24;
    }
    if (GetKeyNameTextW(
            parameter, name, static_cast<int>(std::size(name))) > 0) {
        return name;
    }
    return L"VK " + std::to_wstring(virtualKey);
}

int monitorDpi(HMONITOR monitor) noexcept
{
    MONITORINFOEXW monitorInfo{};
    monitorInfo.cbSize = sizeof(monitorInfo);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &monitorInfo)) {
        const auto monitorDc = CreateDCW(
            L"DISPLAY", monitorInfo.szDevice, nullptr, nullptr);
        if (monitorDc != nullptr) {
            const auto value = GetDeviceCaps(monitorDc, LOGPIXELSX);
            DeleteDC(monitorDc);
            if (value > 0) return value;
        }
    }
    const auto dc = GetDC(nullptr);
    if (dc == nullptr) return 96;
    const auto value = GetDeviceCaps(dc, LOGPIXELSX);
    ReleaseDC(nullptr, dc);
    return value > 0 ? value : 96;
}

int scaled(int value, int dpi) noexcept
{
    return MulDiv(value, dpi, 96);
}

} // namespace

std::wstring shortcutDisplayText(UINT modifiers, UINT virtualKey)
{
    std::wstring result;
    const auto append = [&result](const wchar_t* text) {
        if (!result.empty()) result += L'+';
        result += text;
    };
    modifiers = normalizedModifiers(modifiers);
    if ((modifiers & MOD_CONTROL) != 0U) append(L"Ctrl");
    if ((modifiers & MOD_ALT) != 0U) append(L"Alt");
    if ((modifiers & MOD_SHIFT) != 0U) append(L"Shift");
    if ((modifiers & MOD_WIN) != 0U) append(L"Win");
    const auto key = virtualKeyDisplayText(virtualKey);
    append(key.c_str());
    return result;
}

bool isDisplayableSystemShortcut(UINT modifiers, UINT virtualKey) noexcept
{
    if (isModifierKey(virtualKey)) return false;
    if (normalizedModifiers(modifiers) != 0U) return true;
    return virtualKey == VK_ESCAPE
        || (virtualKey >= VK_F1 && virtualKey <= VK_F24);
}

bool matchesHotKeyBinding(
    HotKeyBinding binding, UINT modifiers, UINT virtualKey) noexcept
{
    return normalizedModifiers(binding.modifiers)
            == normalizedModifiers(modifiers)
        && binding.virtualKey == virtualKey;
}

struct ShortcutFeedbackController::Impl final {
    HINSTANCE instance = nullptr;
    HWND owner = nullptr;
    HWND window = nullptr;
    const PreferencesSettingsStore& settingsStore;
    OwnShortcutPredicate isOwnShortcut;
    HHOOK keyboardHook = nullptr;
    std::array<bool, 256> pressedKeys{};
    UINT pressedModifiers = 0U;
    std::wstring text;
    int width = shortcutFeedbackMinimumBodyWidth
        + shortcutFeedbackTriangleWidth;
    int height = shortcutFeedbackHeight;
    int fadeStep = 0;

    static Impl* hookTarget;

    Impl(HINSTANCE module, HWND sourceOwner,
        const PreferencesSettingsStore& store,
        OwnShortcutPredicate predicate) noexcept
        : instance(module != nullptr ? module : GetModuleHandleW(nullptr))
        , owner(sourceOwner)
        , settingsStore(store)
        , isOwnShortcut(std::move(predicate))
    {
        if ((GetKeyState(VK_CONTROL) & 0x8000) != 0) {
            pressedModifiers |= MOD_CONTROL;
        }
        if ((GetKeyState(VK_MENU) & 0x8000) != 0) {
            pressedModifiers |= MOD_ALT;
        }
        if ((GetKeyState(VK_SHIFT) & 0x8000) != 0) {
            pressedModifiers |= MOD_SHIFT;
        }
        if ((GetKeyState(VK_LWIN) & 0x8000) != 0
            || (GetKeyState(VK_RWIN) & 0x8000) != 0) {
            pressedModifiers |= MOD_WIN;
        }
    }

    ~Impl()
    {
        if (keyboardHook != nullptr) {
            UnhookWindowsHookEx(keyboardHook);
            keyboardHook = nullptr;
        }
        if (hookTarget == this) hookTarget = nullptr;
        close();
        UnregisterClassW(feedbackWindowClass, instance);
    }

    static LRESULT CALLBACK windowProcedure(
        HWND target, UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        auto* self = reinterpret_cast<Impl*>(
            GetWindowLongPtrW(target, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lParam);
            self = static_cast<Impl*>(create->lpCreateParams);
            self->window = target;
            SetWindowLongPtrW(
                target, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
        return self != nullptr
            ? self->handle(message, wParam, lParam)
            : DefWindowProcW(target, message, wParam, lParam);
    }

    static LRESULT CALLBACK keyboardProcedure(
        int code, WPARAM wParam, LPARAM lParam) noexcept
    {
        if (code == HC_ACTION && hookTarget != nullptr) {
            const auto* data = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
            hookTarget->handleKeyboardEvent(wParam, data->vkCode);
        }
        return CallNextHookEx(nullptr, code, wParam, lParam);
    }

    bool initialize() noexcept
    {
        if (!ensureWindow()) return false;
        hookTarget = this;
        keyboardHook = SetWindowsHookExW(
            WH_KEYBOARD_LL, keyboardProcedure, instance, 0);
        if (keyboardHook == nullptr) {
            hookTarget = nullptr;
        }
        return true;
    }

    bool ensureWindow() noexcept
    {
        if (window != nullptr) return true;
        WNDCLASSEXW value{};
        value.cbSize = sizeof(value);
        value.lpfnWndProc = windowProcedure;
        value.hInstance = instance;
        value.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
        value.lpszClassName = feedbackWindowClass;
        if (RegisterClassExW(&value) == 0
            && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            return false;
        }
        window = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
                | WS_EX_TRANSPARENT | WS_EX_LAYERED,
            feedbackWindowClass, L"", WS_POPUP,
            0, 0, width, height, owner, nullptr, instance, this);
        return window != nullptr;
    }

    void handleKeyboardEvent(WPARAM message, UINT virtualKey) noexcept
    {
        if (virtualKey >= pressedKeys.size()) return;
        const bool isDown = message == WM_KEYDOWN || message == WM_SYSKEYDOWN;
        const bool isUp = message == WM_KEYUP || message == WM_SYSKEYUP;
        if (!isDown && !isUp) return;

        const auto modifier = modifierForKey(virtualKey);
        if (isUp) {
            pressedKeys[virtualKey] = false;
            if (modifier != 0U) pressedModifiers &= ~modifier;
            return;
        }

        if (pressedKeys[virtualKey]) return;
        pressedKeys[virtualKey] = true;
        if (modifier != 0U) {
            pressedModifiers |= modifier;
            return;
        }
        if (!settingsStore.load().showsSystemShortcutFeedback
            || !isDisplayableSystemShortcut(
                pressedModifiers, virtualKey)
            || (isOwnShortcut
                && isOwnShortcut(pressedModifiers, virtualKey))) {
            return;
        }
        show(pressedModifiers, virtualKey);
    }

    void show(UINT modifiers, UINT virtualKey) noexcept
    {
        if (!ensureWindow()) return;
        text = shortcutDisplayText(modifiers, virtualKey);
        POINT pointer{};
        GetCursorPos(&pointer);
        const auto monitor = MonitorFromPoint(
            pointer, MONITOR_DEFAULTTONEAREST);
        const auto dpi = monitorDpi(monitor);
        height = scaled(shortcutFeedbackHeight, dpi);
        const auto font = CreateFontW(
            -scaled(shortcutFontSize, dpi), 0, 0, 0, FW_SEMIBOLD,
            FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");
        const auto dc = GetDC(window);
        SIZE textSize{};
        HGDIOBJ previous = nullptr;
        if (dc != nullptr && font != nullptr) {
            previous = SelectObject(dc, font);
            GetTextExtentPoint32W(
                dc, text.c_str(), static_cast<int>(text.size()), &textSize);
            SelectObject(dc, previous);
        }
        if (dc != nullptr) ReleaseDC(window, dc);
        if (font != nullptr) DeleteObject(font);
        const auto bodyWidth = std::max(
            scaled(shortcutFeedbackMinimumBodyWidth, dpi),
            static_cast<int>(textSize.cx)
                + scaled(horizontalTextInset * 2, dpi));
        width = bodyWidth + scaled(shortcutFeedbackTriangleWidth, dpi);

        MONITORINFO info{};
        info.cbSize = sizeof(info);
        RECT work{0, 0, GetSystemMetrics(SM_CXSCREEN),
            GetSystemMetrics(SM_CYSCREEN)};
        if (monitor != nullptr && GetMonitorInfoW(monitor, &info)) {
            work = info.rcWork;
        }
        const auto inset = scaled(shortcutFeedbackScreenInset, dpi);
        const auto x = work.right - inset - width;
        const auto y = work.bottom - inset - height;

        KillTimer(window, holdTimer);
        KillTimer(window, fadeTimer);
        fadeStep = 0;
        SetLayeredWindowAttributes(window, 0, maximumAlpha, LWA_ALPHA);
        applyWindowRegion(dpi);
        SetWindowPos(window, HWND_TOPMOST, x, y, width, height,
            SWP_NOACTIVATE | SWP_SHOWWINDOW);
        InvalidateRect(window, nullptr, FALSE);
        UpdateWindow(window);
        SetTimer(window, holdTimer, shortcutFeedbackHoldMilliseconds, nullptr);
    }

    void applyWindowRegion(int dpi) noexcept
    {
        const auto triangle = scaled(shortcutFeedbackTriangleWidth, dpi);
        const auto bodyWidth = width - triangle;
        const auto radius = scaled(cornerRadius, dpi);
        const auto body = CreateRoundRectRgn(
            0, 0, bodyWidth + 1, height + 1, radius * 2, radius * 2);
        const auto halfTriangle = scaled(10, dpi);
        const auto center = height / 2;
        POINT points[3]{
            {bodyWidth - 1, center - halfTriangle},
            {width, center},
            {bodyWidth - 1, center + halfTriangle},
        };
        const auto tip = CreatePolygonRgn(points, 3, WINDING);
        if (body != nullptr && tip != nullptr) {
            CombineRgn(body, body, tip, RGN_OR);
        }
        if (tip != nullptr) DeleteObject(tip);
        if (body != nullptr && SetWindowRgn(window, body, FALSE) == 0) {
            DeleteObject(body);
        }
    }

    void paint() noexcept
    {
        PAINTSTRUCT paint{};
        const auto dc = BeginPaint(window, &paint);
        RECT client{};
        GetClientRect(window, &client);
        const auto background = CreateSolidBrush(RGB(14, 14, 14));
        FillRect(dc, &client, background);
        DeleteObject(background);

        const auto monitor = MonitorFromWindow(
            window, MONITOR_DEFAULTTONEAREST);
        const auto dpi = monitorDpi(monitor);
        const auto triangle = scaled(shortcutFeedbackTriangleWidth, dpi);
        RECT body{0, 0, client.right - triangle, client.bottom};
        const auto font = CreateFontW(
            -scaled(shortcutFontSize, dpi), 0, 0, 0, FW_SEMIBOLD,
            FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");
        const auto previous = font != nullptr ? SelectObject(dc, font) : nullptr;
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, RGB(255, 255, 255));
        DrawTextW(dc, text.c_str(), static_cast<int>(text.size()), &body,
            DT_CENTER | DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
        if (previous != nullptr) SelectObject(dc, previous);
        if (font != nullptr) DeleteObject(font);
        EndPaint(window, &paint);
    }

    void close() noexcept
    {
        if (window == nullptr) return;
        KillTimer(window, holdTimer);
        KillTimer(window, fadeTimer);
        const auto stale = window;
        window = nullptr;
        DestroyWindow(stale);
    }

    LRESULT handle(UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        switch (message) {
        case WM_PAINT: paint(); return 0;
        case WM_ERASEBKGND: return 1;
        case WM_NCHITTEST: return HTTRANSPARENT;
        case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
        case WM_TIMER:
            if (wParam == holdTimer) {
                KillTimer(window, holdTimer);
                fadeStep = 0;
                SetTimer(window, fadeTimer, fadeTickMilliseconds, nullptr);
                return 0;
            }
            if (wParam == fadeTimer) {
                ++fadeStep;
                const auto stepCount = shortcutFeedbackFadeMilliseconds
                    / static_cast<int>(fadeTickMilliseconds);
                if (fadeStep >= stepCount) {
                    KillTimer(window, fadeTimer);
                    ShowWindow(window, SW_HIDE);
                } else {
                    const auto alpha = static_cast<BYTE>(
                        maximumAlpha * (stepCount - fadeStep) / stepCount);
                    SetLayeredWindowAttributes(window, 0, alpha, LWA_ALPHA);
                }
                return 0;
            }
            return 0;
        case WM_NCDESTROY:
            window = nullptr;
            return 0;
        default:
            return DefWindowProcW(window, message, wParam, lParam);
        }
    }
};

ShortcutFeedbackController::Impl* ShortcutFeedbackController::Impl::hookTarget
    = nullptr;

std::unique_ptr<ShortcutFeedbackController>
ShortcutFeedbackController::create(
    HINSTANCE instance,
    HWND owner,
    const PreferencesSettingsStore& settingsStore,
    OwnShortcutPredicate isOwnShortcut)
{
    auto impl = std::make_unique<Impl>(
        instance, owner, settingsStore, std::move(isOwnShortcut));
    if (!impl->initialize()) return nullptr;
    return std::unique_ptr<ShortcutFeedbackController>(
        new ShortcutFeedbackController(std::move(impl)));
}

ShortcutFeedbackController::ShortcutFeedbackController(
    std::unique_ptr<Impl> impl) noexcept
    : impl_(std::move(impl))
{
}

ShortcutFeedbackController::~ShortcutFeedbackController() = default;

void ShortcutFeedbackController::showAppShortcut(
    HotKeyBinding binding) noexcept
{
    if (impl_->settingsStore.load().showsShortcutFeedback) {
        impl_->show(binding.modifiers, binding.virtualKey);
    }
}

void ShortcutFeedbackController::showForTesting(
    UINT modifiers, UINT virtualKey) noexcept
{
    impl_->show(modifiers, virtualKey);
}

HWND ShortcutFeedbackController::nativeWindow() const noexcept
{
    return impl_->window;
}

} // namespace xxsnap::win
