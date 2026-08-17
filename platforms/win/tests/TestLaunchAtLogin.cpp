#include "app/LaunchAtLogin.h"

#include <iostream>
#include <optional>
#include <string>

using namespace xxsnap::win;

namespace {

int failureCount = 0;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            std::cerr << __FILE__ << ':' << __LINE__                           \
                      << ": CHECK failed: " #condition << '\n';                \
            ++failureCount;                                                     \
        }                                                                       \
    } while (false)

class FakeLaunchAtLoginRegistry final : public LaunchAtLoginRegistry {
public:
    std::optional<std::wstring> readCommand() const noexcept override
    {
        return command;
    }

    bool writeCommand(const std::wstring& value) noexcept override
    {
        if (failWrites) return false;
        command = value;
        return true;
    }

    bool removeCommand() noexcept override
    {
        if (failWrites) return false;
        command.reset();
        return true;
    }

    std::optional<std::wstring> command;
    bool failWrites = false;
};

void testCommandIsQuotedAndComparedCaseInsensitively()
{
    FakeLaunchAtLoginRegistry registry;
    LaunchAtLoginManager manager(registry);
    const std::wstring executable = L"C:\\Program Files\\XxSnap\\xxsnap.exe";
    CHECK(LaunchAtLoginManager::commandForExecutable(executable)
        == L"\"C:\\Program Files\\XxSnap\\xxsnap.exe\"");
    CHECK(!manager.isEnabled(executable));
    registry.command = L"\"c:\\program files\\xxsnap\\XXSNAP.EXE\"";
    CHECK(manager.isEnabled(executable));
    registry.command = L"\"C:\\Elsewhere\\xxsnap.exe\"";
    CHECK(!manager.isEnabled(executable));
}

void testEnableDisableAndFailures()
{
    FakeLaunchAtLoginRegistry registry;
    LaunchAtLoginManager manager(registry);
    const std::wstring executable = L"C:\\XxSnap\\xxsnap.exe";
    CHECK(manager.setEnabled(true, executable));
    CHECK(registry.command == L"\"C:\\XxSnap\\xxsnap.exe\"");
    CHECK(manager.setEnabled(false, executable));
    CHECK(!registry.command.has_value());
    registry.failWrites = true;
    CHECK(!manager.setEnabled(true, executable));
    CHECK(!manager.setEnabled(false, executable));
    CHECK(!manager.setEnabled(true, L""));
}

} // namespace

int main()
{
    testCommandIsQuotedAndComparedCaseInsensitively();
    testEnableDisableAndFailures();
    return failureCount == 0 ? 0 : 1;
}
