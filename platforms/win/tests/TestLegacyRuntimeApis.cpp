#include "capture/FallbackCaptureBackend.h"
#include "capture/DisplayTopology.h"
#include "support/RuntimeApis.h"

#include <Windows.h>

#include <chrono>
#include <cstdint>
#include <iostream>
#include <limits>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace {

using snipory::core::portable::MemoryBudget;
using xxsnap::win::CaptureBackend;
using xxsnap::win::CaptureBackendKind;
using xxsnap::win::CaptureError;
using xxsnap::win::CaptureErrorCode;
using xxsnap::win::CaptureResult;
using xxsnap::win::DisplayTopologySnapshot;
using xxsnap::win::DisplayDescriptor;
using xxsnap::win::DpiAwarenessMode;
using xxsnap::win::FallbackCaptureBackend;
using xxsnap::win::FrozenDesktop;
using xxsnap::win::MonitorDpi;
using xxsnap::win::ResettableCaptureBackend;
using xxsnap::win::RuntimeApiResolver;
using xxsnap::win::RuntimeApis;
using xxsnap::win::buildDisplayTopologySnapshot;

int failureCount = 0;
int legacyAwarenessCalls = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

BOOL WINAPI fakeSetProcessDpiAware()
{
    ++legacyAwarenessCalls;
    return TRUE;
}

RuntimeApiResolver resolverWithoutModernApis(int& freedModules)
{
    return {
        [](const wchar_t* name) {
            if (std::wstring(name) == L"user32.dll") {
                return reinterpret_cast<HMODULE>(0x701);
            }
            return static_cast<HMODULE>(nullptr);
        },
        [](HMODULE module, const char* name) {
            if (module == reinterpret_cast<HMODULE>(0x701)
                && std::string(name) == "SetProcessDPIAware") {
                return reinterpret_cast<FARPROC>(&fakeSetProcessDpiAware);
            }
            return static_cast<FARPROC>(nullptr);
        },
        [&freedModules](HMODULE) { ++freedModules; },
    };
}

DisplayTopologySnapshot snapshotForLegacyStartup()
{
    std::vector<DisplayDescriptor> displays;
    displays.push_back({
        L"legacy-display",
        {0, 0, 1, 1},
        96U,
        96U,
        DISPLAYCONFIG_ROTATION_IDENTITY,
    });
    const auto result = buildDisplayTopologySnapshot(std::move(displays));
    CHECK(result.hasValue());
    return *result.value();
}

class UnsupportedPreferredBackend final : public ResettableCaptureBackend {
public:
    CaptureResult capture(
        const DisplayTopologySnapshot&,
        MemoryBudget&) noexcept override
    {
        ++captureCalls;
        return CaptureError{CaptureErrorCode::unsupported, E_NOTIMPL};
    }

    void reset() noexcept override
    {
        ++resetCalls;
    }

    int captureCalls = 0;
    int resetCalls = 0;
};

class SuccessfulGdiBackend final : public CaptureBackend {
public:
    CaptureResult capture(
        const DisplayTopologySnapshot& snapshot,
        MemoryBudget&) noexcept override
    {
        ++captureCalls;
        return FrozenDesktop{
            snapshot,
            {},
            std::chrono::steady_clock::time_point{},
        };
    }

    int captureCalls = 0;
};

void testMissingModernApisKeepLegacyStartupAndCaptureUsable()
{
    int freedModules = 0;
    int fallbackCalls = 0;
    legacyAwarenessCalls = 0;
    {
        RuntimeApis runtimeApis(resolverWithoutModernApis(freedModules));

        const auto capabilities = runtimeApis.capabilities();
        CHECK(!capabilities.getDpiForMonitor);
        CHECK(!capabilities.setProcessDpiAwarenessContext);
        CHECK(!capabilities.getDpiForWindow);
        CHECK(!capabilities.getSystemMetricsForDpi);
        CHECK(runtimeApis.initializeProcessDpiAwareness()
            == DpiAwarenessMode::systemAware);
        CHECK(legacyAwarenessCalls == 1);

        const auto dpi = runtimeApis.dpiForMonitor(
            nullptr,
            L"\\\\.\\DISPLAY1",
            [&fallbackCalls](HMONITOR, const std::wstring&)
                -> std::optional<MonitorDpi> {
                ++fallbackCalls;
                return MonitorDpi{120U, 121U};
            });
        CHECK((dpi == MonitorDpi{120U, 121U}));
        CHECK(fallbackCalls == 1);
    }
    CHECK(freedModules == 1);

    UnsupportedPreferredBackend preferred;
    SuccessfulGdiBackend gdi;
    FallbackCaptureBackend capture(preferred, gdi);
    MemoryBudget budget(std::numeric_limits<std::uint64_t>::max());
    const auto topology = snapshotForLegacyStartup();

    const auto result = capture.capture(topology, budget);
    CHECK(std::holds_alternative<FrozenDesktop>(result));
    CHECK(preferred.captureCalls == 0);
    CHECK(preferred.resetCalls == 0);
    CHECK(gdi.captureCalls == 1);
    CHECK(capture.lastBackend() == CaptureBackendKind::fallback);
    const auto* desktop = std::get_if<FrozenDesktop>(&result);
    CHECK(desktop != nullptr);
    CHECK(desktop != nullptr
        && desktop->topology.fingerprint() == topology.fingerprint());
}

} // namespace

int main()
{
    testMissingModernApisKeepLegacyStartupAndCaptureUsable();
    return failureCount == 0 ? 0 : 1;
}
