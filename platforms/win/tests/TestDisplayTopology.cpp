#include "capture/DisplayTopology.h"
#include "support/RuntimeApis.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <new>
#include <optional>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

namespace {

using namespace xxsnap::win;

int failureCount = 0;
int legacyAwarenessCalls = 0;
int modernAwarenessCalls = 0;
int modernDpiCalls = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

std::vector<DisplayDescriptor> threeDisplayFixture()
{
    return {
        {L"\\\\.\\DISPLAY1", {-1920, 0, 1920, 1080}, 96U, 96U,
         DISPLAYCONFIG_ROTATION_IDENTITY},
        {L"\\\\.\\DISPLAY2", {0, 0, 2560, 1440}, 144U, 144U,
         DISPLAYCONFIG_ROTATION_ROTATE90},
        {L"\\\\.\\DISPLAY3", {2560, -400, 1440, 2560}, 192U, 192U,
         DISPLAYCONFIG_ROTATION_ROTATE270},
    };
}

BOOL WINAPI fakeSetProcessDpiAware()
{
    ++legacyAwarenessCalls;
    return TRUE;
}

BOOL WINAPI fakeSetProcessDpiAwarenessContext(HANDLE context)
{
    ++modernAwarenessCalls;
    CHECK(context == reinterpret_cast<HANDLE>(static_cast<std::intptr_t>(-4)));
    return TRUE;
}

HRESULT WINAPI fakeGetDpiForMonitor(HMONITOR, int dpiType, UINT* dpiX, UINT* dpiY)
{
    ++modernDpiCalls;
    CHECK(dpiType == 0);
    *dpiX = 144U;
    *dpiY = 145U;
    return S_OK;
}

HRESULT WINAPI fakeTopologyDpi(HMONITOR monitor, int, UINT* dpiX, UINT* dpiY)
{
    const auto monitorId = reinterpret_cast<std::uintptr_t>(monitor);
    *dpiX = monitorId == 1U ? 96U : monitorId == 2U ? 144U : 192U;
    *dpiY = *dpiX;
    return S_OK;
}

HRESULT WINAPI throwingTopologyDpi(HMONITOR, int, UINT*, UINT*)
{
    throw std::runtime_error("injected DPI failure");
}

HRESULT WINAPI allocationFailingTopologyDpi(HMONITOR, int, UINT*, UINT*)
{
    throw std::bad_alloc();
}

RuntimeApiResolver resolverWithoutModernApis(int& freeCount)
{
    RuntimeApiResolver resolver;
    resolver.loadModule = [](const wchar_t* moduleName) {
        return std::wcscmp(moduleName, L"user32.dll") == 0
            ? reinterpret_cast<HMODULE>(static_cast<std::uintptr_t>(1U))
            : reinterpret_cast<HMODULE>(static_cast<std::uintptr_t>(2U));
    };
    resolver.resolve = [](HMODULE, const char* functionName) -> FARPROC {
        if (std::strcmp(functionName, "SetProcessDPIAware") == 0) {
            return reinterpret_cast<FARPROC>(&fakeSetProcessDpiAware);
        }
        return nullptr;
    };
    resolver.freeModule = [&freeCount](HMODULE) { ++freeCount; };
    return resolver;
}

RuntimeApiResolver resolverWithModernApis(int& freeCount)
{
    auto resolver = resolverWithoutModernApis(freeCount);
    resolver.resolve = [](HMODULE, const char* functionName) -> FARPROC {
        if (std::strcmp(functionName, "GetDpiForMonitor") == 0) {
            return reinterpret_cast<FARPROC>(&fakeGetDpiForMonitor);
        }
        if (std::strcmp(functionName, "SetProcessDpiAwarenessContext") == 0) {
            return reinterpret_cast<FARPROC>(&fakeSetProcessDpiAwarenessContext);
        }
        if (std::strcmp(functionName, "GetDpiForWindow") == 0
            || std::strcmp(functionName, "GetSystemMetricsForDpi") == 0) {
            return reinterpret_cast<FARPROC>(&fakeSetProcessDpiAware);
        }
        return nullptr;
    };
    return resolver;
}

RuntimeApiResolver resolverWithTopologyDpi(int& freeCount, FARPROC dpiFunction)
{
    auto resolver = resolverWithoutModernApis(freeCount);
    resolver.resolve = [dpiFunction](HMODULE, const char* functionName) -> FARPROC {
        return std::strcmp(functionName, "GetDpiForMonitor") == 0
            ? dpiFunction
            : nullptr;
    };
    return resolver;
}

void testSnapshotPreservesDescriptorsAndBuildsVirtualBounds()
{
    const auto displays = threeDisplayFixture();
    const auto result = buildDisplayTopologySnapshot(displays);

    CHECK(result.hasValue());
    CHECK(result.error() == nullptr);
    CHECK(result.value()->displays() == displays);
    CHECK((result.value()->virtualBounds() == PixelRect{-1920, -400, 5920, 2560}));
    CHECK(result.value()->fingerprint()
        == buildDisplayTopologySnapshot(displays).value()->fingerprint());
}

void testSnapshotExposesOnlyImmutableState()
{
    static_assert(std::is_copy_constructible_v<DisplayTopologySnapshot>);
    static_assert(std::is_move_constructible_v<DisplayTopologySnapshot>);
    static_assert(std::is_nothrow_move_constructible_v<DisplayTopologySnapshot>);
    static_assert(!std::is_copy_assignable_v<DisplayTopologySnapshot>);
    static_assert(!std::is_move_assignable_v<DisplayTopologySnapshot>);
    static_assert(!std::is_aggregate_v<DisplayTopologySnapshot>);
    static_assert(std::is_same_v<
        decltype(std::declval<const DisplayTopologySnapshot&>().displays()),
        const std::vector<DisplayDescriptor>&>);
    static_assert(std::is_same_v<
        decltype(std::declval<const DisplayTopologySnapshot&>().virtualBounds()),
        PixelRect>);
    static_assert(std::is_same_v<
        decltype(std::declval<const DisplayTopologySnapshot&>().fingerprint()),
        std::uint64_t>);

    const auto result = buildDisplayTopologySnapshot(threeDisplayFixture());
    CHECK(result.hasValue());
    const auto fingerprint = result.value()->fingerprint();
    const auto* const originalDisplaysAddress = &result.value()->displays();
    const DisplayTopologySnapshot copied(*result.value());
    CHECK(&copied.displays() == originalDisplaysAddress);
    CHECK(copied.displays() == result.value()->displays());
    CHECK(copied.virtualBounds() == result.value()->virtualBounds());
    CHECK(copied.fingerprint() == fingerprint);

    DisplayTopologySnapshot moveSource(copied);
    const DisplayTopologySnapshot moved(std::move(moveSource));
    CHECK(&moved.displays() == originalDisplaysAddress);
    CHECK(&moveSource.displays() == originalDisplaysAddress);
    CHECK(moved.displays() == result.value()->displays());
    CHECK(moved.fingerprint() == fingerprint);
    CHECK(moveSource.displays() == result.value()->displays());
    CHECK(moveSource.fingerprint() == fingerprint);
}

void testVirtualBoundsStandardizeAndSaturate()
{
    const auto maximum = std::numeric_limits<std::int64_t>::max();
    const std::vector<DisplayDescriptor> displays{
        {L"A", {maximum, 20, -10, -5}, 96U, 96U, DISPLAYCONFIG_ROTATION_IDENTITY},
        {L"B", {-20, -30, 5, 5}, 96U, 96U, DISPLAYCONFIG_ROTATION_IDENTITY},
    };

    const auto result = buildDisplayTopologySnapshot(displays);

    CHECK(result.hasValue());
    CHECK((result.value()->virtualBounds()
        == PixelRect{-20, -30, maximum, 50}));
    CHECK(result.value()->displays() == displays);
}

void testFingerprintIsOrderIndependentAndSensitiveToEveryField()
{
    const auto fixture = threeDisplayFixture();
    const auto baseline = buildDisplayTopologySnapshot(fixture);
    CHECK(baseline.hasValue());

    auto reordered = fixture;
    std::reverse(reordered.begin(), reordered.end());
    const auto reorderedResult = buildDisplayTopologySnapshot(reordered);
    CHECK(reorderedResult.hasValue());
    CHECK(reorderedResult.value()->fingerprint() == baseline.value()->fingerprint());

    const auto fingerprintChanges = [&](auto mutation) {
        auto changed = fixture;
        mutation(changed.front());
        const auto changedResult = buildDisplayTopologySnapshot(std::move(changed));
        CHECK(changedResult.hasValue());
        CHECK(changedResult.value()->fingerprint() != baseline.value()->fingerprint());
    };

    fingerprintChanges([](DisplayDescriptor& display) { display.deviceName += L"x"; });
    fingerprintChanges([](DisplayDescriptor& display) { ++display.pixelBounds.x; });
    fingerprintChanges([](DisplayDescriptor& display) { ++display.pixelBounds.y; });
    fingerprintChanges([](DisplayDescriptor& display) { ++display.pixelBounds.width; });
    fingerprintChanges([](DisplayDescriptor& display) { ++display.pixelBounds.height; });
    fingerprintChanges([](DisplayDescriptor& display) { ++display.dpiX; });
    fingerprintChanges([](DisplayDescriptor& display) { ++display.dpiY; });
    fingerprintChanges([](DisplayDescriptor& display) {
        display.rotation = DISPLAYCONFIG_ROTATION_ROTATE180;
    });
}

void testEmptyTopologyIsAnError()
{
    const auto result = buildDisplayTopologySnapshot({});
    CHECK(!result.hasValue());
    CHECK(result.value() == nullptr);
    CHECK(result.error() != nullptr);
    CHECK(result.error()->code == TopologyErrorCode::noDisplays);
    CHECK(result.error()->systemError == ERROR_SUCCESS);
}

void testTopologyResultAlwaysContainsExactlyOneAlternative()
{
    static_assert(!std::is_default_constructible_v<DisplayTopologyResult>);
    const auto success = buildDisplayTopologySnapshot(threeDisplayFixture());
    const auto failure = buildDisplayTopologySnapshot({});
    CHECK(success.hasValue());
    CHECK(success.value() != nullptr);
    CHECK(success.error() == nullptr);
    CHECK(!failure.hasValue());
    CHECK(failure.value() == nullptr);
    CHECK(failure.error() != nullptr);
}

void testDpiConversionsUsePerDisplayDpiAndNearestRounding()
{
    for (const auto dpi : {96U, 144U, 192U}) {
        for (const auto dips : {-96LL, -48LL, 0LL, 48LL, 96LL}) {
            const auto pixels = dipsToPhysicalPixels(dips, dpi);
            CHECK(physicalPixelsToDips(pixels, dpi) == dips);
        }
    }

    CHECK(dipsToPhysicalPixels(1, 144U) == 2);
    CHECK(dipsToPhysicalPixels(-1, 144U) == -2);
    CHECK(physicalPixelsToDips(3, 192U) == 2);
    CHECK(physicalPixelsToDips(-3, 192U) == -2);
    CHECK(dipsToPhysicalPixels(11, 0U) == 11);
    CHECK(physicalPixelsToDips(-11, 0U) == -11);
    CHECK(dipsToPhysicalPixels(std::numeric_limits<std::int64_t>::max(), 192U)
        == std::numeric_limits<std::int64_t>::max());
}

void testMissingModernApisUseSafeFallbacks()
{
    int freeCount = 0;
    int fallbackCalls = 0;
    legacyAwarenessCalls = 0;
    {
        RuntimeApis apis(resolverWithoutModernApis(freeCount));
        const auto capabilities = apis.capabilities();
        CHECK(!capabilities.getDpiForMonitor);
        CHECK(!capabilities.setProcessDpiAwarenessContext);
        CHECK(!capabilities.getDpiForWindow);
        CHECK(!capabilities.getSystemMetricsForDpi);

        const auto dpi = apis.dpiForMonitor(
            nullptr,
            L"\\\\.\\DISPLAY1",
            [&fallbackCalls](HMONITOR, const std::wstring&) -> std::optional<MonitorDpi> {
                ++fallbackCalls;
                return MonitorDpi{120U, 121U};
            });
        CHECK((dpi == MonitorDpi{120U, 121U}));
        CHECK(fallbackCalls == 1);
        CHECK(apis.initializeProcessDpiAwareness() == DpiAwarenessMode::systemAware);
        CHECK(legacyAwarenessCalls == 1);

        const auto defaultDpi = apis.dpiForMonitor(
            nullptr,
            L"missing",
            [](HMONITOR, const std::wstring&) -> std::optional<MonitorDpi> {
                return std::nullopt;
            });
        CHECK((defaultDpi == MonitorDpi{96U, 96U}));
    }
    CHECK(freeCount == 2);
}

void testModernApisAreResolvedAndPreferred()
{
    int freeCount = 0;
    int fallbackCalls = 0;
    modernAwarenessCalls = 0;
    modernDpiCalls = 0;
    RuntimeApis apis(resolverWithModernApis(freeCount));

    const auto capabilities = apis.capabilities();
    CHECK(capabilities.getDpiForMonitor);
    CHECK(capabilities.setProcessDpiAwarenessContext);
    CHECK(capabilities.getDpiForWindow);
    CHECK(capabilities.getSystemMetricsForDpi);

    const auto dpi = apis.dpiForMonitor(
        nullptr,
        L"unused",
        [&fallbackCalls](HMONITOR, const std::wstring&) -> std::optional<MonitorDpi> {
            ++fallbackCalls;
            return MonitorDpi{96U, 96U};
        });
    CHECK((dpi == MonitorDpi{144U, 145U}));
    CHECK(modernDpiCalls == 1);
    CHECK(fallbackCalls == 0);
    CHECK(apis.initializeProcessDpiAwareness() == DpiAwarenessMode::perMonitorV2);
    CHECK(modernAwarenessCalls == 1);
}

void testRuntimeApisMoveOwnershipWithoutDoubleFree()
{
    static_assert(!std::is_copy_constructible_v<RuntimeApis>);
    static_assert(!std::is_copy_assignable_v<RuntimeApis>);
    static_assert(std::is_nothrow_move_constructible_v<RuntimeApis>);
    static_assert(std::is_nothrow_move_assignable_v<RuntimeApis>);

    int freeCount = 0;
    {
        RuntimeApis first(resolverWithoutModernApis(freeCount));
        RuntimeApis second(std::move(first));
        RuntimeApis third(resolverWithoutModernApis(freeCount));
        third = std::move(second);
    }
    CHECK(freeCount == 4);
}

RuntimeApis fakeRuntimeApisForTopologyFailure(int& freeCount)
{
    return RuntimeApis(resolverWithoutModernApis(freeCount));
}

void testDisplayConfigBufferSizeFailureIsSystemFailure()
{
    int freeCount = 0;
    auto runtimeApis = fakeRuntimeApisForTopologyFailure(freeCount);
    DisplayConfigApis displayConfigApis;
    displayConfigApis.getDisplayConfigBufferSizes =
        [](UINT32, UINT32*, UINT32*) { return static_cast<LONG>(ERROR_NOT_SUPPORTED); };

    const auto result = snapshotDisplayTopology(runtimeApis, displayConfigApis);

    CHECK(!result.hasValue());
    CHECK(result.error() != nullptr);
    CHECK(result.error()->code == TopologyErrorCode::systemFailure);
    CHECK(result.error()->systemError == ERROR_NOT_SUPPORTED);
}

void testQueryDisplayConfigFailureIsSystemFailure()
{
    int freeCount = 0;
    auto runtimeApis = fakeRuntimeApisForTopologyFailure(freeCount);
    DisplayConfigApis displayConfigApis;
    displayConfigApis.getDisplayConfigBufferSizes =
        [](UINT32, UINT32* pathCount, UINT32* modeCount) {
            *pathCount = 1U;
            *modeCount = 1U;
            return static_cast<LONG>(ERROR_SUCCESS);
        };
    displayConfigApis.queryDisplayConfig =
        [](UINT32,
           UINT32*,
           DISPLAYCONFIG_PATH_INFO*,
           UINT32*,
           DISPLAYCONFIG_MODE_INFO*,
           DISPLAYCONFIG_TOPOLOGY_ID*) {
            return static_cast<LONG>(ERROR_ACCESS_DENIED);
        };

    const auto result = snapshotDisplayTopology(runtimeApis, displayConfigApis);

    CHECK(!result.hasValue());
    CHECK(result.error() != nullptr);
    CHECK(result.error()->code == TopologyErrorCode::systemFailure);
    CHECK(result.error()->systemError == ERROR_ACCESS_DENIED);
}

void testDisplayConfigDeviceInfoFailureIsSystemFailure()
{
    int freeCount = 0;
    auto runtimeApis = fakeRuntimeApisForTopologyFailure(freeCount);
    DisplayConfigApis displayConfigApis;
    displayConfigApis.getDisplayConfigBufferSizes =
        [](UINT32, UINT32* pathCount, UINT32* modeCount) {
            *pathCount = 1U;
            *modeCount = 1U;
            return static_cast<LONG>(ERROR_SUCCESS);
        };
    displayConfigApis.queryDisplayConfig =
        [](UINT32,
           UINT32* pathCount,
           DISPLAYCONFIG_PATH_INFO* paths,
           UINT32* modeCount,
           DISPLAYCONFIG_MODE_INFO*,
           DISPLAYCONFIG_TOPOLOGY_ID*) {
            CHECK(*pathCount == 1U);
            CHECK(*modeCount == 1U);
            paths[0].flags = DISPLAYCONFIG_PATH_ACTIVE;
            paths[0].sourceInfo.id = 7U;
            paths[0].targetInfo.rotation = DISPLAYCONFIG_ROTATION_ROTATE90;
            return static_cast<LONG>(ERROR_SUCCESS);
        };
    displayConfigApis.displayConfigGetDeviceInfo =
        [](DISPLAYCONFIG_DEVICE_INFO_HEADER*) {
            return static_cast<LONG>(ERROR_INVALID_DATA);
        };

    const auto result = snapshotDisplayTopology(runtimeApis, displayConfigApis);

    CHECK(!result.hasValue());
    CHECK(result.error() != nullptr);
    CHECK(result.error()->code == TopologyErrorCode::systemFailure);
    CHECK(result.error()->systemError == ERROR_INVALID_DATA);
}

DisplayConfigApis emptyDisplayConfigApis()
{
    DisplayConfigApis apis;
    apis.getDisplayConfigBufferSizes =
        [](UINT32, UINT32* pathCount, UINT32* modeCount) {
            *pathCount = 0U;
            *modeCount = 0U;
            return static_cast<LONG>(ERROR_SUCCESS);
        };
    apis.queryDisplayConfig =
        [](UINT32,
           UINT32*,
           DISPLAYCONFIG_PATH_INFO*,
           UINT32*,
           DISPLAYCONFIG_MODE_INFO*,
           DISPLAYCONFIG_TOPOLOGY_ID*) {
            return static_cast<LONG>(ERROR_SUCCESS);
        };
    return apis;
}

MonitorEnumerationApis threeMonitorEnumerationApis()
{
    MonitorEnumerationApis apis;
    apis.enumDisplayMonitors =
        [](HDC, LPCRECT, MONITORENUMPROC callback, LPARAM context) {
            RECT ignoredBounds{};
            for (std::uintptr_t monitorId = 1U; monitorId <= 3U; ++monitorId) {
                const auto monitor = reinterpret_cast<HMONITOR>(monitorId);
                if (callback(monitor, nullptr, &ignoredBounds, context) == FALSE) {
                    return FALSE;
                }
            }
            return TRUE;
        };
    apis.getMonitorInfo = [](HMONITOR monitor, LPMONITORINFO monitorInfo) {
        const auto monitorId = reinterpret_cast<std::uintptr_t>(monitor);
        auto* extendedInfo = reinterpret_cast<MONITORINFOEXW*>(monitorInfo);
        const wchar_t* deviceName = L"\\\\.\\DISPLAY3";
        RECT bounds{200, -50, 300, 150};
        if (monitorId == 1U) {
            deviceName = L"\\\\.\\DISPLAY1";
            bounds = {-100, 0, 0, 100};
        } else if (monitorId == 2U) {
            deviceName = L"\\\\.\\DISPLAY2";
            bounds = {0, 0, 200, 100};
        }
        extendedInfo->rcMonitor = bounds;
        return wcscpy_s(
                   extendedInfo->szDevice, CCHDEVICENAME, deviceName)
                == 0
            ? TRUE
            : FALSE;
    };
    return apis;
}

DisplayConfigApis rotationDisplayConfigApis()
{
    DisplayConfigApis apis;
    apis.getDisplayConfigBufferSizes =
        [](UINT32, UINT32* pathCount, UINT32* modeCount) {
            *pathCount = 5U;
            *modeCount = 0U;
            return static_cast<LONG>(ERROR_SUCCESS);
        };
    apis.queryDisplayConfig =
        [](UINT32,
           UINT32* pathCount,
           DISPLAYCONFIG_PATH_INFO* paths,
           UINT32*,
           DISPLAYCONFIG_MODE_INFO*,
           DISPLAYCONFIG_TOPOLOGY_ID*) {
            CHECK(*pathCount == 5U);
            const std::array<UINT32, 5> sourceIds{1U, 2U, 3U, 3U, 99U};
            const std::array<DISPLAYCONFIG_ROTATION, 5> rotations{
                DISPLAYCONFIG_ROTATION_ROTATE90,
                static_cast<DISPLAYCONFIG_ROTATION>(99),
                DISPLAYCONFIG_ROTATION_ROTATE90,
                DISPLAYCONFIG_ROTATION_ROTATE270,
                DISPLAYCONFIG_ROTATION_ROTATE180,
            };
            for (std::size_t index = 0U; index < sourceIds.size(); ++index) {
                paths[index].flags = index == 4U ? 0U : DISPLAYCONFIG_PATH_ACTIVE;
                paths[index].sourceInfo.id = sourceIds[index];
                paths[index].targetInfo.rotation = rotations[index];
            }
            return static_cast<LONG>(ERROR_SUCCESS);
        };
    apis.displayConfigGetDeviceInfo =
        [](DISPLAYCONFIG_DEVICE_INFO_HEADER* header) {
            auto* sourceName =
                reinterpret_cast<DISPLAYCONFIG_SOURCE_DEVICE_NAME*>(header);
            const wchar_t* name = sourceName->header.id == 1U
                ? L"\\\\.\\DISPLAY1"
                : sourceName->header.id == 2U
                ? L"\\\\.\\DISPLAY2"
                : L"\\\\.\\DISPLAY3";
            return wcscpy_s(
                       sourceName->viewGdiDeviceName, CCHDEVICENAME, name)
                    == 0
                ? static_cast<LONG>(ERROR_SUCCESS)
                : static_cast<LONG>(ERROR_INVALID_DATA);
        };
    return apis;
}

void testInjectedEnumerationBuildsDescriptorsAndResolvesRotationSafely()
{
    int freeCount = 0;
    RuntimeApis runtimeApis(resolverWithTopologyDpi(
        freeCount, reinterpret_cast<FARPROC>(&fakeTopologyDpi)));
    const auto result = snapshotDisplayTopology(
        runtimeApis, rotationDisplayConfigApis(), threeMonitorEnumerationApis());

    CHECK(result.hasValue());
    CHECK(result.error() == nullptr);
    CHECK((result.value()->virtualBounds() == PixelRect{-100, -50, 400, 200}));
    CHECK(result.value()->displays().size() == 3U);
    CHECK(result.value()->displays()[0].deviceName == L"\\\\.\\DISPLAY1");
    CHECK(result.value()->displays()[0].dpiX == 96U);
    CHECK(result.value()->displays()[0].rotation == DISPLAYCONFIG_ROTATION_ROTATE90);
    CHECK(result.value()->displays()[1].dpiX == 144U);
    CHECK(result.value()->displays()[1].rotation == DISPLAYCONFIG_ROTATION_IDENTITY);
    CHECK(result.value()->displays()[2].dpiX == 192U);
    CHECK(result.value()->displays()[2].rotation == DISPLAYCONFIG_ROTATION_IDENTITY);
}

void testGetMonitorInfoFailureIsSystemFailure()
{
    int freeCount = 0;
    auto runtimeApis = fakeRuntimeApisForTopologyFailure(freeCount);
    auto monitorApis = threeMonitorEnumerationApis();
    monitorApis.getMonitorInfo = [](HMONITOR, LPMONITORINFO) {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    };

    const auto result = snapshotDisplayTopology(
        runtimeApis, emptyDisplayConfigApis(), monitorApis);

    CHECK(!result.hasValue());
    CHECK(result.error() != nullptr);
    CHECK(result.error()->code == TopologyErrorCode::systemFailure);
    CHECK(result.error()->systemError == ERROR_INVALID_HANDLE);
}

void testMonitorEnumeratorFailureIsSystemFailure()
{
    int freeCount = 0;
    auto runtimeApis = fakeRuntimeApisForTopologyFailure(freeCount);
    MonitorEnumerationApis monitorApis;
    monitorApis.enumDisplayMonitors =
        [](HDC, LPCRECT, MONITORENUMPROC, LPARAM) {
            SetLastError(ERROR_ACCESS_DENIED);
            return FALSE;
        };

    const auto result = snapshotDisplayTopology(
        runtimeApis, emptyDisplayConfigApis(), monitorApis);

    CHECK(!result.hasValue());
    CHECK(result.error() != nullptr);
    CHECK(result.error()->code == TopologyErrorCode::systemFailure);
    CHECK(result.error()->systemError == ERROR_ACCESS_DENIED);
}

void testCallbackRuntimeExceptionIsContained()
{
    int freeCount = 0;
    RuntimeApis runtimeApis(resolverWithTopologyDpi(
        freeCount, reinterpret_cast<FARPROC>(&throwingTopologyDpi)));

    const auto result = snapshotDisplayTopology(
        runtimeApis, emptyDisplayConfigApis(), threeMonitorEnumerationApis());

    CHECK(!result.hasValue());
    CHECK(result.error() != nullptr);
    CHECK(result.error()->systemError == ERROR_UNHANDLED_EXCEPTION);
}

void testCallbackAllocationFailureIsContained()
{
    int freeCount = 0;
    RuntimeApis runtimeApis(resolverWithTopologyDpi(
        freeCount, reinterpret_cast<FARPROC>(&allocationFailingTopologyDpi)));

    const auto result = snapshotDisplayTopology(
        runtimeApis, emptyDisplayConfigApis(), threeMonitorEnumerationApis());

    CHECK(!result.hasValue());
    CHECK(result.error() != nullptr);
    CHECK(result.error()->systemError == ERROR_NOT_ENOUGH_MEMORY);
}

void testThrowingGetMonitorInfoIsContained()
{
    int freeCount = 0;
    auto runtimeApis = fakeRuntimeApisForTopologyFailure(freeCount);
    auto monitorApis = threeMonitorEnumerationApis();
    monitorApis.getMonitorInfo = [](HMONITOR, LPMONITORINFO) -> BOOL {
        throw std::runtime_error("injected monitor info failure");
    };

    const auto result = snapshotDisplayTopology(
        runtimeApis, emptyDisplayConfigApis(), monitorApis);

    CHECK(!result.hasValue());
    CHECK(result.error() != nullptr);
    CHECK(result.error()->systemError == ERROR_UNHANDLED_EXCEPTION);
}

void testDisplayConfigRetriesInsufficientBufferThenSucceeds()
{
    int freeCount = 0;
    auto runtimeApis = fakeRuntimeApisForTopologyFailure(freeCount);
    int queryCalls = 0;
    auto displayConfigApis = emptyDisplayConfigApis();
    displayConfigApis.queryDisplayConfig =
        [&queryCalls](UINT32,
                      UINT32*,
                      DISPLAYCONFIG_PATH_INFO*,
                      UINT32*,
                      DISPLAYCONFIG_MODE_INFO*,
                      DISPLAYCONFIG_TOPOLOGY_ID*) {
            ++queryCalls;
            return static_cast<LONG>(
                queryCalls < 3 ? ERROR_INSUFFICIENT_BUFFER : ERROR_SUCCESS);
        };
    MonitorEnumerationApis monitorApis;
    monitorApis.enumDisplayMonitors =
        [](HDC, LPCRECT, MONITORENUMPROC, LPARAM) { return TRUE; };

    const auto result = snapshotDisplayTopology(
        runtimeApis, displayConfigApis, monitorApis);

    CHECK(queryCalls == 3);
    CHECK(!result.hasValue());
    CHECK(result.error() != nullptr);
    CHECK(result.error()->code == TopologyErrorCode::noDisplays);
}

void testDisplayConfigInsufficientBufferExhaustionIsSystemFailure()
{
    int freeCount = 0;
    auto runtimeApis = fakeRuntimeApisForTopologyFailure(freeCount);
    int queryCalls = 0;
    int monitorCalls = 0;
    auto displayConfigApis = emptyDisplayConfigApis();
    displayConfigApis.queryDisplayConfig =
        [&queryCalls](UINT32,
                      UINT32*,
                      DISPLAYCONFIG_PATH_INFO*,
                      UINT32*,
                      DISPLAYCONFIG_MODE_INFO*,
                      DISPLAYCONFIG_TOPOLOGY_ID*) {
            ++queryCalls;
            return static_cast<LONG>(ERROR_INSUFFICIENT_BUFFER);
        };
    MonitorEnumerationApis monitorApis;
    monitorApis.enumDisplayMonitors =
        [&monitorCalls](HDC, LPCRECT, MONITORENUMPROC, LPARAM) {
            ++monitorCalls;
            return TRUE;
        };

    const auto result = snapshotDisplayTopology(
        runtimeApis, displayConfigApis, monitorApis);

    CHECK(queryCalls == 3);
    CHECK(monitorCalls == 0);
    CHECK(!result.hasValue());
    CHECK(result.error() != nullptr);
    CHECK(result.error()->code == TopologyErrorCode::systemFailure);
    CHECK(result.error()->systemError == ERROR_INSUFFICIENT_BUFFER);
}

int runLiveTopologySmoke()
{
    RuntimeApis apis;
    const auto awareness = apis.initializeProcessDpiAwareness();
    const auto result = snapshotDisplayTopology(apis);
    if (!result.hasValue()) {
        std::cerr << "live topology unavailable: error="
                  << static_cast<int>(result.error()->code)
                  << " system=" << result.error()->systemError << '\n';
        return 2;
    }

    std::cout << "live topology: displays=" << result.value()->displays().size()
              << " awareness=" << static_cast<int>(awareness)
              << " fingerprint=" << result.value()->fingerprint() << '\n';
    for (const auto& display : result.value()->displays()) {
        std::wcout << L"  " << display.deviceName << L" ["
                   << display.pixelBounds.x << L',' << display.pixelBounds.y << L' '
                   << display.pixelBounds.width << L'x' << display.pixelBounds.height
                   << L"] dpi=" << display.dpiX << L'x' << display.dpiY
                   << L" rotation=" << static_cast<unsigned int>(display.rotation) << L'\n';
    }
    return 0;
}

} // namespace

