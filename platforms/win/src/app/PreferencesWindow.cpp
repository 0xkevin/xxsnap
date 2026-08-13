#include "app/PreferencesWindow.h"

#include "app/LaunchAtLogin.h"
#include "resource.h"

#include <shellapi.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cwchar>
#include <string>
#include <utility>
#include <vector>

namespace xxsnap::win {
namespace {

constexpr wchar_t windowClassName[] = L"XxSnap.PreferencesWindow.v1";
constexpr wchar_t windowTitle[] = L"XxSnap 设置";
constexpr COLORREF textColor = RGB(34, 34, 34);
constexpr COLORREF secondaryTextColor = RGB(103, 103, 103);
constexpr COLORREF accentColor = RGB(0, 122, 255);
constexpr COLORREF errorColor = RGB(204, 38, 38);
constexpr COLORREF successColor = RGB(31, 139, 68);

constexpr int navigationFirstId = 1000;
constexpr int launchAtLoginId = 1100;
constexpr int disableOcrSoundId = 1101;
constexpr int disableOcrNotificationId = 1102;
constexpr int showShortcutFeedbackId = 1103;
constexpr int showSystemShortcutFeedbackId = 1104;
constexpr int shortcutFirstId = 1200;
constexpr int resetShortcutsId = 1210;
constexpr int filenameEditId = 1300;
constexpr int checkAtLaunchId = 1400;
constexpr int updateIntervalId = 1401;
constexpr int checkNowId = 1402;
constexpr int contactId = 1500;

constexpr std::array<const wchar_t*, 6> sectionLabels{
    L"通用", L"快捷键", L"保存", L"更新", L"捐赠", L"关于"};
constexpr std::array<const wchar_t*, 6> sectionIcons{
    L"\uE713", L"\uE765", L"\uE74E", L"\uE895", L"\uE8F1", L"\uE946"};

HBITMAP decodeDonationBitmap(HINSTANCE instance, int resourceId) noexcept
{
    using Microsoft::WRL::ComPtr;
    const auto resource = FindResourceW(instance,
        MAKEINTRESOURCEW(resourceId), MAKEINTRESOURCEW(10));
    if (resource == nullptr) return nullptr;
    const auto size = SizeofResource(instance, resource);
    const auto loaded = LoadResource(instance, resource);
    auto* bytes = static_cast<BYTE*>(LockResource(loaded));
    if (bytes == nullptr || size == 0U) return nullptr;
    ComPtr<IWICImagingFactory> factory;
    ComPtr<IWICStream> stream;
    ComPtr<IWICBitmapDecoder> decoder;
    ComPtr<IWICBitmapFrameDecode> frame;
    ComPtr<IWICFormatConverter> converter;
    UINT width = 0;
    UINT height = 0;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
            CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))
        || FAILED(factory->CreateStream(&stream))
        || FAILED(stream->InitializeFromMemory(bytes, size))
        || FAILED(factory->CreateDecoderFromStream(stream.Get(), nullptr,
            WICDecodeMetadataCacheOnLoad, &decoder))
        || FAILED(decoder->GetFrame(0, &frame))
        || FAILED(frame->GetSize(&width, &height))
        || width == 0 || height == 0
        || FAILED(factory->CreateFormatConverter(&converter))
        || FAILED(converter->Initialize(frame.Get(),
            GUID_WICPixelFormat32bppBGR, WICBitmapDitherTypeNone,
            nullptr, 0.0, WICBitmapPaletteTypeCustom))) {
        return nullptr;
    }
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = static_cast<LONG>(width);
    info.bmiHeader.biHeight = -static_cast<LONG>(height);
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void* pixels = nullptr;
    const auto screen = GetDC(nullptr);
    const auto bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS,
        &pixels, nullptr, 0);
    if (screen != nullptr) ReleaseDC(nullptr, screen);
    const auto stride = width * 4U;
    if (bitmap == nullptr || pixels == nullptr
        || FAILED(converter->CopyPixels(nullptr, stride, stride * height,
            static_cast<BYTE*>(pixels)))) {
        DeleteObject(bitmap);
        return nullptr;
    }
    return bitmap;
}

int scaled(int value, UINT dpi) noexcept
{
    return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
}

UINT windowDpi(HWND window) noexcept
{
    const auto dc = GetDC(window);
    if (dc == nullptr) return 96;
    const auto value = GetDeviceCaps(dc, LOGPIXELSX);
    ReleaseDC(window, dc);
    return value > 0 ? static_cast<UINT>(value) : 96;
}

const wchar_t* sectionLabel(PreferencesSection section) noexcept
{
    const auto index = static_cast<std::size_t>(section);
    return index < sectionLabels.size() ? sectionLabels[index] : sectionLabels[0];
}

HotKeyCommand hotKeyCommand(std::size_t index) noexcept
{
    return index < defaultAppHotKeys().size()
        ? defaultAppHotKeys()[index].command
        : HotKeyCommand::regionCapture;
}

