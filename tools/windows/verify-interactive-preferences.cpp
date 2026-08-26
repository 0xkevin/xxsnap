#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include "app/PreferencesSettings.h"

#include <algorithm>
#include <array>
#include <cwchar>
#include <optional>
#include <string>
#include <vector>

namespace {

constexpr wchar_t overlayClassName[] = L"XxSnapCaptureOverlayWindow";
constexpr wchar_t receiverClassName[] = L"XxSnap.HiddenTopLevelWindow.v1";
constexpr wchar_t preferencesClassName[] = L"XxSnap.PreferencesWindow.v1";
constexpr UINT testPreferencesMessage = WM_APP + 0x7B;

HWND findProcessWindow(DWORD processId, const wchar_t* className)
{
    struct Search {
        DWORD processId;
        const wchar_t* className;
        HWND result;
    } search{processId, className, nullptr};
    EnumWindows([](HWND window, LPARAM parameter) -> BOOL {
        auto* current = reinterpret_cast<Search*>(parameter);
        DWORD ownerProcessId = 0;
        GetWindowThreadProcessId(window, &ownerProcessId);
        if (ownerProcessId != current->processId) return TRUE;
        wchar_t actualClass[256]{};
        if (GetClassNameW(window, actualClass,
                static_cast<int>(std::size(actualClass))) > 0
            && std::wcscmp(actualClass, current->className) == 0) {
            current->result = window;
            return FALSE;
        }
        return TRUE;
    }, reinterpret_cast<LPARAM>(&search));
    return search.result;
}

HWND waitForProcessWindow(
    DWORD processId, const wchar_t* className, DWORD timeoutMs)
{
    const auto deadline = GetTickCount64() + timeoutMs;
    while (GetTickCount64() < deadline) {
        if (const auto window = findProcessWindow(processId, className)) {
            return window;
        }
        Sleep(50);
    }
    return nullptr;
}

std::vector<std::wstring> childTexts(HWND parent)
{
    std::vector<std::wstring> result;
    EnumChildWindows(parent, [](HWND window, LPARAM parameter) -> BOOL {
        auto* values = reinterpret_cast<std::vector<std::wstring>*>(parameter);
        const auto length = GetWindowTextLengthW(window);
        if (length > 0) {
            std::wstring text(static_cast<std::size_t>(length) + 1U, L'\0');
            GetWindowTextW(window, text.data(), length + 1);
            text.resize(static_cast<std::size_t>(length));
            values->push_back(std::move(text));
        }
        return TRUE;
    }, reinterpret_cast<LPARAM>(&result));
    return result;
}

bool hasText(HWND parent, const wchar_t* expected)
{
    const auto texts = childTexts(parent);
    return std::find(texts.begin(), texts.end(), expected) != texts.end();
}

bool hasPrefix(HWND parent, const wchar_t* prefix)
{
    const auto texts = childTexts(parent);
    return std::any_of(texts.begin(), texts.end(), [prefix](const auto& text) {
        return text.rfind(prefix, 0) == 0U;
    });
}

bool hasRenderedFilenamePreview(HWND parent)
{
    const auto texts = childTexts(parent);
    return std::any_of(texts.begin(), texts.end(), [](const auto& text) {
        return text.rfind(L"xxsnap_截图_", 0) == 0U
            && text.find(L'{') == std::wstring::npos
            && text.size() >= 4U
            && text.substr(text.size() - 4U) == L".png";
    });
}

void closeExistingInstance()
{
    if (const auto receiver = FindWindowW(receiverClassName, nullptr)) {
        PostMessageW(receiver, WM_CLOSE, 0, 0);
        const auto deadline = GetTickCount64() + 3000;
        while (IsWindow(receiver) && GetTickCount64() < deadline) Sleep(50);
    }
}

bool usesMicrosoftYaHei(HWND control)
{
    const auto font = reinterpret_cast<HFONT>(
        SendMessageW(control, WM_GETFONT, 0, 0));
    if (font == nullptr) return false;
    LOGFONTW description{};
    return GetObjectW(font, sizeof(description), &description)
            == sizeof(description)
        && std::wcscmp(description.lfFaceName, L"Microsoft YaHei") == 0;
}

HWND childWithText(HWND parent, const wchar_t* expected)
{
    struct Search {
        const wchar_t* expected;
        HWND result;
    } search{expected, nullptr};
    EnumChildWindows(parent, [](HWND window, LPARAM parameter) -> BOOL {
        auto* current = reinterpret_cast<Search*>(parameter);
        wchar_t text[256]{};
        GetWindowTextW(window, text, static_cast<int>(std::size(text)));
        if (std::wcscmp(text, current->expected) == 0) {
            current->result = window;
            return FALSE;
        }
        return TRUE;
    }, reinterpret_cast<LPARAM>(&search));
    return search.result;
}

bool labelUsesParentBackground(HWND label, COLORREF expected)
{
    if (label == nullptr) return false;
    RedrawWindow(label, nullptr, nullptr,
        RDW_INVALIDATE | RDW_UPDATENOW);
    RECT client{};
    GetClientRect(label, &client);
    const auto dc = GetDC(label);
    if (dc == nullptr) return false;
    const auto color = GetPixel(dc,
        (std::max)(0L, client.right - 5L),
        (std::max)(0L, (client.bottom - client.top) / 2L));
    ReleaseDC(label, dc);
    return color == expected;
}

bool hasDarkPixels(HWND window, int left, int top, int width, int height)
{
    RedrawWindow(window, nullptr, nullptr,
        RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW);
    const auto dc = GetDC(window);
    if (dc == nullptr) return false;
    const auto dpi = GetDeviceCaps(dc, LOGPIXELSX);
    const auto scaled = [dpi](int value) { return MulDiv(value, dpi, 96); };
    int darkPixels = 0;
    for (int y = scaled(top); y < scaled(top + height); y += scaled(8)) {
        for (int x = scaled(left); x < scaled(left + width); x += scaled(8)) {
            const auto color = GetPixel(dc, x, y);
            if (color != CLR_INVALID && GetRValue(color) < 128
                && GetGValue(color) < 128 && GetBValue(color) < 128) {
                ++darkPixels;
            }
        }
    }
    ReleaseDC(window, dc);
    return darkPixels >= 10;
}

} // namespace

