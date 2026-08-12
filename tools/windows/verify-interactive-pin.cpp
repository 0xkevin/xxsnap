#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <algorithm>
#include <cwchar>

namespace {

constexpr wchar_t overlayClassName[] = L"XxSnapCaptureOverlayWindow";
constexpr wchar_t pinClassName[] = L"XxSnapPinnedImageWindow";

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

void sendMouse(DWORD flags, LONG x, LONG y, DWORD data = 0)
{
    const auto left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    const auto top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    const auto width = (std::max)(2, GetSystemMetrics(SM_CXVIRTUALSCREEN));
    const auto height = (std::max)(2, GetSystemMetrics(SM_CYVIRTUALSCREEN));
    INPUT input{};
    input.type = INPUT_MOUSE;
    input.mi.dx = MulDiv(x - left, 65535, width - 1);
    input.mi.dy = MulDiv(y - top, 65535, height - 1);
    input.mi.mouseData = data;
    input.mi.dwFlags = flags | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
    SendInput(1, &input, sizeof(input));
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
    const auto overlay = waitForWindow(process.dwProcessId, overlayClassName, 10000);
    if (overlay != nullptr) {
        RECT overlayRect{};
        GetWindowRect(overlay, &overlayRect);
        const auto startX = overlayRect.left + (overlayRect.right - overlayRect.left) / 4;
        const auto startY = overlayRect.top + (overlayRect.bottom - overlayRect.top) / 4;
        const auto endX = (std::min)(overlayRect.right - 80, startX + 420L);
        const auto endY = (std::min)(overlayRect.bottom - 80, startY + 280L);
        sendMouse(MOUSEEVENTF_MOVE, startX, startY);
        sendMouse(MOUSEEVENTF_MOVE | MOUSEEVENTF_LEFTDOWN, startX, startY);
        Sleep(100);
        sendMouse(MOUSEEVENTF_MOVE, endX, endY);
        sendMouse(MOUSEEVENTF_MOVE | MOUSEEVENTF_LEFTUP, endX, endY);
        Sleep(250);
        sendKey(VK_CONTROL);
        sendKey('1');
        sendKey('1', true);
        sendKey(VK_CONTROL, true);

        const auto pin = waitForWindow(process.dwProcessId, pinClassName, 5000);
        if (pin != nullptr) {
            RECT before{};
            GetWindowRect(pin, &before);
            const auto centerX = (before.left + before.right) / 2;
            const auto centerY = (before.top + before.bottom) / 2;
            SetCursorPos(centerX, centerY);
            SetForegroundWindow(pin);
            DWORD_PTR messageResult = 0;
            SendMessageTimeoutW(pin, WM_MOUSEWHEEL,
                MAKEWPARAM(0, static_cast<WORD>(-WHEEL_DELTA)),
                MAKELPARAM(centerX, centerY), SMTO_ABORTIFHUNG, 2000,
                &messageResult);
            Sleep(250);
            RECT after{};
            GetWindowRect(pin, &after);
            if (after.right - after.left < before.right - before.left
                && after.bottom - after.top < before.bottom - before.top) {
                SendMessageTimeoutW(pin, WM_KEYDOWN, VK_ESCAPE, 0,
                    SMTO_ABORTIFHUNG, 2000, &messageResult);
                Sleep(100);
                result = !IsWindowVisible(pin) ? ERROR_SUCCESS : ERROR_INVALID_STATE;
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
