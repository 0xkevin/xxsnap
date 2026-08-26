#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cwchar>
#include <cstring>
#include <iostream>

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

void sendLeftButton(bool down)
{
    INPUT input{};
    input.type = INPUT_MOUSE;
    input.mi.dwFlags = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
    SendInput(1, &input, sizeof(input));
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

std::uint64_t cursorFingerprint(HCURSOR cursor)
{
    if (cursor == nullptr) return 0;
    constexpr int side = 64;
    BITMAPV5HEADER header{};
    header.bV5Size = sizeof(header);
    header.bV5Width = side;
    header.bV5Height = -side;
    header.bV5Planes = 1;
    header.bV5BitCount = 32;
    header.bV5Compression = BI_BITFIELDS;
    header.bV5RedMask = 0x00FF0000;
    header.bV5GreenMask = 0x0000FF00;
    header.bV5BlueMask = 0x000000FF;
    header.bV5AlphaMask = 0xFF000000;
    void* bits = nullptr;
    const auto screen = GetDC(nullptr);
    const auto bitmap = CreateDIBSection(screen,
        reinterpret_cast<BITMAPINFO*>(&header), DIB_RGB_COLORS,
        &bits, nullptr, 0);
    const auto dc = CreateCompatibleDC(screen);
    ReleaseDC(nullptr, screen);
    if (bitmap == nullptr || dc == nullptr || bits == nullptr) {
        if (bitmap != nullptr) DeleteObject(bitmap);
        if (dc != nullptr) DeleteDC(dc);
        return 0;
    }
    std::memset(bits, 0, side * side * sizeof(std::uint32_t));
    const auto previous = SelectObject(dc, bitmap);
    const auto drawn = DrawIconEx(
        dc, 0, 0, cursor, 0, 0, 0, nullptr, DI_NORMAL);
    SelectObject(dc, previous);
    DeleteDC(dc);
    if (!drawn) {
        DeleteObject(bitmap);
        return 0;
    }
    std::uint64_t result = 1469598103934665603ULL;
    const auto* bytes = static_cast<const unsigned char*>(bits);
    for (std::size_t index = 0;
         index < side * side * sizeof(std::uint32_t); ++index) {
        result ^= bytes[index];
        result *= 1099511628211ULL;
    }
    ICONINFO info{};
    if (GetIconInfo(cursor, &info)) {
        result ^= info.xHotspot;
        result *= 1099511628211ULL;
        result ^= info.yHotspot;
        if (info.hbmMask != nullptr) DeleteObject(info.hbmMask);
        if (info.hbmColor != nullptr) DeleteObject(info.hbmColor);
    }
    DeleteObject(bitmap);
    return result;
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
            click(first);
            movePointer({first.x, first.y + MulDiv(70, dpi, 96)});
            const auto expectedResetCursor = visibleCursor();
            const auto expectedResetFingerprint = cursorFingerprint(
                expectedResetCursor);
            POINT last = first;
            for (int index = 1; index < 5; ++index) {
                last.x = first.x + index * MulDiv(70, dpi, 96);
                click(last);
            }
            last = {
                selectionStart.x + MulDiv(10, dpi, 96),
                first.y,
            };
            click(last);
            sendKey('N');
            sendKey('N', true);
            Sleep(200);

            const POINT reset{
                last.x - MulDiv(21, dpi, 96),
                last.y + MulDiv(13, dpi, 96),
            };
            movePointer(reset);
            const auto arrow = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
            const auto resetStarted = GetTickCount64();
            sendLeftButton(true);
            while (visibleCursor() == arrow
                && GetTickCount64() - resetStarted < 100U) {
                Sleep(1);
            }
            const auto resetCursorLatency = GetTickCount64() - resetStarted;
            sendLeftButton(false);
            Sleep(100);
            const auto afterReset = visibleCursor();
            const auto afterResetFingerprint = cursorFingerprint(afterReset);

            const POINT empty{last.x + MulDiv(100, dpi, 96),
                last.y + MulDiv(70, dpi, 96)};
            movePointer(empty);
            const auto afterMove = visibleCursor();
            click(empty);
            const auto afterNextNumber = visibleCursor();
            const auto afterNextFingerprint = cursorFingerprint(
                afterNextNumber);

            if (expectedResetCursor != nullptr
                && expectedResetCursor != arrow
                && expectedResetFingerprint != 0
                && afterResetFingerprint == expectedResetFingerprint
                && resetCursorLatency <= 32U
                && afterMove == afterReset
                && afterNextNumber != nullptr
                && afterNextNumber != arrow
                && afterNextFingerprint != afterResetFingerprint) {
                result = ERROR_SUCCESS;
            } else {
                std::wcerr << L"expected=" << expectedResetCursor
                    << L" arrow=" << arrow
                    << L" afterReset=" << afterReset
                    << L" latency=" << resetCursorLatency
                    << L" afterMove=" << afterMove
                    << L" afterNext=" << afterNextNumber
                    << L" expectedHash=" << expectedResetFingerprint
                    << L" resetHash=" << afterResetFingerprint
                    << L" nextHash=" << afterNextFingerprint << L'\n';
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
