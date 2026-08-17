#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <algorithm>
#include <cwchar>
#include <vector>

namespace {

constexpr wchar_t overlayClassName[] = L"XxSnapCaptureOverlayWindow";
constexpr wchar_t receiverClassName[] = L"XxSnap.HiddenTopLevelWindow.v1";
constexpr UINT testOcrMessage = WM_APP + 0x7A;

struct WindowSearch {
    DWORD processId = 0;
    HWND excluded = nullptr;
    HWND result = nullptr;
};

BOOL CALLBACK findOverlay(HWND window, LPARAM parameter)
{
    auto* search = reinterpret_cast<WindowSearch*>(parameter);
    DWORD ownerProcessId = 0;
    GetWindowThreadProcessId(window, &ownerProcessId);
    if (ownerProcessId != search->processId || window == search->excluded
        || !IsWindowVisible(window)) {
        return TRUE;
    }
    wchar_t actualClass[256]{};
    if (GetClassNameW(window, actualClass,
            static_cast<int>(_countof(actualClass))) > 0
        && std::wcscmp(actualClass, overlayClassName) == 0) {
        search->result = window;
        return FALSE;
    }
    return TRUE;
}

HWND waitForOverlay(DWORD processId, HWND excluded, DWORD timeoutMs)
{
    const auto deadline = GetTickCount64() + timeoutMs;
    while (GetTickCount64() < deadline) {
        WindowSearch search{processId, excluded, nullptr};
        EnumWindows(findOverlay, reinterpret_cast<LPARAM>(&search));
        if (search.result != nullptr) return search.result;
        Sleep(50);
    }
    return nullptr;
}

std::vector<HWND> overlayWindows(DWORD processId)
{
    struct Search {
        DWORD processId;
        std::vector<HWND> windows;
    } search{processId, {}};
    EnumWindows([](HWND window, LPARAM parameter) -> BOOL {
        auto* current = reinterpret_cast<Search*>(parameter);
        DWORD ownerProcessId = 0;
        GetWindowThreadProcessId(window, &ownerProcessId);
        if (ownerProcessId != current->processId || !IsWindowVisible(window)) {
            return TRUE;
        }
        wchar_t actualClass[256]{};
        if (GetClassNameW(window, actualClass,
                static_cast<int>(_countof(actualClass))) > 0
            && std::wcscmp(actualClass, overlayClassName) == 0) {
            current->windows.push_back(window);
        }
        return TRUE;
    }, reinterpret_cast<LPARAM>(&search));
    return search.windows;
}

HWND waitForNewOverlay(DWORD processId,
    const std::vector<HWND>& existing, DWORD timeoutMs)
{
    const auto deadline = GetTickCount64() + timeoutMs;
    while (GetTickCount64() < deadline) {
        const auto current = overlayWindows(processId);
        const auto found = std::find_if(current.begin(), current.end(),
            [&existing](HWND window) {
                return std::find(existing.begin(), existing.end(), window)
                    == existing.end();
            });
        if (found != current.end()) return *found;
        Sleep(50);
    }
    return nullptr;
}

HWND receiverWindow(DWORD processId)
{
    const auto direct = FindWindowW(receiverClassName, nullptr);
    if (direct != nullptr) {
        DWORD directProcessId = 0;
        GetWindowThreadProcessId(direct, &directProcessId);
        if (directProcessId == processId) return direct;
    }
    struct Search {
        DWORD processId;
        HWND result;
    } search{processId, nullptr};
    EnumWindows([](HWND window, LPARAM parameter) -> BOOL {
        auto* current = reinterpret_cast<Search*>(parameter);
        DWORD ownerProcessId = 0;
        GetWindowThreadProcessId(window, &ownerProcessId);
        if (ownerProcessId != current->processId) return TRUE;
        wchar_t actualClass[256]{};
        if (GetClassNameW(window, actualClass,
                static_cast<int>(_countof(actualClass))) > 0
            && std::wcscmp(actualClass, receiverClassName) == 0) {
            current->result = window;
            return FALSE;
        }
        return TRUE;
    }, reinterpret_cast<LPARAM>(&search));
    return search.result;
}

void sendKey(WORD key, bool up = false)
{
    INPUT input{};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = key;
    input.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
    SendInput(1, &input, sizeof(input));
}

void sendControlTwo()
{
    sendKey(VK_CONTROL);
    sendKey('2');
    sendKey('2', true);
    sendKey(VK_CONTROL, true);
}

LPARAM pointParameter(int x, int y)
{
    return MAKELPARAM(static_cast<short>(x), static_cast<short>(y));
}

bool hasRedInk(HWND window, RECT client)
{
    const auto dc = GetDC(window);
    if (dc == nullptr) return false;
    int redPixels = 0;
    for (int y = 85; y <= 165; ++y) {
        for (int x = 85; x <= 215; ++x) {
            if (x >= client.right || y >= client.bottom) continue;
            const auto color = GetPixel(dc, x, y);
            if (color != CLR_INVALID
                && GetRValue(color) >= 180U
                && GetRValue(color) > GetGValue(color) + 60U
                && GetRValue(color) > GetBValue(color) + 60U) {
                ++redPixels;
            }
        }
    }
    ReleaseDC(window, dc);
    return redPixels >= 12;
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
    SetEnvironmentVariableW(L"XXSNAP_INTERACTIVE_TESTING", L"1");
    if (!CreateProcessW(argv[1], nullptr, nullptr, nullptr, FALSE, 0,
            nullptr, nullptr, &startup, &process)) {
        return static_cast<int>(GetLastError());
    }
    CloseHandle(process.hThread);

    int result = ERROR_TIMEOUT;
    const auto initial = waitForOverlay(process.dwProcessId, nullptr, 10000);
    if (initial != nullptr) {
        DWORD_PTR messageResult = 0;
        SendMessageTimeoutW(initial, WM_KEYDOWN, VK_ESCAPE, 0,
            SMTO_ABORTIFHUNG, 2000, &messageResult);
        const auto initialDeadline = GetTickCount64() + 3000;
        while (IsWindow(initial) && IsWindowVisible(initial)
            && GetTickCount64() < initialDeadline) {
            Sleep(50);
        }
        sendControlTwo();
        const auto teaching = waitForOverlay(
            process.dwProcessId, initial, 7000);
        if (teaching != nullptr) {
            RECT client{};
            GetClientRect(teaching, &client);
            const auto width = client.right - client.left;
            const auto height = client.bottom - client.top;
            if (width >= 320 && height >= 240) {
                const auto centerX = width / 2;
                const auto centerY = height / 2;
                SendMessageTimeoutW(teaching, WM_RBUTTONDOWN, MK_RBUTTON,
                    pointParameter(centerX, centerY), SMTO_ABORTIFHUNG,
                    2000, &messageResult);
                Sleep(200);

                SendMessageTimeoutW(teaching, WM_LBUTTONDOWN, MK_LBUTTON,
                    pointParameter(100, 100), SMTO_ABORTIFHUNG,
                    2000, &messageResult);
                for (int step = 1; step <= 10; ++step) {
                    const auto x = 100 + step * 10;
                    const auto y = 100 + step * 5;
                    SendMessageTimeoutW(teaching, WM_MOUSEMOVE, MK_LBUTTON,
                        pointParameter(x, y), SMTO_ABORTIFHUNG,
                        2000, &messageResult);
                }
                SendMessageTimeoutW(teaching, WM_LBUTTONUP, 0,
                    pointParameter(200, 150), SMTO_ABORTIFHUNG,
                    2000, &messageResult);
                Sleep(400);
                if (hasRedInk(teaching, client)) {
                    const auto teachingWindows = overlayWindows(
                        process.dwProcessId);
                    const auto receiver = receiverWindow(process.dwProcessId);
                    if (receiver != nullptr) {
                        PostMessageW(receiver, testOcrMessage, 0, 0);
                    }
                    const auto recognition = waitForNewOverlay(
                        process.dwProcessId, teachingWindows, 7000);
                    auto recognitionRoundTrip = false;
                    const auto teachingVisible = std::all_of(
                        teachingWindows.begin(), teachingWindows.end(),
                        [](HWND window) { return IsWindowVisible(window); });
                    if (recognition != nullptr && teachingVisible) {
                        SendMessageTimeoutW(recognition, WM_KEYDOWN,
                            VK_ESCAPE, 0, SMTO_ABORTIFHUNG, 2000,
                            &messageResult);
                        const auto resumeDeadline = GetTickCount64() + 3000;
                        while (IsWindowVisible(recognition)
                            && GetTickCount64() < resumeDeadline) {
                            Sleep(50);
                        }
                        recognitionRoundTrip = std::all_of(
                            teachingWindows.begin(), teachingWindows.end(),
                            [](HWND window) {
                                return IsWindowVisible(window)
                                    && IsWindowEnabled(window);
                            });
                    }
                    if (recognitionRoundTrip) {
                        SendMessageTimeoutW(teaching, WM_KEYDOWN, VK_ESCAPE, 0,
                            SMTO_ABORTIFHUNG, 2000, &messageResult);
                        SendMessageTimeoutW(teaching, WM_KEYDOWN, VK_ESCAPE, 0,
                            SMTO_ABORTIFHUNG, 2000, &messageResult);
                        const auto exitDeadline = GetTickCount64() + 3000;
                        while (IsWindow(teaching) && IsWindowVisible(teaching)
                            && GetTickCount64() < exitDeadline) {
                            Sleep(50);
                        }
                        result = !IsWindow(teaching)
                                || !IsWindowVisible(teaching)
                            ? ERROR_SUCCESS : ERROR_INVALID_STATE;
                    } else {
                        result = ERROR_INVALID_STATE;
                    }
                } else {
                    result = ERROR_INVALID_DATA;
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
