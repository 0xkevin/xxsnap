#include "capture/DxgiCaptureBackend.h"
#include "capture/FallbackCaptureBackend.h"
#include "capture/DisplayTopology.h"
#include "capture/GdiCaptureBackend.h"
#include "support/RuntimeApis.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <optional>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

namespace {

using namespace xxsnap::win;
using snipory::core::portable::MemoryBudget;
using snipory::core::portable::PixelBuffer;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

DisplayTopologySnapshot snapshotFor(std::int64_t width = 1, std::int64_t height = 1)
{
    std::vector<DisplayDescriptor> displays;
    displays.push_back({
        L"display",
        {0, 0, width, height},
        96U,
        96U,
        DISPLAYCONFIG_ROTATION_IDENTITY,
    });
    const auto result = buildDisplayTopologySnapshot(std::move(displays));
    CHECK(result.hasValue());
    return *result.value();
}

CaptureResult successfulCapture(
    const DisplayTopologySnapshot& snapshot,
    MemoryBudget& budget)
{
    const auto& descriptor = snapshot.displays().front();
    auto allocation = PixelBuffer::allocate(
        descriptor.pixelBounds.width,
        descriptor.pixelBounds.height,
        budget);
    CHECK(allocation.value != nullptr);
    std::vector<FrozenDisplay> displays;
    displays.emplace_back(descriptor, std::move(*allocation.value));
    return FrozenDesktop{
        snapshot,
        std::move(displays),
        std::chrono::steady_clock::time_point{},
    };
}

enum class Event {
    dxgiCapture,
    dxgiReset,
    gdiCapture,
};

class FakeDxgi final : public ResettableCaptureBackend {
public:
    explicit FakeDxgi(std::vector<Event>& events)
        : events_(events)
    {
    }

    CaptureResult capture(
        const DisplayTopologySnapshot& snapshot,
        MemoryBudget& budget) noexcept override
    {
        events_.push_back(Event::dxgiCapture);
        if (results.empty()) {
            return successfulCapture(snapshot, budget);
        }
        const auto error = results.front();
        results.erase(results.begin());
        if (!error.has_value()) {
            return successfulCapture(snapshot, budget);
        }
        return *error;
    }

    void reset() noexcept override
    {
        events_.push_back(Event::dxgiReset);
        ++resetCalls;
    }

    std::vector<std::optional<CaptureError>> results;
    int resetCalls = 0;

private:
    std::vector<Event>& events_;
};

class FakeGdi final : public CaptureBackend {
public:
    explicit FakeGdi(std::vector<Event>& events)
        : events_(events)
    {
    }

    CaptureResult capture(
        const DisplayTopologySnapshot& snapshot,
        MemoryBudget& budget) noexcept override
    {
        events_.push_back(Event::gdiCapture);
        ++captureCalls;
        if (result.has_value()) {
            return *result;
        }
        return successfulCapture(snapshot, budget);
    }

