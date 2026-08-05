#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif
#include <Windows.h>

#include <functional>
#include <optional>
#include <string>

namespace xxsnap::win {

struct MonitorDpi {
    UINT x;
    UINT y;
};

inline bool operator==(MonitorDpi lhs, MonitorDpi rhs) noexcept
{
    return lhs.x == rhs.x && lhs.y == rhs.y;
}

inline bool operator!=(MonitorDpi lhs, MonitorDpi rhs) noexcept
{
    return !(lhs == rhs);
}

struct RuntimeApiCapabilities {
    bool getDpiForMonitor;
    bool setProcessDpiAwarenessContext;
    bool getDpiForWindow;
    bool getSystemMetricsForDpi;
};

enum class DpiAwarenessMode {
    unavailable,
    systemAware,
    perMonitorV2,
};

struct RuntimeApiResolver {
    std::function<HMODULE(const wchar_t*)> loadModule;
    std::function<FARPROC(HMODULE, const char*)> resolve;
    std::function<void(HMODULE)> freeModule;
};

using FallbackDpiProvider =
    std::function<std::optional<MonitorDpi>(HMONITOR, const std::wstring&)>;

RuntimeApiResolver systemRuntimeApiResolver();

class RuntimeApis final {
public:
    RuntimeApis();
    explicit RuntimeApis(RuntimeApiResolver resolver);
    ~RuntimeApis();

    RuntimeApis(const RuntimeApis&) = delete;
    RuntimeApis& operator=(const RuntimeApis&) = delete;
    RuntimeApis(RuntimeApis&& other) noexcept;
    RuntimeApis& operator=(RuntimeApis&& other) noexcept;

    RuntimeApiCapabilities capabilities() const noexcept;
    DpiAwarenessMode initializeProcessDpiAwareness() const noexcept;

    MonitorDpi dpiForMonitor(
        HMONITOR monitor,
        const std::wstring& deviceName,
        const FallbackDpiProvider& fallbackProvider) const;
    MonitorDpi dpiForMonitor(HMONITOR monitor, const std::wstring& deviceName) const;

private:
    using GetDpiForMonitorFunction = HRESULT(WINAPI*)(HMONITOR, int, UINT*, UINT*);
    using SetProcessDpiAwarenessContextFunction = BOOL(WINAPI*)(HANDLE);
    using SetProcessDpiAwareFunction = BOOL(WINAPI*)();

    void releaseModules() noexcept;

    RuntimeApiResolver resolver_;
    HMODULE user32Module_ = nullptr;
    HMODULE shcoreModule_ = nullptr;
    GetDpiForMonitorFunction getDpiForMonitor_ = nullptr;
    SetProcessDpiAwarenessContextFunction setProcessDpiAwarenessContext_ = nullptr;
    SetProcessDpiAwareFunction setProcessDpiAware_ = nullptr;
    FARPROC getDpiForWindow_ = nullptr;
    FARPROC getSystemMetricsForDpi_ = nullptr;
};

} // namespace xxsnap::win
