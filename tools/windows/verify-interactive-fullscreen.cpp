#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <algorithm>
#include <cwchar>

namespace {

constexpr wchar_t overlayClassName[] = L"XxSnapCaptureOverlayWindow";
constexpr wchar_t previewClassName[] = L"XxSnapFullScreenPreviewWindow";

struct WindowSearch {
    DWORD processId = 0;
    const wchar_t* className = nullptr;
    HWND result = nullptr;
};

BOOL CALLBACK findWindow(HWND window, LPARAM parameter)
{
    auto* search = reinterpret_cast<WindowSearch*>(parameter);
    DWORD ownerProcessId = 0;
    GetWindowThreadProcessId(window, &ownerProcessId);
    if (ownerProcessId != search->processId || !IsWindowVisible(window)) return TRUE;

    wchar_t actualClass[256]{};
    if (GetClassNameW(window, actualClass, static_cast<int>(_countof(actualClass))) > 0
        && std::wcscmp(actualClass, search->className) == 0) {
        search->result = window;
        return FALSE;
    }
    return TRUE;
}

HWND waitForWindow(DWORD processId, const wchar_t* className, DWORD timeoutMs)
{
    const auto deadline = GetTickCount64() + timeoutMs;
    while (GetTickCount64() < deadline) {
        WindowSearch search{processId, className, nullptr};
        EnumWindows(findWindow, reinterpret_cast<LPARAM>(&search));
        if (search.result != nullptr) return search.result;
        Sleep(50);
    }
    return nullptr;
}

bool previewHasVisibleContent(HWND preview)
{
    RECT client{};
    if (!GetClientRect(preview, &client)) return false;
    const auto width = client.right - client.left;
    const auto height = client.bottom - client.top;
    if (width <= 2 || height <= 2) return false;
    const auto dc = GetDC(preview);
    if (dc == nullptr) return false;
    bool visible = false;
    const auto stepX = (std::max)(1L, width / 64);
    const auto stepY = (std::max)(1L, height / 44);
    for (LONG y = 1; y < height - 1 && !visible; y += stepY) {
        for (LONG x = 1; x < width - 1; x += stepX) {
            const auto color = GetPixel(dc, x, y);
            if (color != CLR_INVALID
                && (GetRValue(color) > 3U
                    || GetGValue(color) > 3U
                    || GetBValue(color) > 3U)) {
                visible = true;
                break;
            }
        }
    }
    ReleaseDC(preview, dc);
    return visible;
}

void sendKey(WORD key, bool up = false)
{
    INPUT input{};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = key;
    input.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
    SendInput(1, &input, sizeof(input));
}

} // namespace

int wmain(int argc, wchar_t** argv)
{
    if (argc != 2 || argv[1] == nullptr || argv[1][0] == L'\0') {
        return ERROR_INVALID_PARAMETER;
    }

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(argv[1], nullptr, nullptr, nullptr, FALSE, 0,
            nullptr, nullptr, &startup, &process)) {
        return static_cast<int>(GetLastError());
    }
    CloseHandle(process.hThread);

    int result = ERROR_TIMEOUT;
    const auto capture = waitForWindow(
        process.dwProcessId, overlayClassName, 10000);
    if (capture != nullptr) {
        DWORD_PTR messageResult = 0;
        SendMessageTimeoutW(capture, WM_KEYDOWN, VK_ESCAPE, 0,
            SMTO_ABORTIFHUNG, 2000, &messageResult);
        Sleep(200);
        sendKey(VK_CONTROL);
        sendKey(VK_SHIFT);
        sendKey('1');
        sendKey('1', true);
        sendKey(VK_SHIFT, true);
        sendKey(VK_CONTROL, true);

        const auto preview = waitForWindow(
            process.dwProcessId, previewClassName, 7000);
        if (preview != nullptr) {
            RECT previewRect{};
            GetWindowRect(preview, &previewRect);
            const auto width = previewRect.right - previewRect.left;
            const auto height = previewRect.bottom - previewRect.top;
            if (width > 0 && height > 0 && width <= 320 && height <= 220
                && previewHasVisibleContent(preview)) {
                SendMessageTimeoutW(preview, WM_LBUTTONUP, 0, 0,
                    SMTO_ABORTIFHUNG, 2000, &messageResult);
                const auto editor = waitForWindow(
                    process.dwProcessId, overlayClassName, 5000);
                if (editor != nullptr && !IsWindowVisible(preview)) {
                    SendMessageTimeoutW(editor, WM_KEYDOWN, VK_SHIFT, 0,
                        SMTO_ABORTIFHUNG, 2000, &messageResult);
                    SendMessageTimeoutW(editor, WM_KEYUP, VK_SHIFT, 0,
                        SMTO_ABORTIFHUNG, 2000, &messageResult);
                    const auto deadline = GetTickCount64() + 3000;
                    while (!IsWindowVisible(preview)
                        && GetTickCount64() < deadline) {
                        Sleep(50);
                    }
                    result = IsWindowVisible(preview)
                        ? ERROR_SUCCESS : ERROR_INVALID_STATE;
                } else {
                    result = ERROR_INVALID_STATE;
                }
            } else {
                result = ERROR_INVALID_DATA;
            }
        }
    }

    if (WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT) {
        TerminateProcess(process.hProcess, static_cast<UINT>(result));
        WaitForSingleObject(process.hProcess, 5000);
    }
    CloseHandle(process.hProcess);
    return result;
}
