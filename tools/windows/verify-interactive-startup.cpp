#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <cwchar>

namespace {

constexpr wchar_t kOverlayClassName[] = L"XxSnapCaptureOverlayWindow";

struct WindowSearch {
    DWORD processId = 0;
    bool found = false;
};

BOOL CALLBACK findVisibleOverlay(HWND window, LPARAM parameter)
{
    auto* search = reinterpret_cast<WindowSearch*>(parameter);
    DWORD ownerProcessId = 0;
    GetWindowThreadProcessId(window, &ownerProcessId);
    if (ownerProcessId != search->processId || !IsWindowVisible(window)) {
        return TRUE;
    }

    wchar_t className[256]{};
    if (GetClassNameW(window, className, static_cast<int>(_countof(className))) > 0
        && std::wcscmp(className, kOverlayClassName) == 0) {
        search->found = true;
        return FALSE;
    }
    return TRUE;
}

bool hasVisibleOverlay(DWORD processId)
{
    WindowSearch search{processId, false};
    EnumWindows(findVisibleOverlay, reinterpret_cast<LPARAM>(&search));
    return search.found;
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
    if (!CreateProcessW(
            argv[1],
            nullptr,
            nullptr,
            nullptr,
            FALSE,
            0,
            nullptr,
            nullptr,
            &startup,
            &process)) {
        return static_cast<int>(GetLastError());
    }
    CloseHandle(process.hThread);

    int result = ERROR_TIMEOUT;
    const ULONGLONG deadline = GetTickCount64() + 10000;
    while (GetTickCount64() < deadline) {
        if (WaitForSingleObject(process.hProcess, 0) == WAIT_OBJECT_0) {
            result = ERROR_PROCESS_ABORTED;
            break;
        }
        if (hasVisibleOverlay(process.dwProcessId)) {
            result = ERROR_SUCCESS;
            break;
        }
        Sleep(100);
    }

    if (WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT) {
        TerminateProcess(process.hProcess, static_cast<UINT>(result));
        WaitForSingleObject(process.hProcess, 5000);
    }
    CloseHandle(process.hProcess);
    return result;
}