    std::optional<CaptureError> result;
    int captureCalls = 0;

private:
    std::vector<Event>& events_;
};

const CaptureError* errorFrom(const CaptureResult& result)
{
    const auto* error = std::get_if<CaptureError>(&result);
    CHECK(error != nullptr);
    return error;
}

void testDxgiSuccessReturnsWithoutResetOrFallback()
{
    std::vector<Event> events;
    FakeDxgi dxgi(events);
    FakeGdi gdi(events);
    FallbackCaptureBackend backend(dxgi, gdi);
    MemoryBudget budget(4U);

    const auto result = backend.capture(snapshotFor(), budget);

    CHECK(std::holds_alternative<FrozenDesktop>(result));
    CHECK((events == std::vector{Event::dxgiCapture}));
    CHECK(dxgi.resetCalls == 0);
    CHECK(gdi.captureCalls == 0);
    CHECK(backend.lastBackend() == CaptureBackendKind::preferred);
}

void testDeviceLostResetsOnceAndRetriesDxgiOnce()
{
    std::vector<Event> events;
    FakeDxgi dxgi(events);
    dxgi.results = {
        CaptureError{CaptureErrorCode::deviceLost, DXGI_ERROR_ACCESS_LOST},
        std::nullopt,
    };
    FakeGdi gdi(events);
    FallbackCaptureBackend backend(dxgi, gdi);
    MemoryBudget budget(4U);

    const auto result = backend.capture(snapshotFor(), budget);

    CHECK(std::holds_alternative<FrozenDesktop>(result));
    CHECK((events == std::vector{
        Event::dxgiCapture,
        Event::dxgiReset,
        Event::dxgiCapture,
    }));
    CHECK(dxgi.resetCalls == 1);
    CHECK(gdi.captureCalls == 0);
    CHECK(backend.lastBackend() == CaptureBackendKind::preferred);
}

void testFailedRetryFallsBackToGdiAndReturnsItsResultUnchanged()
{
    std::vector<Event> events;
    FakeDxgi dxgi(events);
    dxgi.results = {
        CaptureError{CaptureErrorCode::deviceLost, DXGI_ERROR_ACCESS_LOST},
        CaptureError{CaptureErrorCode::noFrame, DXGI_ERROR_WAIT_TIMEOUT},
    };
    FakeGdi gdi(events);
    gdi.result = CaptureError{CaptureErrorCode::systemFailure, E_UNEXPECTED};
    FallbackCaptureBackend backend(dxgi, gdi);
    MemoryBudget budget(4U);

    const auto result = backend.capture(snapshotFor(), budget);

    CHECK((events == std::vector{
        Event::dxgiCapture,
        Event::dxgiReset,
        Event::dxgiCapture,
        Event::gdiCapture,
    }));
    CHECK(errorFrom(result)->code == CaptureErrorCode::systemFailure);
    CHECK(errorFrom(result)->nativeCode == E_UNEXPECTED);
    CHECK(backend.lastBackend() == CaptureBackendKind::fallback);
}

void testSecondDeviceLostDoesNotResetTwice()
{
    std::vector<Event> events;
    FakeDxgi dxgi(events);
    dxgi.results = {
        CaptureError{CaptureErrorCode::deviceLost, DXGI_ERROR_ACCESS_LOST},
        CaptureError{CaptureErrorCode::deviceLost, DXGI_ERROR_ACCESS_LOST},
    };
    FakeGdi gdi(events);
    FallbackCaptureBackend backend(dxgi, gdi);
    MemoryBudget budget(4U);

    const auto result = backend.capture(snapshotFor(), budget);

    CHECK(std::holds_alternative<FrozenDesktop>(result));
    CHECK((events == std::vector{
        Event::dxgiCapture,
        Event::dxgiReset,
        Event::dxgiCapture,
        Event::gdiCapture,
    }));
    CHECK(dxgi.resetCalls == 1);
    CHECK(gdi.captureCalls == 1);
    CHECK(backend.lastBackend() == CaptureBackendKind::fallback);
}

void testRecoverableErrorsFallBackDirectlyWithoutReset()
{
    const std::array recoverable{
        CaptureErrorCode::accessDenied,
        CaptureErrorCode::noFrame,
        CaptureErrorCode::unsupported,
        CaptureErrorCode::systemFailure,
    };
    for (const auto code : recoverable) {
        std::vector<Event> events;
        FakeDxgi dxgi(events);
        dxgi.results = {CaptureError{code, E_FAIL}};
        FakeGdi gdi(events);
        FallbackCaptureBackend backend(dxgi, gdi);
        MemoryBudget budget(4U);

        const auto result = backend.capture(snapshotFor(), budget);

        CHECK(std::holds_alternative<FrozenDesktop>(result));
        CHECK((events == std::vector{Event::dxgiCapture, Event::gdiCapture}));
        CHECK(dxgi.resetCalls == 0);
        CHECK(gdi.captureCalls == 1);
        CHECK(backend.lastBackend() == CaptureBackendKind::fallback);
    }
}

void testTerminalErrorsNeverRetryOrFallBack()
{
    const std::array terminal{
        CaptureErrorCode::memoryLimit,
        CaptureErrorCode::arithmeticOverflow,
        CaptureErrorCode::invalidSize,
        CaptureErrorCode::topologyChanged,
    };
    for (const auto code : terminal) {
        std::vector<Event> events;
        FakeDxgi dxgi(events);
        dxgi.results = {CaptureError{code, E_OUTOFMEMORY}};
        FakeGdi gdi(events);
        FallbackCaptureBackend backend(dxgi, gdi);
        MemoryBudget budget(4U);

        const auto result = backend.capture(snapshotFor(), budget);

        CHECK(errorFrom(result)->code == code);
        CHECK((events == std::vector{Event::dxgiCapture}));
        CHECK(dxgi.resetCalls == 0);
        CHECK(gdi.captureCalls == 0);
        CHECK(backend.lastBackend() == CaptureBackendKind::preferred);
    }
}

void testTerminalRetryErrorReturnsImmediately()
{
    std::vector<Event> events;
    FakeDxgi dxgi(events);
    dxgi.results = {
        CaptureError{CaptureErrorCode::deviceLost, DXGI_ERROR_ACCESS_LOST},
        CaptureError{CaptureErrorCode::topologyChanged, E_FAIL},
    };
    FakeGdi gdi(events);
    FallbackCaptureBackend backend(dxgi, gdi);
    MemoryBudget budget(4U);

    const auto result = backend.capture(snapshotFor(), budget);

    CHECK(errorFrom(result)->code == CaptureErrorCode::topologyChanged);
    CHECK((events == std::vector{
        Event::dxgiCapture,
        Event::dxgiReset,
        Event::dxgiCapture,
    }));
    CHECK(gdi.captureCalls == 0);
}

void testDxgiErrorMappingIsStableAndPreservesNativeCode()
{
    const std::array mappings{
        std::pair{DXGI_ERROR_ACCESS_LOST, CaptureErrorCode::deviceLost},
        std::pair{DXGI_ERROR_WAIT_TIMEOUT, CaptureErrorCode::noFrame},
        std::pair{E_ACCESSDENIED, CaptureErrorCode::accessDenied},
        std::pair{DXGI_ERROR_DEVICE_REMOVED, CaptureErrorCode::systemFailure},
        std::pair{DXGI_ERROR_DEVICE_RESET, CaptureErrorCode::systemFailure},
        std::pair{DXGI_ERROR_UNSUPPORTED, CaptureErrorCode::systemFailure},
        std::pair{DXGI_ERROR_NOT_CURRENTLY_AVAILABLE, CaptureErrorCode::systemFailure},
        std::pair{E_OUTOFMEMORY, CaptureErrorCode::systemFailure},
        std::pair{E_INVALIDARG, CaptureErrorCode::systemFailure},
        std::pair{E_UNEXPECTED, CaptureErrorCode::systemFailure},
    };
    for (const auto& [nativeCode, expectedCode] : mappings) {
        const auto mapped = mapDxgiError(nativeCode);
        CHECK(mapped.code == expectedCode);
        CHECK(mapped.nativeCode == nativeCode);
    }
}

void testMatchingDxgiCacheKeyIsReused()
{
    const DisplayDescriptor requested{
        L"display",
        {-1920, 0, 1920, 1080},
        144U,
        144U,
        DISPLAYCONFIG_ROTATION_IDENTITY,
    };
    const DxgiCaptureCacheKey cached{
        L"display",
        {-1920, 0, 1920, 1080},
        DISPLAYCONFIG_ROTATION_IDENTITY,
    };

    CHECK(decideDxgiCaptureCache(requested, cached)
        == DxgiCaptureCacheDecision::reuse);
}

void testSameDeviceWithChangedTopologyRebuildsDxgiCache()
{
    const DisplayDescriptor requested{
        L"display",
        {-1920, 0, 1920, 1080},
        144U,
        144U,
        DISPLAYCONFIG_ROTATION_IDENTITY,
    };
    const std::array changedKeys{
        DxgiCaptureCacheKey{L"display", {-1919, 0, 1920, 1080},
                            DISPLAYCONFIG_ROTATION_IDENTITY},
        DxgiCaptureCacheKey{L"display", {-1920, 1, 1920, 1080},
                            DISPLAYCONFIG_ROTATION_IDENTITY},
        DxgiCaptureCacheKey{L"display", {-1920, 0, 1919, 1080},
                            DISPLAYCONFIG_ROTATION_IDENTITY},
        DxgiCaptureCacheKey{L"display", {-1920, 0, 1920, 1079},
                            DISPLAYCONFIG_ROTATION_IDENTITY},
        DxgiCaptureCacheKey{L"display", {-1920, 0, 1920, 1080},
                            DISPLAYCONFIG_ROTATION_ROTATE90},
    };

    for (const auto& cached : changedKeys) {
        CHECK(decideDxgiCaptureCache(requested, cached)
            == DxgiCaptureCacheDecision::rebuild);
    }
}

void testDifferentDeviceDoesNotHitDxgiCache()
{
    const DisplayDescriptor requested{
        L"display-a",
        {0, 0, 1920, 1080},
        96U,
        96U,
        DISPLAYCONFIG_ROTATION_IDENTITY,
    };
    const DxgiCaptureCacheKey cached{
        L"display-b",
        {0, 0, 1920, 1080},
        DISPLAYCONFIG_ROTATION_IDENTITY,
    };

    CHECK(decideDxgiCaptureCache(requested, cached)
        == DxgiCaptureCacheDecision::noMatch);
}

std::vector<std::byte> mappedPattern(
    std::int64_t width,
    std::int64_t height,
    std::size_t rowPitch,
    const std::vector<unsigned char>& labels)
{
    std::vector<std::byte> bytes(rowPitch * static_cast<std::size_t>(height), std::byte{0xEEU});
    for (std::int64_t y = 0; y < height; ++y) {
        for (std::int64_t x = 0; x < width; ++x) {
            const auto pixel = static_cast<std::size_t>(y * width + x);
            const auto offset = static_cast<std::size_t>(y) * rowPitch
                + static_cast<std::size_t>(x) * 4U;
            bytes[offset + 0U] = std::byte{labels[pixel]};
            bytes[offset + 1U] = std::byte{static_cast<unsigned char>(labels[pixel] + 20U)};
            bytes[offset + 2U] = std::byte{static_cast<unsigned char>(labels[pixel] + 40U)};
            bytes[offset + 3U] = std::byte{0U};
        }
    }
    return bytes;
}

void checkCanonicalPattern(const PixelBuffer& pixels)
{
    CHECK(pixels.width() == 2);
    CHECK(pixels.height() == 3);
    const std::array<unsigned char, 6> expected{1U, 2U, 3U, 4U, 5U, 6U};
    for (std::size_t index = 0; index < expected.size(); ++index) {
        const auto offset = index * 4U;
        CHECK(pixels.data()[offset + 0U] == std::byte{expected[index]});
        CHECK(pixels.data()[offset + 1U]
            == std::byte{static_cast<unsigned char>(expected[index] + 20U)});
        CHECK(pixels.data()[offset + 2U]
            == std::byte{static_cast<unsigned char>(expected[index] + 40U)});
        CHECK(pixels.data()[offset + 3U] == std::byte{255U});
    }
}

void testMappedBgraCopyHandlesEveryRotationAndPaddedRows()
{
    struct RotationCase {
        DISPLAYCONFIG_ROTATION rotation;
        std::int64_t sourceWidth;
        std::int64_t sourceHeight;
        std::vector<unsigned char> sourceLabels;
    };
    const std::array cases{
        RotationCase{DISPLAYCONFIG_ROTATION_IDENTITY, 2, 3, {1, 2, 3, 4, 5, 6}},
        RotationCase{DISPLAYCONFIG_ROTATION_ROTATE90, 3, 2, {5, 3, 1, 6, 4, 2}},
        RotationCase{DISPLAYCONFIG_ROTATION_ROTATE180, 2, 3, {6, 5, 4, 3, 2, 1}},
        RotationCase{DISPLAYCONFIG_ROTATION_ROTATE270, 3, 2, {2, 4, 6, 1, 3, 5}},
    };
    for (const auto& testCase : cases) {
        const auto tightRowBytes = static_cast<std::size_t>(testCase.sourceWidth) * 4U;
        const auto rowPitch = tightRowBytes + 12U;
        const auto source = mappedPattern(
            testCase.sourceWidth,
            testCase.sourceHeight,
            rowPitch,
            testCase.sourceLabels);
        MemoryBudget budget(24U);
        auto allocation = PixelBuffer::allocate(2, 3, budget);
        CHECK(allocation.value != nullptr);

        const auto failure = copyMappedBgra(
            source.data(),
            rowPitch,
            testCase.sourceWidth,
            testCase.sourceHeight,
            testCase.rotation,
            *allocation.value);

        CHECK(!failure.has_value());
        checkCanonicalPattern(*allocation.value);
    }
}

void testMappedBgraCopyRejectsInconsistentDimensionsAndPitch()
{
    MemoryBudget budget(24U);
    auto allocation = PixelBuffer::allocate(2, 3, budget);
    CHECK(allocation.value != nullptr);
    const std::array<std::byte, 24> source{};

    const auto wrongRotationDimensions = copyMappedBgra(
        source.data(), 8U, 2, 3, DISPLAYCONFIG_ROTATION_ROTATE90, *allocation.value);
    const auto shortPitch = copyMappedBgra(
        source.data(), 7U, 2, 3, DISPLAYCONFIG_ROTATION_IDENTITY, *allocation.value);
    const auto nullSource = copyMappedBgra(
        nullptr, 8U, 2, 3, DISPLAYCONFIG_ROTATION_IDENTITY, *allocation.value);

    CHECK(wrongRotationDimensions.has_value());
    CHECK(wrongRotationDimensions->code == CaptureErrorCode::invalidSize);
    CHECK(shortPitch.has_value());
    CHECK(shortPitch->code == CaptureErrorCode::invalidSize);
    CHECK(nullSource.has_value());
    CHECK(nullSource->code == CaptureErrorCode::systemFailure);
}

void testAllBlackMappedFrameIsAValidCapture()
{
    MemoryBudget budget(24U);
    auto allocation = PixelBuffer::allocate(2, 3, budget);
    CHECK(allocation.value != nullptr);
    const std::array<std::byte, 24> source{};

    const auto failure = copyMappedBgra(
        source.data(), 8U, 2, 3, DISPLAYCONFIG_ROTATION_IDENTITY, *allocation.value);

    CHECK(!failure.has_value());
    for (std::size_t offset = 0U; offset < allocation.value->byteCount(); offset += 4U) {
        CHECK(allocation.value->data()[offset + 0U] == std::byte{0U});
        CHECK(allocation.value->data()[offset + 1U] == std::byte{0U});
        CHECK(allocation.value->data()[offset + 2U] == std::byte{0U});
        CHECK(allocation.value->data()[offset + 3U] == std::byte{255U});
    }
}

#if defined(XXSNAP_MODERN)

class TrackingDxgi final : public ResettableCaptureBackend {
public:
    CaptureResult capture(
        const DisplayTopologySnapshot& snapshot,
        MemoryBudget& budget) noexcept override
    {
        auto result = backend_.capture(snapshot, budget);
        const auto* failure = std::get_if<CaptureError>(&result);
        results.push_back(failure == nullptr
                ? std::optional<CaptureError>{}
                : std::optional<CaptureError>{*failure});
        return result;
    }

