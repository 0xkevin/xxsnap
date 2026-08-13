#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <array>
#include <cstdlib>
#include <cwchar>
#include <string>

namespace {

constexpr wchar_t overlayClassName[] = L"XxSnapCaptureOverlayWindow";
constexpr wchar_t receiverClassName[] = L"XxSnap.HiddenTopLevelWindow.v1";
constexpr wchar_t helpClassName[] = L"XxSnap.HelpWindow.v1";
constexpr UINT testHelpMessage = WM_APP + 0x7C;

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
    if (const auto receiver = FindWindowW(receiverClassName, nullptr)) {
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
            process.dwProcessId, overlayClassName, 10000)) {
        SendMessageW(overlay, WM_KEYDOWN, VK_ESCAPE, 0);
    }
    if (const auto receiver = waitForWindow(
            process.dwProcessId, receiverClassName, 5000)) {
        PostMessageW(receiver, testHelpMessage, 0, 0);
        if (const auto help = waitForWindow(
                process.dwProcessId, helpClassName, 5000)) {
            const auto visibleDeadline = GetTickCount64() + 2000;
            while (!IsWindowVisible(help)
                && GetTickCount64() < visibleDeadline) {
                Sleep(20);
            }
            auto failure = 0;
            const auto require = [&failure](bool condition, int code) {
                if (!condition && failure == 0) failure = code;
            };
            require(IsWindowVisible(help) != FALSE, 20);
            RECT client{};
            GetClientRect(help, &client);
            const auto dc = GetDC(help);
            const auto dpi = dc == nullptr ? 96 : GetDeviceCaps(dc, LOGPIXELSX);
            if (dc != nullptr) ReleaseDC(help, dc);
            require(std::abs(client.right - MulDiv(980, dpi, 96)) <= 2, 21);
            require(std::abs(client.bottom - MulDiv(700, dpi, 96)) <= 2, 22);
            const auto content = GetDlgItem(help, 2200);
            require(content != nullptr, 23);
            require(GetDlgItem(help, 2100) != nullptr, 24);
            require(GetDlgItem(help, 2104) != nullptr, 25);
            SendMessageW(help, WM_COMMAND, 2104, 0);
            require(IsWindowEnabled(GetDlgItem(help, 2104)) == FALSE, 26);
            result = failure;
            PostMessageW(help, WM_CLOSE, 0, 0);
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
