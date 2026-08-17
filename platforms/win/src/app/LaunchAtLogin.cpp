#include "app/LaunchAtLogin.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <cwchar>
#include <limits>

namespace xxsnap::win {
namespace {

constexpr wchar_t runKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t valueName[] = L"XxSnap";

class RegistryKey final {
public:
    RegistryKey(bool create, REGSAM access) noexcept
    {
        if (create) {
            RegCreateKeyExW(HKEY_CURRENT_USER, runKey, 0, nullptr,
                REG_OPTION_NON_VOLATILE, access, nullptr, &key_, nullptr);
        } else {
            RegOpenKeyExW(HKEY_CURRENT_USER, runKey, 0, access, &key_);
        }
    }

    ~RegistryKey()
    {
        if (key_ != nullptr) RegCloseKey(key_);
    }

    RegistryKey(const RegistryKey&) = delete;
    RegistryKey& operator=(const RegistryKey&) = delete;

    HKEY get() const noexcept { return key_; }

private:
    HKEY key_ = nullptr;
};

} // namespace

std::optional<std::wstring>
SystemLaunchAtLoginRegistry::readCommand() const noexcept
{
    RegistryKey key(false, KEY_QUERY_VALUE);
    if (key.get() == nullptr) return std::nullopt;
    DWORD type = 0;
    DWORD byteCount = 0;
    if (RegQueryValueExW(key.get(), valueName, nullptr, &type, nullptr,
            &byteCount) != ERROR_SUCCESS
        || type != REG_SZ || byteCount < sizeof(wchar_t)) {
        return std::nullopt;
    }
    try {
        std::wstring value(byteCount / sizeof(wchar_t), L'\0');
        if (RegQueryValueExW(key.get(), valueName, nullptr, &type,
                reinterpret_cast<BYTE*>(value.data()), &byteCount)
            != ERROR_SUCCESS) {
            return std::nullopt;
        }
        while (!value.empty() && value.back() == L'\0') value.pop_back();
        return value;
    } catch (...) {
        return std::nullopt;
    }
}

bool SystemLaunchAtLoginRegistry::writeCommand(
    const std::wstring& command) noexcept
{
    if (command.size()
        > (std::numeric_limits<DWORD>::max() / sizeof(wchar_t)) - 1U) {
        return false;
    }
    RegistryKey key(true, KEY_SET_VALUE);
    if (key.get() == nullptr) return false;
    const auto byteCount = static_cast<DWORD>(
        (command.size() + 1U) * sizeof(wchar_t));
    return RegSetValueExW(key.get(), valueName, 0, REG_SZ,
               reinterpret_cast<const BYTE*>(command.c_str()), byteCount)
        == ERROR_SUCCESS;
}

bool SystemLaunchAtLoginRegistry::removeCommand() noexcept
{
    RegistryKey key(false, KEY_SET_VALUE);
    if (key.get() == nullptr) return true;
    const auto result = RegDeleteValueW(key.get(), valueName);
    return result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND;
}

LaunchAtLoginManager::LaunchAtLoginManager(
    LaunchAtLoginRegistry& registry) noexcept
    : registry_(registry)
{
}

std::wstring LaunchAtLoginManager::commandForExecutable(
    const std::wstring& executablePath)
{
    if (executablePath.empty()) return {};
    return L"\"" + executablePath + L"\"";
}

bool LaunchAtLoginManager::isEnabled(
    const std::wstring& executablePath) const noexcept
{
    if (executablePath.empty()) return false;
    const auto command = registry_.readCommand();
    if (!command.has_value()) return false;
    try {
        const auto expected = commandForExecutable(executablePath);
        return _wcsicmp(command->c_str(), expected.c_str()) == 0;
    } catch (...) {
        return false;
    }
}

bool LaunchAtLoginManager::setEnabled(
    bool enabled, const std::wstring& executablePath) noexcept
{
    if (!enabled) return registry_.removeCommand();
    if (executablePath.empty()) return false;
    try {
        return registry_.writeCommand(commandForExecutable(executablePath));
    } catch (...) {
        return false;
    }
}

std::wstring currentExecutablePath()
{
    DWORD capacity = MAX_PATH;
    for (;;) {
        std::wstring path(capacity, L'\0');
        const auto length = GetModuleFileNameW(nullptr, path.data(), capacity);
        if (length == 0) return {};
        if (length < capacity - 1U) {
            path.resize(length);
            return path;
        }
        if (capacity > 32768U / 2U) return {};
        capacity *= 2U;
    }
}

} // namespace xxsnap::win
