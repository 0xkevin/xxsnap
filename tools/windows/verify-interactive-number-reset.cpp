#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cwchar>

namespace {

constexpr wchar_t overlayClassName[] = L"XxSnapCaptureOverlayWindow";
constexpr wchar_t receiverClassName[] = L"XxSnap.HiddenTopLevelWindow.v1";

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
        if (ownerProcessId != current->processId || !IsWindowVisible(window)) {
            return TRUE;
        }
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

void closeExistingInstance()
{
    if (const auto receiver = FindWindowW(receiverClassName, nullptr)) {
        PostMessageW(receiver, WM_CLOSE, 0, 0);
        const auto deadline = GetTickCount64() + 3000;
        while (IsWindow(receiver) && GetTickCount64() < deadline) Sleep(50);
    }
}

void sendKey(WORD key, bool up = false)
{
    INPUT input{};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = key;
    input.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
    SendInput(1, &input, sizeof(input));
}

void movePointer(POINT point)
{
    SetCursorPos(point.x, point.y);
    Sleep(100);
}

void setLeftButton(bool down)
{
    INPUT input{};
    input.type = INPUT_MOUSE;
    input.mi.dwFlags = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
    SendInput(1, &input, sizeof(input));
    Sleep(100);
}

void click(POINT point)
{
    movePointer(point);
    setLeftButton(true);
    setLeftButton(false);
}

void drag(POINT start, POINT finish)
{
    movePointer(start);
    setLeftButton(true);
    constexpr int steps = 12;
    for (int step = 1; step <= steps; ++step) {
        movePointer({
            start.x + (finish.x - start.x) * step / steps,
            start.y + (finish.y - start.y) * step / steps,
        });
    }
    setLeftButton(false);
}

HCURSOR visibleCursor()
{
    CURSORINFO info{};
    info.cbSize = sizeof(info);
    return GetCursorInfo(&info) && (info.flags & CURSOR_SHOWING) != 0U
        ? info.hCursor : nullptr;
}

} // namespace

int wmain(int argc, wchar_t** argv)
{
    if (argc != 2 || argv[1] == nullptr || argv[1][0] == L'\0') {
        return ERROR_INVALID_PARAMETER;
    }

    closeExistingInstance();
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
        SetForegroundWindow(overlay);
        RECT client{};
        POINT origin{};
        GetClientRect(overlay, &client);
        ClientToScreen(overlay, &origin);
        const auto width = client.right - client.left;
        const auto height = client.bottom - client.top;
        const auto dpi = GetDpiForWindow(overlay);
        if (width >= 800 && height >= 600 && dpi != 0U) {
            const POINT selectionStart{origin.x + width / 5,
                origin.y + height / 5};
            const POINT selectionEnd{origin.x + width * 4 / 5,
                origin.y + height * 4 / 5};
            drag(selectionStart, selectionEnd);
            sendKey('N');
            sendKey('N', true);
            Sleep(200);

            const POINT first{selectionStart.x + width / 5,
                selectionStart.y + height / 5};
            const POINT second{first.x + MulDiv(90, dpi, 96), first.y};
            click(first);
            click(second);
            const auto beforeReset = visibleCursor();

            const POINT reset{
                second.x - MulDiv(21, dpi, 96),
                second.y + MulDiv(13, dpi, 96),
            };
            click(reset);
            const auto afterReset = visibleCursor();
            const auto arrow = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));

            const POINT empty{second.x + MulDiv(120, dpi, 96),
                second.y + MulDiv(70, dpi, 96)};
            movePointer(empty);
            const auto afterMove = visibleCursor();
            click(empty);
            const auto afterNextNumber = visibleCursor();

            if (beforeReset != nullptr && afterReset != nullptr
                && afterReset != arrow && afterReset != beforeReset
                && afterMove == afterReset
                && afterNextNumber != nullptr
                && afterNextNumber != arrow
                && afterNextNumber != afterReset) {
                result = ERROR_SUCCESS;
            } else {
                result = ERROR_INVALID_STATE;
            }
        } else {
            result = ERROR_INVALID_DATA;
        }
    }

    if (WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT) {
        TerminateProcess(process.hProcess, static_cast<UINT>(result));
        WaitForSingleObject(process.hProcess, 5000);
    }
    CloseHandle(process.hProcess);
    return result;
}