    void reset() noexcept override
    {
        ++resetCalls;
        backend_.reset();
    }

    std::vector<std::optional<CaptureError>> results;
    int resetCalls = 0;

private:
    DxgiCaptureBackend backend_;
};

class TrackingGdi final : public CaptureBackend {
public:
    CaptureResult capture(
        const DisplayTopologySnapshot& snapshot,
        MemoryBudget& budget) noexcept override
    {
        ++captureCalls;
        auto result = backend_.capture(snapshot, budget);
        const auto* failure = std::get_if<CaptureError>(&result);
        lastResult = failure == nullptr
            ? std::optional<CaptureError>{}
            : std::optional<CaptureError>{*failure};
        return result;
    }

    std::optional<CaptureError> lastResult;
    int captureCalls = 0;

private:
    GdiCaptureBackend backend_;
};

bool terminalForSmoke(CaptureErrorCode code)
{
    return code == CaptureErrorCode::memoryLimit
        || code == CaptureErrorCode::arithmeticOverflow
        || code == CaptureErrorCode::invalidSize
        || code == CaptureErrorCode::topologyChanged;
}

#endif

void testLiveDxgiCaptureUsesRealGdiFallbackWhenRequired()
{
#if defined(XXSNAP_MODERN)
    RuntimeApis runtimeApis;
    const auto topology = snapshotDisplayTopology(runtimeApis);
    const auto liveSnapshot = topology.hasValue()
        ? *topology.value()
        : snapshotFor();

    TrackingDxgi dxgi;
    TrackingGdi gdi;
    FallbackCaptureBackend backend(dxgi, gdi);
    MemoryBudget budget(std::numeric_limits<std::uint64_t>::max());

    const auto result = backend.capture(liveSnapshot, budget);

    CHECK(!dxgi.results.empty());
    if (dxgi.results.empty()) {
        return;
    }

    bool expectGdi = false;
    if (dxgi.results.front().has_value()) {
        const auto firstCode = dxgi.results.front()->code;
        if (firstCode == CaptureErrorCode::deviceLost) {
            CHECK(dxgi.resetCalls == 1);
            CHECK(dxgi.results.size() == 2U);
            if (dxgi.results.size() == 2U && dxgi.results[1].has_value()) {
                expectGdi = !terminalForSmoke(dxgi.results[1]->code);
            }
        } else {
            expectGdi = !terminalForSmoke(firstCode);
        }
    }

    CHECK(gdi.captureCalls == (expectGdi ? 1 : 0));
    if (expectGdi) {
        CHECK(gdi.lastResult.has_value()
            == std::holds_alternative<CaptureError>(result));
    }

    if (dxgi.results.front().has_value()) {
        std::cout << (topology.hasValue() ? "Live" : "Headless synthetic-output")
                  << " DXGI HRESULT: 0x" << std::hex
                  << static_cast<std::uint32_t>(dxgi.results.front()->nativeCode)
                  << std::dec << ", GDI fallback calls: " << gdi.captureCalls << '\n';
    } else {
        std::cout << "Live DXGI capture succeeded, GDI fallback calls: "
                  << gdi.captureCalls << '\n';
    }
#endif
}

} // namespace

