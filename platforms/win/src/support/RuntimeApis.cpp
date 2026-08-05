#include "support/RuntimeApis.h"

#include <utility>

namespace xxsnap::win {
namespace {

constexpr UINT defaultDpi = 96U;
constexpr std::intptr_t perMonitorAwareV2Value = -4;

MonitorDpi normalizedDpi(std::optional<MonitorDpi> dpi) noexcept
{
    if (!dpi.has_value()) {
        return {defaultDpi, defaultDpi};
    }
    return {
        dpi->x == 0U ? defaultDpi : dpi->x,
        dpi->y == 0U ? defaultDpi : dpi->y,
    };
}

std::optional<MonitorDpi> deviceDpi(HMONITOR, const std::wstring& deviceName)
{
    HDC deviceContext = nullptr;
    bool releaseDesktopContext = false;
    if (!deviceName.empty()) {
        deviceContext = CreateDCW(L"DISPLAY", deviceName.c_str(), nullptr, nullptr);
    }
    if (deviceContext == nullptr) {
        deviceContext = GetDC(nullptr);
        releaseDesktopContext = deviceContext != nullptr;
    }
    if (deviceContext == nullptr) {
        return std::nullopt;
    }

    const int dpiX = GetDeviceCaps(deviceContext, LOGPIXELSX);
    const int dpiY = GetDeviceCaps(deviceContext, LOGPIXELSY);
    if (releaseDesktopContext) {
        ReleaseDC(nullptr, deviceContext);
    } else {
        DeleteDC(deviceContext);
    }

    if (dpiX <= 0 || dpiY <= 0) {
        return std::nullopt;
    }
    return MonitorDpi{static_cast<UINT>(dpiX), static_cast<UINT>(dpiY)};
}

} // namespace

RuntimeApiResolver systemRuntimeApiResolver()
{
    RuntimeApiResolver resolver;
    resolver.loadModule = [](const wchar_t* moduleName) { return LoadLibraryW(moduleName); };
    resolver.resolve = [](HMODULE module, const char* functionName) {
        return module == nullptr ? nullptr : GetProcAddress(module, functionName);
    };
    resolver.freeModule = [](HMODULE module) {
        if (module != nullptr) {
            FreeLibrary(module);
        }
    };
    return resolver;
}

RuntimeApis::RuntimeApis()
    : RuntimeApis(systemRuntimeApiResolver())
{
}

RuntimeApis::RuntimeApis(RuntimeApiResolver resolver)
    : resolver_(std::move(resolver))
{
    if (!resolver_.loadModule || !resolver_.resolve) {
        return;
    }

    user32Module_ = resolver_.loadModule(L"user32.dll");
    shcoreModule_ = resolver_.loadModule(L"shcore.dll");

    getDpiForMonitor_ = reinterpret_cast<GetDpiForMonitorFunction>(
        resolver_.resolve(shcoreModule_, "GetDpiForMonitor"));
    setProcessDpiAwarenessContext_ =
        reinterpret_cast<SetProcessDpiAwarenessContextFunction>(
            resolver_.resolve(user32Module_, "SetProcessDpiAwarenessContext"));
    setProcessDpiAware_ = reinterpret_cast<SetProcessDpiAwareFunction>(
        resolver_.resolve(user32Module_, "SetProcessDPIAware"));
    getDpiForWindow_ = resolver_.resolve(user32Module_, "GetDpiForWindow");
    getSystemMetricsForDpi_ = resolver_.resolve(user32Module_, "GetSystemMetricsForDpi");
}

RuntimeApis::~RuntimeApis()
{
    releaseModules();
}

RuntimeApis::RuntimeApis(RuntimeApis&& other) noexcept
    : resolver_(std::move(other.resolver_))
    , user32Module_(std::exchange(other.user32Module_, nullptr))
    , shcoreModule_(std::exchange(other.shcoreModule_, nullptr))
    , getDpiForMonitor_(std::exchange(other.getDpiForMonitor_, nullptr))
    , setProcessDpiAwarenessContext_(
          std::exchange(other.setProcessDpiAwarenessContext_, nullptr))
    , setProcessDpiAware_(std::exchange(other.setProcessDpiAware_, nullptr))
    , getDpiForWindow_(std::exchange(other.getDpiForWindow_, nullptr))
    , getSystemMetricsForDpi_(std::exchange(other.getSystemMetricsForDpi_, nullptr))
{
}

RuntimeApis& RuntimeApis::operator=(RuntimeApis&& other) noexcept
{
    if (this == &other) {
        return *this;
    }

    releaseModules();
    resolver_ = std::move(other.resolver_);
    user32Module_ = std::exchange(other.user32Module_, nullptr);
    shcoreModule_ = std::exchange(other.shcoreModule_, nullptr);
    getDpiForMonitor_ = std::exchange(other.getDpiForMonitor_, nullptr);
    setProcessDpiAwarenessContext_ =
        std::exchange(other.setProcessDpiAwarenessContext_, nullptr);
    setProcessDpiAware_ = std::exchange(other.setProcessDpiAware_, nullptr);
    getDpiForWindow_ = std::exchange(other.getDpiForWindow_, nullptr);
    getSystemMetricsForDpi_ = std::exchange(other.getSystemMetricsForDpi_, nullptr);
    return *this;
}

RuntimeApiCapabilities RuntimeApis::capabilities() const noexcept
{
    return {
        getDpiForMonitor_ != nullptr,
        setProcessDpiAwarenessContext_ != nullptr,
        getDpiForWindow_ != nullptr,
        getSystemMetricsForDpi_ != nullptr,
    };
}

DpiAwarenessMode RuntimeApis::initializeProcessDpiAwareness() const noexcept
{
    if (setProcessDpiAwarenessContext_ != nullptr) {
        const auto context = reinterpret_cast<HANDLE>(perMonitorAwareV2Value);
        if (setProcessDpiAwarenessContext_(context) != FALSE) {
            return DpiAwarenessMode::perMonitorV2;
        }
    }
    if (setProcessDpiAware_ != nullptr && setProcessDpiAware_() != FALSE) {
        return DpiAwarenessMode::systemAware;
    }
    return DpiAwarenessMode::unavailable;
}

MonitorDpi RuntimeApis::dpiForMonitor(
    HMONITOR monitor,
    const std::wstring& deviceName,
    const FallbackDpiProvider& fallbackProvider) const
{
    if (getDpiForMonitor_ != nullptr) {
        UINT dpiX = 0U;
        UINT dpiY = 0U;
        if (SUCCEEDED(getDpiForMonitor_(monitor, 0, &dpiX, &dpiY))
            && dpiX != 0U && dpiY != 0U) {
            return {dpiX, dpiY};
        }
    }
    return normalizedDpi(
        fallbackProvider ? fallbackProvider(monitor, deviceName) : std::nullopt);
}

MonitorDpi RuntimeApis::dpiForMonitor(
    HMONITOR monitor,
    const std::wstring& deviceName) const
{
    return dpiForMonitor(monitor, deviceName, deviceDpi);
}

void RuntimeApis::releaseModules() noexcept
{
    if (resolver_.freeModule) {
        if (shcoreModule_ != nullptr) {
            resolver_.freeModule(shcoreModule_);
        }
        if (user32Module_ != nullptr) {
            resolver_.freeModule(user32Module_);
        }
    }
    shcoreModule_ = nullptr;
    user32Module_ = nullptr;
}

} // namespace xxsnap::win
