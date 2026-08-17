#pragma once

#include <optional>
#include <string>

namespace xxsnap::win {

class LaunchAtLoginRegistry {
public:
    virtual ~LaunchAtLoginRegistry() = default;
    virtual std::optional<std::wstring> readCommand() const noexcept = 0;
    virtual bool writeCommand(const std::wstring& command) noexcept = 0;
    virtual bool removeCommand() noexcept = 0;
};

class SystemLaunchAtLoginRegistry final : public LaunchAtLoginRegistry {
public:
    std::optional<std::wstring> readCommand() const noexcept override;
    bool writeCommand(const std::wstring& command) noexcept override;
    bool removeCommand() noexcept override;
};

class LaunchAtLoginManager final {
public:
    explicit LaunchAtLoginManager(LaunchAtLoginRegistry& registry) noexcept;

    static std::wstring commandForExecutable(
        const std::wstring& executablePath);
    bool isEnabled(const std::wstring& executablePath) const noexcept;
    bool setEnabled(
        bool enabled, const std::wstring& executablePath) noexcept;

private:
    LaunchAtLoginRegistry& registry_;
};

std::wstring currentExecutablePath();

} // namespace xxsnap::win
