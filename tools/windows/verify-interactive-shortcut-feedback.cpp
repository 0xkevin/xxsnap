#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <array>
#include <cstdlib>
#include <cwchar>

namespace {

constexpr wchar_t overlayClass[] = L"XxSnapCaptureOverlayWindow";
constexpr wchar_t receiverClass[] = L"XxSnap.HiddenTopLevelWindow.v1";
constexpr wchar_t feedbackClass[] = L"XxSnap.ShortcutFeedback.v1";
constexpr UINT showFeedbackMessage = WM_APP + 0x7D;

HWND findProcessWindow(DWORD processId, const wchar_t* className)
{
    struct Search final {
        DWORD processId;
        const wchar_t* className;
        HWND result;
    } search{processId, className, nullptr};
    EnumWindows([](HWND window, LPARAM parameter) -> BOOL {
        auto* current = reinterpret_cast<Search*>(parameter);
        DWORD ownerProcessId = 0;
        GetWindowThreadProcessId(window, &ownerProcessId);
        wchar_t actualClass[128]{};
        if (ownerProcessId == current->processId
            && GetClassNameW(window, actualClass,
                static_cast<int>(std::size(actualClass))) > 0
            && std::wcscmp(actualClass, current->className) == 0) {
            current->result = window;
            return FALSE;
        }
        return TRUE;
    }, reinterpret_cast<LPARAM>(&search));
    return search.result;
}

HWND waitForWindow(DWORD processId, const wchar_t* className, DWORD timeout)
{
    const auto deadline = GetTickCount64() + timeout;
    while (GetTickCount64() < deadline) {
        if (const auto result = findProcessWindow(processId, className)) {
            return result;
        }
        Sleep(50);
    }
    return nullptr;
}

void closeExistingInstance()
{
    if (const auto receiver = FindWindowW(receiverClass, nullptr)) {
        PostMessageW(receiver, WM_CLOSE, 0, 0);
        const auto deadline = GetTickCount64() + 3000;
        while (IsWindow(receiver) && GetTickCount64() < deadline) Sleep(50);
    }
}

} // namespace

int wmain(int argc, wchar_t** argv)
{
    if (argc != 2) return ERROR_INVALID_PARAMETER;
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
    if (const auto overlay = waitForWindow(
            process.dwProcessId, overlayClass, 10000)) {
        SendMessageW(overlay, WM_KEYDOWN, VK_ESCAPE, 0);
    }
    if (const auto receiver = waitForWindow(
            process.dwProcessId, receiverClass, 5000)) {
        PostMessageW(receiver, showFeedbackMessage, 0, 0);
        if (const auto bubble = waitForWindow(
                process.dwProcessId, feedbackClass, 3000)) {
            const auto visibleDeadline = GetTickCount64() + 2000;
            while (!IsWindowVisible(bubble)
                && GetTickCount64() < visibleDeadline) {
                Sleep(20);
            }
            int failure = 0;
            const auto require = [&failure](bool condition, int code) {
                if (!condition && failure == 0) failure = code;
            };
            require(IsWindowVisible(bubble) != FALSE, 20);
            RECT bounds{};
            require(GetWindowRect(bubble, &bounds) != FALSE, 21);
            const auto extended = static_cast<DWORD>(
                GetWindowLongW(bubble, GWL_EXSTYLE));
            require((extended & WS_EX_TOPMOST) != 0, 22);
            require((extended & WS_EX_NOACTIVATE) != 0, 23);
            require((extended & WS_EX_TRANSPARENT) != 0, 24);
            require(bounds.right > bounds.left
                    && bounds.bottom > bounds.top,
                25);

            POINT pointer{};
            GetCursorPos(&pointer);
            MONITORINFO monitorInfo{};
            monitorInfo.cbSize = sizeof(monitorInfo);
            const auto monitor = MonitorFromPoint(
                pointer, MONITOR_DEFAULTTONEAREST);
            require(monitor != nullptr
                    && GetMonitorInfoW(monitor, &monitorInfo),
                26);
            require(bounds.right <= monitorInfo.rcWork.right
                    && bounds.bottom <= monitorInfo.rcWork.bottom,
                27);
            require(monitorInfo.rcWork.right - bounds.right >= 20
                    && monitorInfo.rcWork.bottom - bounds.bottom >= 20,
                28);

            const auto hiddenDeadline = GetTickCount64() + 5000;
            while (IsWindowVisible(bubble)
                && GetTickCount64() < hiddenDeadline) {
                Sleep(20);
            }
            require(IsWindowVisible(bubble) == FALSE, 29);
            result = failure;
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
    return result;
}