bool isModifierKey(UINT virtualKey) noexcept
{
    return virtualKey == VK_CONTROL || virtualKey == VK_LCONTROL
        || virtualKey == VK_RCONTROL || virtualKey == VK_SHIFT
        || virtualKey == VK_LSHIFT || virtualKey == VK_RSHIFT
        || virtualKey == VK_MENU || virtualKey == VK_LMENU
        || virtualKey == VK_RMENU || virtualKey == VK_LWIN
        || virtualKey == VK_RWIN;
}

std::wstring virtualKeyName(UINT virtualKey)
{
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
    if (GetKeyNameTextW(parameter, name,
            static_cast<int>(std::size(name))) > 0) {
        return name;
    }
    if (virtualKey >= 32U && virtualKey < 127U) {
        return std::wstring(1, static_cast<wchar_t>(virtualKey));
    }
    return L"VK " + std::to_wstring(virtualKey);
}

std::wstring formatHotKey(HotKeyBinding binding)
{
    if (!binding.enabled) return L"未设置";
    std::wstring result;
    const auto append = [&result](const wchar_t* value) {
        if (!result.empty()) result += L" + ";
        result += value;
    };
    if ((binding.modifiers & MOD_CONTROL) != 0U) append(L"Ctrl");
    if ((binding.modifiers & MOD_ALT) != 0U) append(L"Alt");
    if ((binding.modifiers & MOD_SHIFT) != 0U) append(L"Shift");
    if ((binding.modifiers & MOD_WIN) != 0U) append(L"Win");
    const auto key = virtualKeyName(binding.virtualKey);
    append(key.c_str());
    return result;
}

std::wstring executableVersion()
{
    const auto path = currentExecutablePath();
    if (path.empty()) return L"0.1.0";
    DWORD ignored = 0;
    const auto size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
    if (size == 0) return L"0.1.0";
    try {
        std::vector<BYTE> data(size);
        if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) {
            return L"0.1.0";
        }
        VS_FIXEDFILEINFO* info = nullptr;
        UINT length = 0;
        if (!VerQueryValueW(data.data(), L"\\",
                reinterpret_cast<void**>(&info), &length)
            || info == nullptr || length < sizeof(VS_FIXEDFILEINFO)) {
            return L"0.1.0";
        }
        return std::to_wstring(HIWORD(info->dwFileVersionMS)) + L"."
            + std::to_wstring(LOWORD(info->dwFileVersionMS)) + L"."
            + std::to_wstring(HIWORD(info->dwFileVersionLS));
    } catch (...) {
        return L"0.1.0";
    }
}

} // namespace

SIZE preferencesWindowClientSize(UINT dpi) noexcept
{
    const auto effective = dpi == 0 ? 96U : dpi;
    return {MulDiv(680, static_cast<int>(effective), 96),
        MulDiv(480, static_cast<int>(effective), 96)};
}

std::wstring filenameTemplateErrorText(
    FilenameTemplateError error, const std::wstring& invalidVariable)
{
    switch (error) {
    case FilenameTemplateError::empty:
        return L"文件名模板不能为空";
    case FilenameTemplateError::pathCharacter:
        return L"文件名模板不能包含 Windows 路径字符";
    case FilenameTemplateError::unknownVariable:
        return L"不支持的变量：" + invalidVariable;
    }
    return L"文件名模板无效";
}

struct PreferencesWindow::Impl final {
    HINSTANCE instance = nullptr;
    HWND owner = nullptr;
    HWND window = nullptr;
    UINT dpi = 96;
    PreferencesSection selected = PreferencesSection::general;
    SystemPreferencesRegistry registry;
    PreferencesSettingsStore store{registry};
    SystemLaunchAtLoginRegistry launchRegistry;
    LaunchAtLoginManager launchManager{launchRegistry};
    PreferencesShortcutCallbacks shortcutCallbacks;
    std::wstring executablePath;
    std::vector<HWND> navigationControls;
    std::vector<HWND> pageControls;
    std::vector<HWND> secondaryControls;
    HWND filenameEdit = nullptr;
    HWND filenamePreview = nullptr;
    HWND filenameError = nullptr;
    HWND updateStatus = nullptr;
    HFONT regularFont = nullptr;
    HFONT boldFont = nullptr;
    HFONT smallFont = nullptr;
    HFONT monoFont = nullptr;
    HFONT iconFont = nullptr;
    HBRUSH backgroundBrush = nullptr;
    HBITMAP alipayBitmap = nullptr;
    HBITMAP wechatPayBitmap = nullptr;
    int recordingShortcutIndex = -1;

    Impl(HINSTANCE module, HWND sourceOwner,
        PreferencesShortcutCallbacks callbacks)
        : instance(module != nullptr ? module : GetModuleHandleW(nullptr))
        , owner(sourceOwner)
        , shortcutCallbacks(std::move(callbacks))
        , executablePath(currentExecutablePath())
    {
    }

    ~Impl()
    {
        if (window != nullptr) DestroyWindow(window);
        deleteResources();
        UnregisterClassW(windowClassName, instance);
    }

