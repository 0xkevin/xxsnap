#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>
#include <UserEnv.h>
#include <WtsApi32.h>

#include <cwchar>
#include <string>

int wmain(int argc, wchar_t** argv)
{
    const bool waitForExit = argc >= 3 && std::wcscmp(argv[1], L"--wait") == 0;
    const int applicationIndex = waitForExit ? 2 : 1;
    if (applicationIndex >= argc
        || argv[applicationIndex] == nullptr
        || argv[applicationIndex][0] == L'\0') {
        return ERROR_INVALID_PARAMETER;
    }

    HANDLE userToken = nullptr;
    if (!WTSQueryUserToken(WTSGetActiveConsoleSessionId(), &userToken)) {
        return static_cast<int>(GetLastError());
    }

    HANDLE primaryToken = nullptr;
    if (!DuplicateTokenEx(
            userToken,
            TOKEN_ALL_ACCESS,
            nullptr,
            SecurityImpersonation,
            TokenPrimary,
            &primaryToken)) {
        const auto error = GetLastError();
        CloseHandle(userToken);
        return static_cast<int>(error);
    }

    void* environment = nullptr;
    if (!CreateEnvironmentBlock(&environment, primaryToken, FALSE)) {
        const auto error = GetLastError();
        CloseHandle(primaryToken);
        CloseHandle(userToken);
        return static_cast<int>(error);
    }

    std::wstring commandLine;
    try {
        for (int index = applicationIndex; index < argc; ++index) {
            if (!commandLine.empty()) {
                commandLine.push_back(L' ');
            }
            commandLine.push_back(L'\"');
            commandLine.append(argv[index]);
            commandLine.push_back(L'\"');
        }
    } catch (...) {
        DestroyEnvironmentBlock(environment);
        CloseHandle(primaryToken);
        CloseHandle(userToken);
        return ERROR_NOT_ENOUGH_MEMORY;
    }

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.lpDesktop = const_cast<wchar_t*>(L"winsta0\\default");
    PROCESS_INFORMATION process{};
    const auto created = CreateProcessAsUserW(
        primaryToken,
        argv[applicationIndex],
        commandLine.data(),
        nullptr,
        nullptr,
        FALSE,
        CREATE_UNICODE_ENVIRONMENT,
        environment,
        nullptr,
        &startup,
        &process);
    auto error = created ? ERROR_SUCCESS : GetLastError();
    if (created) {
        CloseHandle(process.hThread);
        if (waitForExit) {
            if (WaitForSingleObject(process.hProcess, INFINITE) == WAIT_OBJECT_0) {
                DWORD exitCode = ERROR_GEN_FAILURE;
                if (GetExitCodeProcess(process.hProcess, &exitCode)) {
                    error = exitCode;
                } else {
                    error = GetLastError();
                }
            } else {
                error = GetLastError();
            }
        }
        CloseHandle(process.hProcess);
    }
    DestroyEnvironmentBlock(environment);
    CloseHandle(primaryToken);
    CloseHandle(userToken);
    return static_cast<int>(error);
}
