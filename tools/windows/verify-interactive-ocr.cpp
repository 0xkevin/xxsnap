#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <cwchar>
#include <string>

namespace {

constexpr wchar_t overlayClassName[] = L"XxSnapCaptureOverlayWindow";
constexpr wchar_t resultClassName[] = L"XxSnap.OcrResultWindow.v1";
constexpr wchar_t sampleWindowClass[] = L"XxSnap.OcrVerifierSample.v1";
constexpr wchar_t receiverClassName[] = L"XxSnap.HiddenTopLevelWindow.v1";
constexpr int ocrHotKeyId = 0x585C;

struct WindowSearch {
    DWORD processId = 0;
    const wchar_t* className = nullptr;
    HWND result = nullptr;
    bool requireVisible = true;
};

BOOL CALLBACK findWindow(HWND window, LPARAM parameter)
{
    auto* search = reinterpret_cast<WindowSearch*>(parameter);
    DWORD processId = 0;
    GetWindowThreadProcessId(window, &processId);
    if (processId != search->processId
        || (search->requireVisible && !IsWindowVisible(window))) return TRUE;
    wchar_t actual[256]{};
    if (GetClassNameW(window, actual, static_cast<int>(_countof(actual))) > 0
        && std::wcscmp(actual, search->className) == 0) {
        search->result = window;
        return FALSE;
    }
    return TRUE;
}

HWND waitForWindow(
    DWORD processId, const wchar_t* className, DWORD timeoutMs,
    bool requireVisible = true)
{
    const auto deadline = GetTickCount64() + timeoutMs;
    while (GetTickCount64() < deadline) {
        WindowSearch search{processId, className, nullptr, requireVisible};
        EnumWindows(findWindow, reinterpret_cast<LPARAM>(&search));
        if (search.result != nullptr) return search.result;
        MSG message{};
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        Sleep(30);
    }
    return nullptr;
}

void moveMouse(int x, int y, DWORD flags)
{
    const auto left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    const auto top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    const auto width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    const auto height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    INPUT input{};
    input.type = INPUT_MOUSE;
    input.mi.dx = static_cast<LONG>(
        (static_cast<long long>(x - left) * 65535) / (width - 1));
    input.mi.dy = static_cast<LONG>(
        (static_cast<long long>(y - top) * 65535) / (height - 1));
    input.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE
        | MOUSEEVENTF_VIRTUALDESK | flags;
    SendInput(1, &input, sizeof(input));
}

std::wstring clipboardText()
{
    std::wstring result;
    if (!OpenClipboard(nullptr)) return result;
    const auto data = GetClipboardData(CF_UNICODETEXT);
    const auto* text = data != nullptr
        ? static_cast<const wchar_t*>(GlobalLock(data)) : nullptr;
    if (text != nullptr) {
        result = text;
        GlobalUnlock(data);
    }
    CloseClipboard();
    return result;
}

LRESULT CALLBACK sampleProcedure(
    HWND window, UINT message, WPARAM wParam, LPARAM lParam)
{
    if (message == WM_PAINT) {
        PAINTSTRUCT paint{};
        const auto dc = BeginPaint(window, &paint);
        RECT client{};
        GetClientRect(window, &client);
        FillRect(dc, &client,
            reinterpret_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
        const auto font = CreateFontW(64, 0, 0, 0, FW_BOLD,
            FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");
        const auto previous = SelectObject(dc, font);
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, RGB(4, 4, 4));
        DrawTextW(dc, L"\u6587\u5b57\u8bc6\u522b 2026", -1, &client,
            DT_CENTER | DT_SINGLELINE | DT_VCENTER);
        SelectObject(dc, previous);
        DeleteObject(font);
        EndPaint(window, &paint);
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

} // namespace

int wmain(int argc, wchar_t** argv)
{
    if (argc != 2 || argv[1] == nullptr || argv[1][0] == L'\0') {
        return ERROR_INVALID_PARAMETER;
    }
    const auto instance = GetModuleHandleW(nullptr);
    WNDCLASSEXW value{};
    value.cbSize = sizeof(value);
    value.lpfnWndProc = sampleProcedure;
    value.hInstance = instance;
    value.lpszClassName = sampleWindowClass;
    if (!RegisterClassExW(&value)) return static_cast<int>(GetLastError());
    const auto sample = CreateWindowExW(WS_EX_TOPMOST, sampleWindowClass, L"",
        WS_POPUP | WS_VISIBLE, 120, 120, 860, 300,
        nullptr, nullptr, instance, nullptr);
    if (sample == nullptr) return static_cast<int>(GetLastError());
    UpdateWindow(sample);

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(argv[1], nullptr, nullptr, nullptr, FALSE, 0,
            nullptr, nullptr, &startup, &process)) {
        return static_cast<int>(GetLastError());
    }
    CloseHandle(process.hThread);
    int result = ERROR_TIMEOUT;
    const auto initial = waitForWindow(
        process.dwProcessId, overlayClassName, 10000);
    const auto receiver = waitForWindow(
        process.dwProcessId, receiverClassName, 2000, false);
    if (initial != nullptr && receiver != nullptr) {
        DWORD_PTR ignored = 0;
        SendMessageTimeoutW(initial, WM_KEYDOWN, VK_ESCAPE, 0,
            SMTO_ABORTIFHUNG, 2000, &ignored);
        Sleep(200);
        if (PostMessageW(receiver, WM_HOTKEY, ocrHotKeyId,
                MAKELPARAM(MOD_CONTROL, '3'))) {
            const auto overlay = waitForWindow(
                process.dwProcessId, overlayClassName, 7000);
            if (overlay != nullptr) {
                moveMouse(140, 140, 0);
                moveMouse(140, 140, MOUSEEVENTF_LEFTDOWN);
                moveMouse(960, 380, MOUSEEVENTF_LEFTUP);
                const auto panel = waitForWindow(
                    process.dwProcessId, resultClassName, 10000);
                if (panel != nullptr) {
                    wchar_t panelText[128]{};
                    GetWindowTextW(panel, panelText,
                        static_cast<int>(std::size(panelText)));
                    const auto text = clipboardText();
                    result = std::wstring(panelText).find(L"\u8bc6\u522b\u6210\u529f")
                                != std::wstring::npos
                            && text.find(L"\u6587") != std::wstring::npos
                            && text.find(L"2026") != std::wstring::npos
                        ? ERROR_SUCCESS : ERROR_INVALID_DATA;
                }
            }
        }
    }
    DestroyWindow(sample);
    if (WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT) {
        TerminateProcess(process.hProcess, static_cast<UINT>(result));
        WaitForSingleObject(process.hProcess, 5000);
    }
    CloseHandle(process.hProcess);
    return result;
}
