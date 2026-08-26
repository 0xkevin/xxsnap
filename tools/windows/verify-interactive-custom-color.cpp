#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "annotation/ShapeOptions.h"
#include "overlay/OverlayRenderer.h"
#include "toolbar/ToolbarCatalog.h"

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cwchar>
#include <vector>

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

void movePointer(POINT point)
{
    SetCursorPos(point.x, point.y);
    Sleep(100);
}

void click(POINT point)
{
    movePointer(point);
    INPUT input{};
    input.type = INPUT_MOUSE;
    input.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
    SendInput(1, &input, sizeof(input));
    input.mi.dwFlags = MOUSEEVENTF_LEFTUP;
    SendInput(1, &input, sizeof(input));
    Sleep(150);
}

void drag(POINT start, POINT finish)
{
    movePointer(start);
    INPUT input{};
    input.type = INPUT_MOUSE;
    input.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
    SendInput(1, &input, sizeof(input));
    constexpr int steps = 12;
    for (int step = 1; step <= steps; ++step) {
        movePointer({
            start.x + (finish.x - start.x) * step / steps,
            start.y + (finish.y - start.y) * step / steps,
        });
    }
    input.mi.dwFlags = MOUSEEVENTF_LEFTUP;
    SendInput(1, &input, sizeof(input));
    Sleep(150);
}

void sendKey(WORD key, bool up = false)
{
    INPUT input{};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = key;
    input.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
    SendInput(1, &input, sizeof(input));
}

xxsnap::win::AnnotationPoint optionsOrigin(
    const xxsnap::win::OverlayLayout& chrome,
    xxsnap::win::AnnotationRect initial) noexcept
{
    const xxsnap::win::AnnotationRect safe{
        8.0F, 8.0F,
        (std::max)(0.0F, chrome.overlayBounds.width - 16.0F),
        (std::max)(0.0F, chrome.overlayBounds.height - 16.0F),
    };
    const auto x = (std::max)(safe.x, (std::min)(
        chrome.toolbar.bounds.x,
        safe.x + (std::max)(0.0F, safe.width - initial.width)));
    auto y = chrome.toolbar.bounds.y + chrome.toolbar.bounds.height + 8.0F;
    if (y + initial.height > safe.y + safe.height) {
        y = chrome.toolbar.bounds.y - 8.0F - initial.height;
    }
    y = (std::max)(safe.y, (std::min)(
        y, safe.y + (std::max)(0.0F, safe.height - initial.height)));
    return {x, y};
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
            const POINT selectionStart{
                origin.x + width / 5, origin.y + height / 5};
            const POINT selectionEnd{
                origin.x + width * 4 / 5, origin.y + height * 3 / 5};
            drag(selectionStart, selectionEnd);
            sendKey('N');
            sendKey('N', true);
            Sleep(200);

            const auto& actions = xxsnap::win::fullToolbarActions();
            const auto chrome = xxsnap::win::computeOverlayLayout({
                {origin.x, origin.y, width, height},
                {selectionStart.x, selectionStart.y,
                    selectionEnd.x - selectionStart.x,
                    selectionEnd.y - selectionStart.y},
                dpi, dpi, 0.0F, true,
                {actions.begin(), actions.end()},
            });
            const auto initial = xxsnap::win::numberOptionsLayout(
                {}, xxsnap::win::macShapePalette().size());
            const auto options = xxsnap::win::numberOptionsLayout(
                optionsOrigin(chrome, initial.toolbar),
                xxsnap::win::macShapePalette().size());
            const auto custom = options.colorSwatches.back();
            click({
                origin.x + MulDiv(static_cast<int>(std::lround(
                    custom.x + custom.width / 2.0F)), dpi, 96),
                origin.y + MulDiv(static_cast<int>(std::lround(
                    custom.y + custom.height / 2.0F)), dpi, 96),
            });
            const auto dialog = waitForProcessWindow(
                process.dwProcessId, L"#32770", 3000);
            if (dialog != nullptr) {
                PostMessageW(dialog, WM_COMMAND, IDCANCEL, 0);
                const auto deadline = GetTickCount64() + 3000;
                while (IsWindow(dialog) && GetTickCount64() < deadline) {
                    Sleep(50);
                }
                if (!IsWindow(dialog)
                    && WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT
                    && findProcessWindow(
                        process.dwProcessId, overlayClassName) != nullptr) {
                    result = ERROR_SUCCESS;
                } else {
                    result = ERROR_INVALID_STATE;
                }
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