int main(int argumentCount, char* arguments[])
{
    if (argumentCount == 2 && std::string_view(arguments[1]) == "--live") {
        testLiveDxgiCaptureUsesRealGdiFallbackWhenRequired();
        return failureCount == 0 ? 0 : 1;
    }
    if (argumentCount != 1) {
        std::cerr << "Usage: xxsnap_fallback_capture_test [--live]\n";
        return 2;
    }

    testDxgiSuccessReturnsWithoutResetOrFallback();
    testDeviceLostResetsOnceAndRetriesDxgiOnce();
    testFailedRetryFallsBackToGdiAndReturnsItsResultUnchanged();
    testSecondDeviceLostDoesNotResetTwice();
    testRecoverableErrorsFallBackDirectlyWithoutReset();
    testTerminalErrorsNeverRetryOrFallBack();
    testTerminalRetryErrorReturnsImmediately();
    testDxgiErrorMappingIsStableAndPreservesNativeCode();
    testMatchingDxgiCacheKeyIsReused();
    testSameDeviceWithChangedTopologyRebuildsDxgiCache();
    testDifferentDeviceDoesNotHitDxgiCache();
    testMappedBgraCopyHandlesEveryRotationAndPaddedRows();
    testMappedBgraCopyRejectsInconsistentDimensionsAndPitch();
    testAllBlackMappedFrameIsAValidCapture();
    return failureCount == 0 ? 0 : 1;
}