    void deleteResources() noexcept
    {
        DeleteObject(regularFont);
        DeleteObject(boldFont);
        DeleteObject(smallFont);
        DeleteObject(monoFont);
        DeleteObject(iconFont);
        DeleteObject(backgroundBrush);
        DeleteObject(alipayBitmap);
        DeleteObject(wechatPayBitmap);
        regularFont = nullptr;
        boldFont = nullptr;
        smallFont = nullptr;
        monoFont = nullptr;
        iconFont = nullptr;
        backgroundBrush = nullptr;
        alipayBitmap = nullptr;
        wechatPayBitmap = nullptr;
    }

    void createResources() noexcept
    {
        deleteResources();
        const auto fontHeight = -scaled(13, dpi);
        regularFont = CreateFontW(fontHeight, 0, 0, 0, FW_NORMAL,
            FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");
        boldFont = CreateFontW(-scaled(14, dpi), 0, 0, 0, FW_SEMIBOLD,
            FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");
        smallFont = CreateFontW(-scaled(12, dpi), 0, 0, 0, FW_NORMAL,
            FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");
        monoFont = CreateFontW(-scaled(13, dpi), 0, 0, 0, FW_NORMAL,
            FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            FIXED_PITCH | FF_MODERN, L"Microsoft YaHei");
        iconFont = CreateFontW(-scaled(21, dpi), 0, 0, 0, FW_NORMAL,
            FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Segoe MDL2 Assets");
        backgroundBrush = CreateSolidBrush(RGB(246, 246, 246));
        alipayBitmap = decodeDonationBitmap(instance, IDR_DONATION_ALIPAY);
        wechatPayBitmap = decodeDonationBitmap(
            instance, IDR_DONATION_WECHATPAY);
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

    bool createWindow() noexcept
    {
        WNDCLASSEXW value{};
        value.cbSize = sizeof(value);
        value.lpfnWndProc = windowProcedure;
        value.hInstance = instance;
        value.hIcon = reinterpret_cast<HICON>(LoadImageW(instance,
            MAKEINTRESOURCEW(IDI_XXSNAP), IMAGE_ICON, 0, 0,
            LR_DEFAULTSIZE | LR_SHARED));
        value.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
        value.lpszClassName = windowClassName;
        if (RegisterClassExW(&value) == 0
            && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            return false;
        }
        dpi = 96;
        auto client = preferencesWindowClientSize(dpi);
        RECT rect{0, 0, client.cx, client.cy};
        constexpr DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU
            | WS_MINIMIZEBOX;
        AdjustWindowRectEx(&rect, style, FALSE, 0);
        window = CreateWindowExW(0, windowClassName, windowTitle, style,
            CW_USEDEFAULT, CW_USEDEFAULT, rect.right - rect.left,
            rect.bottom - rect.top, owner, nullptr, instance, this);
        if (window == nullptr) return false;
        dpi = windowDpi(window);
        createResources();
        createNavigation();
        rebuildPage();
        centerWindow();
        return true;
    }

    void centerWindow() noexcept
    {
        RECT rect{};
        GetWindowRect(window, &rect);
        const auto monitor = MonitorFromWindow(
            owner != nullptr ? owner : window, MONITOR_DEFAULTTONEAREST);
        MONITORINFO info{};
        info.cbSize = sizeof(info);
        if (monitor == nullptr || !GetMonitorInfoW(monitor, &info)) return;
        const auto width = rect.right - rect.left;
        const auto height = rect.bottom - rect.top;
        SetWindowPos(window, nullptr,
            info.rcWork.left + (info.rcWork.right - info.rcWork.left - width) / 2,
            info.rcWork.top + (info.rcWork.bottom - info.rcWork.top - height) / 2,
            0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    }

    HWND addControl(const wchar_t* className, const wchar_t* text,
        DWORD style, DWORD extendedStyle, int x, int y, int width, int height,
        int identifier, HFONT font, bool page = true)
    {
        const auto control = CreateWindowExW(extendedStyle, className,
            text == nullptr ? L"" : text, WS_CHILD | WS_VISIBLE | style,
            scaled(x, dpi), scaled(y, dpi), scaled(width, dpi),
            scaled(height, dpi), window,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(identifier)),
            instance, nullptr);
        if (control != nullptr) {
            SendMessageW(control, WM_SETFONT,
                reinterpret_cast<WPARAM>(font), TRUE);
            if (page) pageControls.push_back(control);
        }
        return control;
    }

    HWND addLabel(const wchar_t* text, int x, int y, int width, int height,
        HFONT font, bool secondary = false, DWORD extraStyle = 0)
    {
        const auto label = addControl(L"STATIC", text,
            SS_LEFT | SS_NOPREFIX | extraStyle, 0,
            x, y, width, height, 0, font);
        if (secondary && label != nullptr) secondaryControls.push_back(label);
        return label;
    }

    void createNavigation()
    {
        for (auto control : navigationControls) DestroyWindow(control);
        navigationControls.clear();
        constexpr int buttonWidth = 90;
        constexpr int startX = (680 - buttonWidth * 6) / 2;
        for (std::size_t index = 0; index < preferencesSections().size(); ++index) {
            const auto control = addControl(L"BUTTON", sectionLabels[index],
                BS_OWNERDRAW | WS_TABSTOP, 0,
                startX + static_cast<int>(index) * buttonWidth,
                6, buttonWidth, 68,
                navigationFirstId + static_cast<int>(index),
                regularFont, false);
            if (control != nullptr) navigationControls.push_back(control);
        }
    }

    void destroyPage() noexcept
    {
        for (auto control : pageControls) DestroyWindow(control);
        pageControls.clear();
        secondaryControls.clear();
        filenameEdit = nullptr;
        filenamePreview = nullptr;
        filenameError = nullptr;
        updateStatus = nullptr;
    }

    void addRowLabels(
        const wchar_t* title, const wchar_t* detail, int row)
    {
        const auto y = 105 + row * 62;
        addLabel(title, 50, y + 10, 430, 22, boldFont);
        if (detail != nullptr && detail[0] != L'\0') {
            addLabel(detail, 50, y + 33, 500, 20, smallFont, true);
        }
    }

    HWND addCheckbox(int identifier, int row, bool checked)
    {
        const auto control = addControl(L"BUTTON", L"",
            BS_AUTOCHECKBOX | WS_TABSTOP, 0,
            594, 105 + row * 62 + 20, 24, 24,
            identifier, regularFont);
        if (control != nullptr) {
            SendMessageW(control, BM_SETCHECK,
                checked ? BST_CHECKED : BST_UNCHECKED, 0);
        }
        return control;
    }

    void makeGeneralPage()
    {
        const auto settings = store.load();
        addRowLabels(L"开机自启动",
            L"登录 Windows 后自动运行 XxSnap", 0);
        addCheckbox(launchAtLoginId, 0,
            launchManager.isEnabled(executablePath));
        addRowLabels(L"禁用识别文字提示音",
            L"识别成功后不播放提示音", 1);
        addCheckbox(disableOcrSoundId, 1,
            settings.disablesTextRecognitionSound);
        addRowLabels(L"禁用识别文字通知",
            L"不显示识别成功提示，识别失败仍会正常提示", 2);
        addCheckbox(disableOcrNotificationId, 2,
            settings.disablesTextRecognitionSuccessNotification);
        addRowLabels(L"显示 XxSnap 快捷键",
            L"按 XxSnap 快捷键时，在当前屏幕右下角显示按键组合", 3);
        addCheckbox(showShortcutFeedbackId, 3,
            settings.showsShortcutFeedback);
        addRowLabels(L"显示其他应用快捷键",
            L"显示包含 Ctrl、Alt 或 Shift 的组合键，不记录普通输入", 4);
        addCheckbox(showSystemShortcutFeedbackId, 4,
            settings.showsSystemShortcutFeedback);
    }

    void makeShortcutsPage()
    {
        constexpr std::array<const wchar_t*, 5> titles{
            L"截图", L"全屏截图", L"识别文字", L"教笔", L"恢复最近隐藏的贴图"};
        constexpr std::array<const wchar_t*, 5> details{
            L"开始一次新的区域截图", L"立即截取整个可见桌面",
            L"框选屏幕区域并识别文字", L"进入全屏教笔标注模式",
            L"截图进行中会暂时停用"};
        auto bindings = defaultAppHotKeys();
        if (shortcutCallbacks.load) bindings = shortcutCallbacks.load();
        for (std::size_t index = 0; index < titles.size(); ++index) {
            addRowLabels(titles[index], details[index], static_cast<int>(index));
            const auto shortcut = formatHotKey(bindings[index]);
            addControl(L"BUTTON", shortcut.c_str(),
                BS_PUSHBUTTON | WS_TABSTOP, 0, 500,
                105 + static_cast<int>(index) * 62 + 16, 118, 30,
                shortcutFirstId + static_cast<int>(index), regularFont);
        }
        addControl(L"BUTTON", L"恢复默认快捷键",
            BS_PUSHBUTTON | WS_TABSTOP, 0, 500, 424, 118, 30,
            resetShortcutsId, regularFont);
    }

    void makeSavePage()
    {
        const auto settings = store.load();
        addLabel(L"文件名模板", 50, 118, 560, 24, boldFont);
        addLabel(L"PNG 扩展名会自动补充", 50, 143, 560, 20,
            smallFont, true);
        filenameEdit = addControl(L"EDIT", settings.filenameTemplate.c_str(),
            ES_AUTOHSCROLL | WS_TABSTOP, WS_EX_CLIENTEDGE,
            50, 174, 568, 32, filenameEditId, monoFont);
        addLabel(L"预览", 64, 236, 540, 20, smallFont, true);
        filenamePreview = addLabel(L"", 64, 266, 540, 38, monoFont);
        filenameError = addLabel(L"", 64, 309, 540, 36, smallFont);
        addLabel(L"可用变量：{yyyyMMdd}、{HHmmss}",
            64, 359, 540, 24, smallFont, true);
        updateFilenamePreview();
    }

    void makeUpdatePage()
    {
        const auto settings = store.load();
        addRowLabels(L"启动时检查更新", L"", 0);
        addCheckbox(checkAtLaunchId, 0, settings.checksForUpdatesAtLaunch);
        addRowLabels(L"自动检查间隔", L"", 1);
        const auto combo = addControl(L"COMBOBOX", L"",
            CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL, 0,
            488, 105 + 62 + 15, 130, 180,
            updateIntervalId, regularFont);
        if (combo != nullptr) {
            for (const auto interval : allowedUpdateIntervals) {
                const auto label = std::to_wstring(interval) + L" 小时";
                const auto index = SendMessageW(
                    combo, CB_ADDSTRING, 0,
                    reinterpret_cast<LPARAM>(label.c_str()));
                SendMessageW(combo, CB_SETITEMDATA,
                    static_cast<WPARAM>(index), interval);
                if (interval == settings.updateCheckIntervalHours) {
                    SendMessageW(combo, CB_SETCURSEL,
                        static_cast<WPARAM>(index), 0);
                }
            }
        }
        updateStatus = addLabel(L"", 50, 261, 330, 28, regularFont);
        addControl(L"BUTTON", L"立即检查", BS_PUSHBUTTON | WS_TABSTOP,
            0, 500, 252, 118, 32, checkNowId, regularFont);
    }

    void makeDonationPage()
    {
        addLabel(L"如果这个软件对您有所帮助，欢迎通过捐赠支持我们持续维护与改进",
            70, 407, 540, 40, regularFont, false, SS_CENTER);
    }

    void makeAboutPage()
    {
        const auto icon = addControl(L"STATIC", L"", SS_ICON | SS_CENTERIMAGE,
            0, 296, 114, 88, 88, 0, regularFont);
        if (icon != nullptr) {
            const auto value = LoadImageW(instance,
                MAKEINTRESOURCEW(IDI_XXSNAP), IMAGE_ICON,
                scaled(72, dpi), scaled(72, dpi), LR_DEFAULTCOLOR);
            SendMessageW(icon, STM_SETICON, reinterpret_cast<WPARAM>(value), 0);
        }
        addLabel(L"XxSnap", 0, 213, 680, 34,
            boldFont, false, SS_CENTER);
        const auto version = L"版本 " + executableVersion();
        addLabel(version.c_str(), 0, 253, 680, 24,
            regularFont, true, SS_CENTER);
        addLabel(L"版权所有 © 2026 xxsofts.com", 0, 298, 680, 24,
            smallFont, true, SS_CENTER);
        addControl(L"BUTTON", L"问题反馈或技术支持：zfc.2012@gmail.com",
            BS_FLAT | BS_PUSHBUTTON | WS_TABSTOP, 0,
            185, 337, 310, 30, contactId, smallFont);
    }

    void rebuildPage()
    {
        destroyPage();
        switch (selected) {
        case PreferencesSection::general: makeGeneralPage(); break;
        case PreferencesSection::shortcuts: makeShortcutsPage(); break;
        case PreferencesSection::save: makeSavePage(); break;
        case PreferencesSection::update: makeUpdatePage(); break;
        case PreferencesSection::donation: makeDonationPage(); break;
        case PreferencesSection::about: makeAboutPage(); break;
        }
        InvalidateRect(window, nullptr, TRUE);
    }

    void setSelected(PreferencesSection section)
    {
        if (static_cast<std::size_t>(section) >= preferencesSections().size()) {
            section = PreferencesSection::general;
        }
        if (selected != section || pageControls.empty()) {
            selected = section;
            rebuildPage();
        } else {
            InvalidateRect(window, nullptr, TRUE);
        }
    }

    bool checked(int identifier) const noexcept
    {
        const auto control = GetDlgItem(window, identifier);
        return control != nullptr
            && SendMessageW(control, BM_GETCHECK, 0, 0) == BST_CHECKED;
    }

    void reportSaveFailure()
    {
        MessageBoxW(window, L"设置保存失败。", L"XxSnap 错误",
            MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
    }

    void saveGeneralSetting(int identifier)
    {
        auto settings = store.load();
        if (identifier == disableOcrSoundId) {
            settings.disablesTextRecognitionSound = checked(identifier);
        } else if (identifier == disableOcrNotificationId) {
            settings.disablesTextRecognitionSuccessNotification = checked(identifier);
        } else if (identifier == showShortcutFeedbackId) {
            settings.showsShortcutFeedback = checked(identifier);
        } else if (identifier == showSystemShortcutFeedbackId) {
            settings.showsSystemShortcutFeedback = checked(identifier);
        }
        if (!store.save(settings)) {
            reportSaveFailure();
            rebuildPage();
        }
    }

    std::wstring filenameText() const
    {
        if (filenameEdit == nullptr) return {};
        const auto length = GetWindowTextLengthW(filenameEdit);
        if (length <= 0) return {};
        std::wstring value(static_cast<std::size_t>(length) + 1U, L'\0');
        GetWindowTextW(filenameEdit, value.data(), length + 1);
        value.resize(static_cast<std::size_t>(length));
        return value;
    }

    void updateFilenamePreview()
    {
        if (filenamePreview == nullptr || filenameError == nullptr) return;
        SYSTEMTIME time{};
        GetLocalTime(&time);
        const auto result = renderCaptureFilename(filenameText(), time);
        if (result.error.has_value()) {
            SetWindowTextW(filenamePreview, L"");
            const auto text = filenameTemplateErrorText(
                *result.error, result.invalidVariable);
            SetWindowTextW(filenameError, text.c_str());
        } else {
            SetWindowTextW(filenamePreview, result.filename.c_str());
            SetWindowTextW(filenameError, L"");
        }
        InvalidateRect(filenameError, nullptr, TRUE);
    }

    void commitFilename()
    {
        if (filenameEdit == nullptr) return;
        SYSTEMTIME time{};
        GetLocalTime(&time);
        const auto value = filenameText();
        const auto rendered = renderCaptureFilename(value, time);
        if (rendered.error.has_value()) return;
        auto settings = store.load();
        if (settings.filenameTemplate == value) return;
        settings.filenameTemplate = value;
        if (!store.save(settings)) reportSaveFailure();
    }

    void drawNavigationButton(const DRAWITEMSTRUCT& item) noexcept
    {
        const auto index = item.CtlID - navigationFirstId;
        if (index < 0 || static_cast<std::size_t>(index) >= sectionLabels.size()) {
            return;
        }
        const auto active = static_cast<std::size_t>(selected)
            == static_cast<std::size_t>(index);
        const auto brush = CreateSolidBrush(active
            ? RGB(226, 239, 255) : RGB(246, 246, 246));
        FillRect(item.hDC, &item.rcItem, brush);
        DeleteObject(brush);
        SetBkMode(item.hDC, TRANSPARENT);
        SetTextColor(item.hDC, active ? accentColor : textColor);
        auto iconRect = item.rcItem;
        iconRect.bottom = iconRect.top + scaled(39, dpi);
        SelectObject(item.hDC, iconFont);
        DrawTextW(item.hDC, sectionIcons[static_cast<std::size_t>(index)], -1,
            &iconRect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        auto labelRect = item.rcItem;
        labelRect.top += scaled(40, dpi);
        SelectObject(item.hDC, smallFont);
        DrawTextW(item.hDC, sectionLabels[static_cast<std::size_t>(index)], -1,
            &labelRect, DT_CENTER | DT_TOP | DT_SINGLELINE);
        if ((item.itemState & ODS_FOCUS) != 0U) {
            auto focus = item.rcItem;
            InflateRect(&focus, -scaled(5, dpi), -scaled(4, dpi));
            DrawFocusRect(item.hDC, &focus);
        }
    }

    void paint() noexcept
    {
        PAINTSTRUCT paint{};
        const auto dc = BeginPaint(window, &paint);
        RECT client{};
        GetClientRect(window, &client);
        FillRect(dc, &client, backgroundBrush);
        const auto separator = CreatePen(PS_SOLID, 1, RGB(218, 218, 218));
        const auto previousPen = SelectObject(dc, separator);
        MoveToEx(dc, 0, scaled(78, dpi), nullptr);
        LineTo(dc, client.right, scaled(78, dpi));
        SelectObject(dc, previousPen);
        DeleteObject(separator);
        if (selected == PreferencesSection::general
            || selected == PreferencesSection::shortcuts
            || selected == PreferencesSection::update) {
            const auto panelBrush = CreateSolidBrush(RGB(255, 255, 255));
            const auto panelPen = CreatePen(PS_SOLID, 1, RGB(215, 215, 215));
            const auto oldBrush = SelectObject(dc, panelBrush);
            const auto oldPen = SelectObject(dc, panelPen);
            const auto rows = selected == PreferencesSection::update ? 2 : 5;
            RoundRect(dc, scaled(34, dpi), scaled(104, dpi),
                scaled(646, dpi), scaled(105 + rows * 62, dpi),
                scaled(10, dpi), scaled(10, dpi));
            for (int row = 1; row < rows; ++row) {
                MoveToEx(dc, scaled(34, dpi), scaled(105 + row * 62, dpi), nullptr);
                LineTo(dc, scaled(646, dpi), scaled(105 + row * 62, dpi));
            }
            SelectObject(dc, oldBrush);
            SelectObject(dc, oldPen);
            DeleteObject(panelBrush);
            DeleteObject(panelPen);
        } else if (selected == PreferencesSection::save) {
            const auto panelBrush = CreateSolidBrush(RGB(255, 255, 255));
            RECT panel{scaled(50, dpi), scaled(224, dpi),
                scaled(630, dpi), scaled(394, dpi)};
            FillRect(dc, &panel, panelBrush);
            DeleteObject(panelBrush);
        } else if (selected == PreferencesSection::donation) {
            const auto drawBitmap = [this, dc](HBITMAP bitmap, int x) {
                if (bitmap == nullptr) return;
                BITMAP sourceInfo{};
                GetObjectW(bitmap, sizeof(sourceInfo), &sourceInfo);
                const auto source = CreateCompatibleDC(dc);
                const auto old = SelectObject(source, bitmap);
                SetStretchBltMode(dc, HALFTONE);
                StretchBlt(dc, scaled(x, dpi), scaled(105, dpi),
                    scaled(194, dpi), scaled(282, dpi), source,
                    0, 0, sourceInfo.bmWidth, sourceInfo.bmHeight, SRCCOPY);
                SelectObject(source, old);
                DeleteDC(source);
            };
            drawBitmap(alipayBitmap, 132);
            drawBitmap(wechatPayBitmap, 354);
        }
        EndPaint(window, &paint);
    }

    void handleCommand(int identifier, int notification)
    {
        if (identifier >= navigationFirstId
            && identifier < navigationFirstId
                    + static_cast<int>(preferencesSections().size())) {
            if (filenameEdit != nullptr) commitFilename();
            setSelected(preferencesSections()[
                static_cast<std::size_t>(identifier - navigationFirstId)]);
            return;
        }
        if (identifier == launchAtLoginId && notification == BN_CLICKED) {
            if (!launchManager.setEnabled(checked(identifier), executablePath)) {
                reportSaveFailure();
                rebuildPage();
            }
        } else if ((identifier == disableOcrSoundId
                       || identifier == disableOcrNotificationId
                       || identifier == showShortcutFeedbackId
                       || identifier == showSystemShortcutFeedbackId)
            && notification == BN_CLICKED) {
            saveGeneralSetting(identifier);
        } else if (identifier == filenameEditId && notification == EN_CHANGE) {
            updateFilenamePreview();
        } else if (identifier == filenameEditId
            && notification == EN_KILLFOCUS) {
            commitFilename();
        } else if (identifier == checkAtLaunchId
            && notification == BN_CLICKED) {
            auto settings = store.load();
            settings.checksForUpdatesAtLaunch = checked(identifier);
            if (!store.save(settings)) {
                reportSaveFailure();
                rebuildPage();
            }
        } else if (identifier == updateIntervalId
            && notification == CBN_SELCHANGE) {
            const auto combo = GetDlgItem(window, updateIntervalId);
            const auto index = SendMessageW(combo, CB_GETCURSEL, 0, 0);
            const auto interval = SendMessageW(
                combo, CB_GETITEMDATA, static_cast<WPARAM>(index), 0);
            auto settings = store.load();
            settings.updateCheckIntervalHours = static_cast<int>(interval);
            if (!store.save(settings)) reportSaveFailure();
        } else if (identifier == checkNowId && notification == BN_CLICKED) {
            if (updateStatus != nullptr) {
                SetWindowTextW(updateStatus, L"已是最新版本");
                InvalidateRect(updateStatus, nullptr, TRUE);
            }
        } else if (identifier == resetShortcutsId
            && notification == BN_CLICKED) {
            if (!shortcutCallbacks.reset || !shortcutCallbacks.reset()) {
                MessageBoxW(window, L"无法恢复默认快捷键。",
                    L"XxSnap 错误", MB_OK | MB_ICONERROR);
            }
            recordingShortcutIndex = -1;
            rebuildPage();
        } else if (identifier >= shortcutFirstId
            && identifier < shortcutFirstId + 5
            && notification == BN_CLICKED) {
            recordingShortcutIndex = identifier - shortcutFirstId;
            if (const auto button = GetDlgItem(window, identifier)) {
                SetWindowTextW(button, L"按键 / Delete 清除");
            }
            SetFocus(window);
        } else if (identifier == contactId && notification == BN_CLICKED) {
            ShellExecuteW(window, L"open", L"mailto:zfc.2012@gmail.com",
                nullptr, nullptr, SW_SHOWNORMAL);
        }
    }

    void recordShortcut(UINT virtualKey)
    {
        if (recordingShortcutIndex < 0 || recordingShortcutIndex >= 5) return;
        if (virtualKey == VK_ESCAPE) {
            recordingShortcutIndex = -1;
            rebuildPage();
            return;
        }
        if (virtualKey == VK_DELETE || virtualKey == VK_BACK) {
            const auto disabled = disabledHotKey(hotKeyCommand(
                static_cast<std::size_t>(recordingShortcutIndex)));
            if (!shortcutCallbacks.apply
                || !shortcutCallbacks.apply(disabled)) {
                MessageBoxW(window, L"无法停用该快捷键。",
                    L"录制快捷键", MB_OK | MB_ICONWARNING);
                return;
            }
            recordingShortcutIndex = -1;
            rebuildPage();
            return;
        }
        if (isModifierKey(virtualKey)) return;
        UINT modifiers = 0U;
        if ((GetKeyState(VK_CONTROL) & 0x8000) != 0) modifiers |= MOD_CONTROL;
        if ((GetKeyState(VK_MENU) & 0x8000) != 0) modifiers |= MOD_ALT;
        if ((GetKeyState(VK_SHIFT) & 0x8000) != 0) modifiers |= MOD_SHIFT;
        if ((GetKeyState(VK_LWIN) & 0x8000) != 0
            || (GetKeyState(VK_RWIN) & 0x8000) != 0) {
            modifiers |= MOD_WIN;
        }
        if (modifiers == 0U) {
            MessageBoxW(window, L"快捷键必须包含 Ctrl、Alt、Shift 或 Win。",
                L"录制快捷键", MB_OK | MB_ICONWARNING);
            return;
        }
        const HotKeyBinding replacement{
            hotKeyCommand(static_cast<std::size_t>(recordingShortcutIndex)),
            modifiers, virtualKey};
        auto bindings = defaultAppHotKeys();
        if (shortcutCallbacks.load) bindings = shortcutCallbacks.load();
        for (std::size_t index = 0; index < bindings.size(); ++index) {
            if (static_cast<int>(index) != recordingShortcutIndex
                && bindings[index].enabled
                && bindings[index].modifiers == replacement.modifiers
                && bindings[index].virtualKey == replacement.virtualKey) {
                MessageBoxW(window, L"该快捷键已被 XxSnap 的其他操作占用。",
                    L"录制快捷键", MB_OK | MB_ICONWARNING);
                return;
            }
        }
        if (!shortcutCallbacks.apply || !shortcutCallbacks.apply(replacement)) {
            MessageBoxW(window, L"该快捷键已被占用，或无法注册。",
                L"录制快捷键", MB_OK | MB_ICONWARNING);
            return;
        }
        recordingShortcutIndex = -1;
        rebuildPage();
    }

    LRESULT handle(UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        switch (message) {
        case WM_COMMAND:
            try {
                handleCommand(LOWORD(wParam), HIWORD(wParam));
            } catch (...) {
                reportSaveFailure();
            }
            return 0;
        case WM_KEYDOWN:
            try {
                recordShortcut(static_cast<UINT>(wParam));
            } catch (...) {
                recordingShortcutIndex = -1;
                rebuildPage();
            }
            return 0;
        case WM_DRAWITEM:
            if (const auto* item = reinterpret_cast<DRAWITEMSTRUCT*>(lParam)) {
                drawNavigationButton(*item);
                return TRUE;
            }
            return FALSE;
        case WM_CTLCOLORSTATIC: {
            const auto dc = reinterpret_cast<HDC>(wParam);
            const auto control = reinterpret_cast<HWND>(lParam);
            SetBkMode(dc, TRANSPARENT);
            if (control == filenameError) {
                SetTextColor(dc, errorColor);
            } else if (control == updateStatus) {
                SetTextColor(dc, successColor);
            } else if (std::find(secondaryControls.begin(),
                           secondaryControls.end(), control)
                != secondaryControls.end()) {
                SetTextColor(dc, secondaryTextColor);
            } else {
                SetTextColor(dc, textColor);
            }
            return reinterpret_cast<LRESULT>(backgroundBrush);
        }
        case WM_PAINT:
            paint();
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_CLOSE:
            commitFilename();
            ShowWindow(window, SW_HIDE);
            return 0;
        case WM_NCDESTROY:
            SetWindowLongPtrW(window, GWLP_USERDATA, 0);
            window = nullptr;
            return 0;
        default:
            return DefWindowProcW(window, message, wParam, lParam);
        }
    }

    void show(PreferencesSection section) noexcept
    {
        if (window == nullptr) return;
        try {
            setSelected(section);
            ShowWindow(window, SW_SHOWNORMAL);
            SetForegroundWindow(window);
        } catch (...) {
        }
    }
};

PreferencesWindow::PreferencesWindow(std::unique_ptr<Impl> impl) noexcept
    : impl_(std::move(impl))
{
}

PreferencesWindow::~PreferencesWindow() = default;

std::unique_ptr<PreferencesWindow> PreferencesWindow::create(
    HINSTANCE instance, HWND owner,
    PreferencesShortcutCallbacks shortcutCallbacks)
{
    try {
        auto impl = std::make_unique<Impl>(
            instance, owner, std::move(shortcutCallbacks));
        if (!impl->createWindow()) return nullptr;
        return std::unique_ptr<PreferencesWindow>(
            new PreferencesWindow(std::move(impl)));
    } catch (...) {
        return nullptr;
    }
}

void PreferencesWindow::show(PreferencesSection section) noexcept
{
    if (impl_) impl_->show(section);
}

HWND PreferencesWindow::window() const noexcept
{
    return impl_ ? impl_->window : nullptr;
}

} // namespace xxsnap::win