int wmain(int argc, wchar_t** argv)
{
    if (argc != 2 || argv[1] == nullptr || argv[1][0] == L'\0') {
        return ERROR_INVALID_PARAMETER;
    }
    closeExistingInstance();
    xxsnap::win::SystemPreferencesRegistry registry;
    xxsnap::win::PreferencesSettingsStore settingsStore(registry);
    const auto originalSettings = settingsStore.load();
    SetEnvironmentVariableW(L"XXSNAP_INTERACTIVE_TESTING", L"1");

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(argv[1], nullptr, nullptr, nullptr, FALSE, 0,
            nullptr, nullptr, &startup, &process)) {
        return static_cast<int>(GetLastError());
    }
    CloseHandle(process.hThread);

    int result = ERROR_TIMEOUT;
    const auto overlay = waitForProcessWindow(
        process.dwProcessId, overlayClassName, 10000);
    if (overlay != nullptr) {
        DWORD_PTR ignored = 0;
        SendMessageTimeoutW(overlay, WM_KEYDOWN, VK_ESCAPE, 0,
            SMTO_ABORTIFHUNG, 2000, &ignored);
    }
    const auto receiver = waitForProcessWindow(
        process.dwProcessId, receiverClassName, 5000);
    if (receiver != nullptr) {
        PostMessageW(receiver, testPreferencesMessage, 0, 0);
        const auto preferences = waitForProcessWindow(
            process.dwProcessId, preferencesClassName, 5000);
        if (preferences != nullptr && IsWindowVisible(preferences)) {
            wchar_t title[128]{};
            GetWindowTextW(preferences, title, static_cast<int>(std::size(title)));
            RECT client{};
            GetClientRect(preferences, &client);
            const auto dc = GetDC(preferences);
            const auto dpi = dc != nullptr ? GetDeviceCaps(dc, LOGPIXELSX) : 96;
            if (dc != nullptr) ReleaseDC(preferences, dc);
            const auto expectedWidth = MulDiv(680, dpi, 96);
            const auto expectedHeight = MulDiv(480, dpi, 96);
            const auto generalCheckbox = GetDlgItem(preferences, 1100);
            int failureCode = 0;
            const auto require = [&failureCode](bool condition, int code) {
                if (!condition && failureCode == 0) failureCode = code;
            };
            require(std::wcscmp(title, L"XxSnap 设置") == 0, 20);
            require(std::abs((client.right - client.left) - expectedWidth) <= 2,
                21);
            require(std::abs((client.bottom - client.top) - expectedHeight) <= 2,
                22);
            require(generalCheckbox != nullptr, 23);
            require(usesMicrosoftYaHei(GetDlgItem(preferences, 1101)), 24);
            require(hasText(preferences, L"开机自启动"), 25);
            require(labelUsesParentBackground(
                childWithText(preferences, L"开机自启动"),
                RGB(255, 255, 255)), 26);

            SendMessageW(preferences, WM_COMMAND, 1001, 0);
            require(GetDlgItem(preferences, 1200) != nullptr, 30);
            require(hasText(preferences, L"恢复默认快捷键"), 31);
            require(hasPrefix(preferences, L"Ctrl"), 32);

            SendMessageW(preferences, WM_COMMAND, 1002, 0);
            const auto editor = GetDlgItem(preferences, 1300);
            require(editor != nullptr, 40);
            require(hasText(preferences, L"文件名模板"), 41);
            if (editor != nullptr) {
                wchar_t currentEditorText[256]{};
                GetWindowTextW(editor, currentEditorText,
                    static_cast<int>(std::size(currentEditorText)));
                require(std::wcscmp(
                            currentEditorText,
                            L"xxsnap_截图_{yyyyMMdd}_{HHmmss}") == 0,
                    42);
                require(hasRenderedFilenamePreview(preferences), 43);
            }

            SendMessageW(preferences, WM_COMMAND, 1003, 0);
            require(GetDlgItem(preferences, 1401) != nullptr, 50);
            require(GetDlgItem(preferences, 1402) != nullptr, 51);
            require(hasText(preferences, L"自动检查间隔"), 52);
            SendMessageW(preferences, WM_COMMAND,
                MAKEWPARAM(1402, BN_CLICKED), 0);
            require(hasText(preferences, L"已是最新版本"), 53);

            SendMessageW(preferences, WM_COMMAND, 1004, 0);
            require(hasPrefix(preferences,
                L"如果这个软件对您有所帮助"), 60);
            require(hasDarkPixels(preferences, 132, 105, 194, 282), 61);
            require(hasDarkPixels(preferences, 354, 105, 194, 282), 62);
            SendMessageW(preferences, WM_COMMAND, 1005, 0);
            require(hasText(preferences, L"XxSnap"), 70);
            require(hasPrefix(preferences, L"问题反馈或技术支持"), 71);
            auto persistenceProbe = originalSettings;
            persistenceProbe.filenameTemplate = L"qa_{yyyyMMdd}";
            persistenceProbe.updateCheckIntervalHours = 6;
            require(settingsStore.save(persistenceProbe), 72);
            require(settingsStore.load() == persistenceProbe, 73);
            require(settingsStore.save(originalSettings), 74);
            result = failureCode;
            PostMessageW(preferences, WM_CLOSE, 0, 0);
        }
        PostMessageW(receiver, WM_CLOSE, 0, 0);
    }

    const auto deadline = GetTickCount64() + 3000;
    while (WaitForSingleObject(process.hProcess, 50) == WAIT_TIMEOUT
        && GetTickCount64() < deadline) {
    }
    if (WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT) {
        TerminateProcess(process.hProcess, ERROR_CANCELLED);
    }
    CloseHandle(process.hProcess);
    settingsStore.save(originalSettings);
    return result;
}