int main(int argumentCount, char** arguments)
{
    if (argumentCount == 2 && std::strcmp(arguments[1], "--live") == 0) {
        return runLiveTopologySmoke();
    }

    testSnapshotPreservesDescriptorsAndBuildsVirtualBounds();
    testSnapshotExposesOnlyImmutableState();
    testTopologyResultAlwaysContainsExactlyOneAlternative();
    testVirtualBoundsStandardizeAndSaturate();
    testFingerprintIsOrderIndependentAndSensitiveToEveryField();
    testEmptyTopologyIsAnError();
    testDpiConversionsUsePerDisplayDpiAndNearestRounding();
    testMissingModernApisUseSafeFallbacks();
    testModernApisAreResolvedAndPreferred();
    testRuntimeApisMoveOwnershipWithoutDoubleFree();
    testDisplayConfigBufferSizeFailureIsSystemFailure();
    testQueryDisplayConfigFailureIsSystemFailure();
    testDisplayConfigDeviceInfoFailureIsSystemFailure();
    testInjectedEnumerationBuildsDescriptorsAndResolvesRotationSafely();
    testGetMonitorInfoFailureIsSystemFailure();
    testMonitorEnumeratorFailureIsSystemFailure();
    testCallbackRuntimeExceptionIsContained();
    testCallbackAllocationFailureIsContained();
    testThrowingGetMonitorInfoIsContained();
    testDisplayConfigRetriesInsufficientBufferThenSucceeds();
    testDisplayConfigInsufficientBufferExhaustionIsSystemFailure();
    return failureCount == 0 ? 0 : 1;
}
