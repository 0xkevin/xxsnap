#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <algorithm>
#include <cstdlib>
#include <cwchar>

namespace {

constexpr wchar_t overlayClassName[] = L"XxSnapCaptureOverlayWindow";
constexpr wchar_t scrollClassName[] = L"XxSnapScrollCaptureChromeWindow";

struct WindowSearch {
    DWORD processId = 0U;
    const wchar_t* className = nullptr;
    HWND result = nullptr;
};

BOOL CALLBACK findWindow(HWND window, LPARAM parameter)
{
    auto* search = reinterpret_cast<WindowSearch*>(parameter);
    DWORD processId = 0U;
    GetWindowThreadProcessId(window, &processId);
    if (processId != search->processId || !IsWindowVisible(window)) return TRUE;
    wchar_t className[128]{};
    if (GetClassNameW(window, className,
            static_cast<int>(_countof(className))) > 0
        && std::wcscmp(className, search->className) == 0) {
        search->result = window;
        return FALSE;
    }
    return TRUE;
}

HWND waitForWindow(DWORD processId, const wchar_t* className, DWORD timeout)
{
    const auto deadline = GetTickCount64() + timeout;
    while (GetTickCount64() < deadline) {
        WindowSearch search{processId, className, nullptr};
        EnumWindows(findWindow, reinterpret_cast<LPARAM>(&search));
        if (search.result != nullptr) return search.result;
        Sleep(50U);
    }
    return nullptr;
}

void sendMouse(DWORD flags, LONG x, LONG y, DWORD data = 0U)
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
    input.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0U;
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

    auto result = ERROR_TIMEOUT;
    const auto overlay = waitForWindow(
        process.dwProcessId, overlayClassName, 10'000U);
    if (overlay != nullptr) {
        RECT bounds{};
        GetWindowRect(overlay, &bounds);
        const auto startX = bounds.left + (bounds.right - bounds.left) / 3;
        const auto startY = bounds.top + (bounds.bottom - bounds.top) / 5;
        const auto endX = (std::min)(bounds.right - 100L, startX + 700L);
        const auto endY = (std::min)(bounds.bottom - 100L, startY + 800L);
        sendMouse(MOUSEEVENTF_MOVE, startX, startY);
        sendMouse(MOUSEEVENTF_MOVE | MOUSEEVENTF_LEFTDOWN, startX, startY);
        Sleep(100U);
        sendMouse(MOUSEEVENTF_MOVE, endX, endY);
        sendMouse(MOUSEEVENTF_MOVE | MOUSEEVENTF_LEFTUP, endX, endY);
        Sleep(200U);
        sendKey('R');
        sendKey('R', true);

        const auto scroll = waitForWindow(
            process.dwProcessId, scrollClassName, 5'000U);
        if (scroll != nullptr
            && WaitForSingleObject(process.hProcess, 0U) == WAIT_TIMEOUT) {
            RECT scrollBounds{};
            GetWindowRect(scroll, &scrollBounds);
            const auto x = (scrollBounds.left + scrollBounds.right) / 2;
            const auto y = (scrollBounds.top + scrollBounds.bottom) / 2;
            sendMouse(MOUSEEVENTF_MOVE, x, y);
            for (int attempt = 0; attempt < 5; ++attempt) {
                sendMouse(MOUSEEVENTF_WHEEL, x, y,
                    static_cast<DWORD>(-WHEEL_DELTA));
                Sleep(300U);
                if (WaitForSingleObject(process.hProcess, 0U) != WAIT_TIMEOUT) {
                    break;
                }
            }
            Sleep(2'000U);
            if (WaitForSingleObject(process.hProcess, 0U) != WAIT_TIMEOUT) {
                result = ERROR_PROCESS_ABORTED;
            } else {
                sendKey(VK_RETURN);
                sendKey(VK_RETURN, true);
                const auto editor = waitForWindow(
                    process.dwProcessId, overlayClassName, 10'000U);
                if (editor == nullptr) {
                    result = ERROR_TIMEOUT;
                } else {
                    const auto style = static_cast<DWORD>(
                        GetWindowLongPtrW(editor, GWL_STYLE));
                    wchar_t title[256]{};
                    GetWindowTextW(editor, title, static_cast<int>(_countof(title)));
                    RECT before{};
                    GetWindowRect(editor, &before);
                    const auto titleX = before.left
                        + (std::min)(160L, (std::max)(40L,
                            (before.right - before.left) / 3));
                    const auto titleY = before.top + 12L;
                    sendMouse(MOUSEEVENTF_MOVE, titleX, titleY);
                    sendMouse(MOUSEEVENTF_MOVE | MOUSEEVENTF_LEFTDOWN,
                        titleX, titleY);
                    Sleep(100U);
                    sendMouse(MOUSEEVENTF_MOVE, titleX + 80L, titleY + 60L);
                    sendMouse(MOUSEEVENTF_MOVE | MOUSEEVENTF_LEFTUP,
                        titleX + 80L, titleY + 60L);
                    Sleep(250U);
                    RECT after{};
                    GetWindowRect(editor, &after);
                    const auto moved = std::abs(after.left - before.left) >= 40L
                        && std::abs(after.top - before.top) >= 30L;
                    result = (style & WS_CAPTION) != 0U
                            && std::wcsstr(title, L"px") != nullptr && moved
                        ? ERROR_SUCCESS : ERROR_INVALID_STATE;
                }
            }
        }
    }

    if (WaitForSingleObject(process.hProcess, 0U) == WAIT_TIMEOUT) {
        TerminateProcess(process.hProcess, static_cast<UINT>(result));
        WaitForSingleObject(process.hProcess, 5'000U);
    }
    CloseHandle(process.hProcess);
    return static_cast<int>(result);
}
