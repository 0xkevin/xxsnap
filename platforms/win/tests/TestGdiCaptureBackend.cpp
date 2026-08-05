#include "capture/GdiCaptureBackend.h"
#include "capture/DisplayTopology.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <new>
#include <stdexcept>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

namespace {

using namespace xxsnap::win;
using snipory::core::portable::MemoryBudget;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

enum class FailurePoint {
    none,
    getDc,
    createCompatibleDc,
    createDibSection,
    createDibSectionWithoutBits,
    selectObject,
    bitBlt,
    gdiFlush,
};

enum class RestoreFailure {
    none,
    nullResult,
    gdiError,
    exception,
};

enum class GdiEvent {
    bitBlt,
    flush,
    restore,
    deleteDc,
    deleteObject,
    releaseDc,
};

struct FakeGdi final {
    FailurePoint failure = FailurePoint::none;
    DWORD error = ERROR_INVALID_FUNCTION;
    bool failureSetsLastError = true;
    bool throwFromBitBlt = false;
    bool throwBadAllocFromDib = false;
    RestoreFailure restoreFailure = RestoreFailure::none;
    int setLastErrorCalls = 0;
    int getDcCalls = 0;
    int releaseDcCalls = 0;
    int createCompatibleDcCalls = 0;
    int deleteDcCalls = 0;
    int createDibSectionCalls = 0;
    int deleteObjectCalls = 0;
    int selectObjectCalls = 0;
    int bitBltCalls = 0;
    int gdiFlushCalls = 0;
    bool bitmapSelected = false;
    bool deletedWhileSelected = false;
    int sourceX = 0;
    int sourceY = 0;
    DWORD rasterOperation = 0;
    LONG dibWidth = 0;
    LONG dibHeight = 0;
    std::vector<std::byte> dibBytes;
    std::vector<std::byte> pendingDibBytes;
    std::vector<GdiEvent> events;

    HDC desktopDc() const noexcept
    {
        return reinterpret_cast<HDC>(static_cast<std::uintptr_t>(0x101U));
    }

    HDC memoryDc() const noexcept
    {
        return reinterpret_cast<HDC>(static_cast<std::uintptr_t>(0x202U));
    }

    HBITMAP bitmap() const noexcept
    {
        return reinterpret_cast<HBITMAP>(static_cast<std::uintptr_t>(0x303U));
    }

    HGDIOBJ oldObject() const noexcept
    {
        return reinterpret_cast<HGDIOBJ>(static_cast<std::uintptr_t>(0x404U));
    }

    void fail() const noexcept
    {
        if (failureSetsLastError) {
            SetLastError(error);
        }
    }

    GdiCaptureApis apis()
    {
        GdiCaptureApis result;
        result.getDc = [this](HWND window) {
            CHECK(window == nullptr);
            ++getDcCalls;
            if (failure == FailurePoint::getDc) {
                fail();
                return static_cast<HDC>(nullptr);
            }
            return desktopDc();
        };
        result.releaseDc = [this](HWND window, HDC dc) {
            CHECK(window == nullptr);
            CHECK(dc == desktopDc());
            ++releaseDcCalls;
            events.push_back(GdiEvent::releaseDc);
            return 1;
        };
        result.createCompatibleDc = [this](HDC dc) {
            CHECK(dc == desktopDc());
            ++createCompatibleDcCalls;
            if (failure == FailurePoint::createCompatibleDc) {
                fail();
                return static_cast<HDC>(nullptr);
            }
            return memoryDc();
        };
        result.deleteDc = [this](HDC dc) {
            CHECK(dc == memoryDc());
            ++deleteDcCalls;
            bitmapSelected = false;
            events.push_back(GdiEvent::deleteDc);
            return TRUE;
        };
        result.createDibSection =
            [this](HDC dc, const BITMAPINFO* info, UINT usage, void** bits, HANDLE section,
                   DWORD offset) {
                CHECK(dc == desktopDc());
                CHECK(info != nullptr);
                CHECK(usage == DIB_RGB_COLORS);
                CHECK(section == nullptr);
                CHECK(offset == 0U);
                ++createDibSectionCalls;
                if (throwBadAllocFromDib) {
                    throw std::bad_alloc();
                }
                if (failure == FailurePoint::createDibSection) {
                    fail();
                    return static_cast<HBITMAP>(nullptr);
                }
                if (failure == FailurePoint::createDibSectionWithoutBits) {
                    fail();
                    return bitmap();
                }
                CHECK(info->bmiHeader.biSize == sizeof(BITMAPINFOHEADER));
                CHECK(info->bmiHeader.biPlanes == 1U);
                CHECK(info->bmiHeader.biBitCount == 32U);
                CHECK(info->bmiHeader.biCompression == BI_RGB);
                CHECK(info->bmiHeader.biHeight < 0);
                dibWidth = info->bmiHeader.biWidth;
                dibHeight = -info->bmiHeader.biHeight;
                dibBytes.assign(
                    static_cast<std::size_t>(dibWidth * dibHeight * 4), std::byte{0});
                pendingDibBytes.assign(dibBytes.size(), std::byte{0});
                *bits = dibBytes.data();
                return bitmap();
            };
        result.deleteObject = [this](HGDIOBJ object) {
            CHECK(object == bitmap());
            ++deleteObjectCalls;
            deletedWhileSelected = deletedWhileSelected || bitmapSelected;
            events.push_back(GdiEvent::deleteObject);
            return TRUE;
        };
        result.selectObject = [this](HDC dc, HGDIOBJ object) {
            CHECK(dc == memoryDc());
            ++selectObjectCalls;
            if (failure == FailurePoint::selectObject && object == bitmap()) {
                fail();
                return static_cast<HGDIOBJ>(nullptr);
            }
            if (object == bitmap()) {
                bitmapSelected = true;
                return oldObject();
            }
            CHECK(object == oldObject());
            events.push_back(GdiEvent::restore);
            if (restoreFailure == RestoreFailure::exception) {
                throw std::runtime_error("injected restore failure");
            }
            if (restoreFailure != RestoreFailure::none) {
                fail();
                return restoreFailure == RestoreFailure::gdiError
                    ? HGDI_ERROR
                    : static_cast<HGDIOBJ>(nullptr);
            }
            bitmapSelected = false;
            return static_cast<HGDIOBJ>(bitmap());
        };
        result.bitBlt = [this](HDC destination, int x, int y, int width, int height,
                               HDC source, int sourceLeft, int sourceTop, DWORD operation) {
            CHECK(destination == memoryDc());
            CHECK(source == desktopDc());
            CHECK(x == 0);
            CHECK(y == 0);
            CHECK(width == dibWidth);
            CHECK(height == dibHeight);
            CHECK(bitmapSelected);
            ++bitBltCalls;
            events.push_back(GdiEvent::bitBlt);
            sourceX = sourceLeft;
            sourceY = sourceTop;
            rasterOperation = operation;
            if (throwFromBitBlt) {
                throw std::runtime_error("injected BitBlt failure");
            }
            if (failure == FailurePoint::bitBlt) {
                fail();
                return FALSE;
            }
            for (LONG row = 0; row < dibHeight; ++row) {
                for (LONG column = 0; column < dibWidth; ++column) {
                    const auto offset = static_cast<std::size_t>(
                        (row * dibWidth + column) * 4);
                    pendingDibBytes[offset + 0U]
                        = std::byte{static_cast<unsigned char>(10 + row)};
                    pendingDibBytes[offset + 1U]
                        = std::byte{static_cast<unsigned char>(20 + column)};
                    pendingDibBytes[offset + 2U]
                        = std::byte{static_cast<unsigned char>(30 + row * 4 + column)};
                    pendingDibBytes[offset + 3U]
                        = std::byte{static_cast<unsigned char>(40 + row)};
                }
            }
            return TRUE;
        };
        result.gdiFlush = [this] {
            ++gdiFlushCalls;
            events.push_back(GdiEvent::flush);
            if (failure == FailurePoint::gdiFlush) {
                fail();
                return FALSE;
            }
            if (pendingDibBytes.size() == dibBytes.size()) {
                dibBytes = pendingDibBytes;
            }
            return TRUE;
        };
        result.setLastError = [this](DWORD value) {
            ++setLastErrorCalls;
            SetLastError(value);
        };
        result.getLastError = [] { return GetLastError(); };
        return result;
    }
};

DisplayTopologySnapshot snapshotFor(std::vector<DisplayDescriptor> displays)
{
    const auto result = buildDisplayTopologySnapshot(std::move(displays));
    CHECK(result.hasValue());
    return *result.value();
}

DisplayDescriptor display(
    const wchar_t* name,
    std::int64_t x,
    std::int64_t y,
    std::int64_t width = 4,
    std::int64_t height = 3)
{
    return {name, {x, y, width, height}, 96U, 96U,
            DISPLAYCONFIG_ROTATION_IDENTITY};
}

const FrozenDesktop* successfulDesktop(const CaptureResult& result)
{
    const auto* desktop = std::get_if<FrozenDesktop>(&result);
    CHECK(desktop != nullptr);
    return desktop;
}

const CaptureError* captureError(const CaptureResult& result)
{
    const auto* error = std::get_if<CaptureError>(&result);
    CHECK(error != nullptr);
    return error;
}

void testBoundaryIsPortableAndMoveOnly()
{
    static_assert(std::is_abstract_v<CaptureBackend>);
    static_assert(std::is_same_v<
        CaptureResult,
        std::variant<FrozenDesktop, CaptureError>>);
    static_assert(!std::is_copy_constructible_v<FrozenDisplay>);
    static_assert(std::is_move_constructible_v<FrozenDisplay>);
    static_assert(!std::is_copy_constructible_v<FrozenDesktop>);
    static_assert(std::is_move_constructible_v<FrozenDesktop>);
}

void testCapturesTopDownBgrxAsOpaqueBgra()
{
    FakeGdi fake;
    GdiCaptureBackend backend(fake.apis());
    const auto snapshot = snapshotFor({display(L"A", -7, 11)});
    MemoryBudget budget(48U);
    const auto before = std::chrono::steady_clock::now();

    const auto result = backend.capture(snapshot, budget);

    const auto after = std::chrono::steady_clock::now();
    const auto* desktop = successfulDesktop(result);
    if (desktop == nullptr) {
        return;
    }
    CHECK(desktop->topology.fingerprint() == snapshot.fingerprint());
    CHECK(desktop->topology.displays() == snapshot.displays());
    CHECK(desktop->displays.size() == 1U);
    CHECK(desktop->displays[0].descriptor == snapshot.displays()[0]);
    CHECK(desktop->capturedAt >= before);
    CHECK(desktop->capturedAt <= after);
    CHECK(fake.sourceX == -7);
    CHECK(fake.sourceY == 11);
    CHECK(fake.rasterOperation == (SRCCOPY | CAPTUREBLT));
    CHECK(fake.gdiFlushCalls == 1);
    CHECK(fake.setLastErrorCalls == 7);
    CHECK(fake.events.size() >= 6U);
    if (fake.events.size() >= 6U) {
        CHECK(fake.events[0] == GdiEvent::bitBlt);
        CHECK(fake.events[1] == GdiEvent::flush);
        CHECK(fake.events[2] == GdiEvent::restore);
        CHECK(fake.events[3] == GdiEvent::deleteDc);
        CHECK(fake.events[4] == GdiEvent::deleteObject);
        CHECK(fake.events[5] == GdiEvent::releaseDc);
    }

    const auto& pixels = desktop->displays[0].pixels;
    CHECK(pixels.width() == 4);
    CHECK(pixels.height() == 3);
    CHECK(pixels.stride() == 16U);
    CHECK(pixels.byteCount() == 48U);
    for (std::int64_t row = 0; row < 3; ++row) {
        for (std::int64_t column = 0; column < 4; ++column) {
            const auto offset = static_cast<std::size_t>(row * 16 + column * 4);
            CHECK(pixels.data()[offset + 0U]
                == std::byte{static_cast<unsigned char>(10 + row)});
            CHECK(pixels.data()[offset + 1U]
                == std::byte{static_cast<unsigned char>(20 + column)});
            CHECK(pixels.data()[offset + 2U]
                == std::byte{static_cast<unsigned char>(30 + row * 4 + column)});
            CHECK(pixels.data()[offset + 3U] == std::byte{255U});
        }
    }
    CHECK(fake.releaseDcCalls == 1);
    CHECK(fake.deleteDcCalls == 1);
    CHECK(fake.deleteObjectCalls == 1);
    CHECK(fake.selectObjectCalls == 2);
    CHECK(!fake.bitmapSelected);
    CHECK(!fake.deletedWhileSelected);
    CHECK(budget.usedBytes() == 48U);
}

void testAllBlackDesktopSucceeds()
{
    FakeGdi fake;
    auto apis = fake.apis();
    apis.bitBlt = [&fake](HDC, int, int, int, int, HDC, int, int, DWORD) {
        ++fake.bitBltCalls;
        return TRUE;
    };
    GdiCaptureBackend backend(std::move(apis));
    MemoryBudget budget(16U);
    const auto result = backend.capture(snapshotFor({display(L"black", 0, 0, 2, 2)}), budget);

    CHECK(std::holds_alternative<FrozenDesktop>(result));
    const auto* desktop = successfulDesktop(result);
    if (desktop != nullptr) {
        for (std::size_t index = 0; index < desktop->displays[0].pixels.byteCount(); index += 4U) {
            CHECK(desktop->displays[0].pixels.data()[index + 0U] == std::byte{0U});
            CHECK(desktop->displays[0].pixels.data()[index + 1U] == std::byte{0U});
            CHECK(desktop->displays[0].pixels.data()[index + 2U] == std::byte{0U});
            CHECK(desktop->displays[0].pixels.data()[index + 3U] == std::byte{255U});
        }
    }
}

void testEveryGdiFailureReturnsSystemFailureAndCleansUp()
{
    const std::array failures{
        FailurePoint::getDc,
        FailurePoint::createCompatibleDc,
        FailurePoint::createDibSection,
        FailurePoint::createDibSectionWithoutBits,
        FailurePoint::selectObject,
        FailurePoint::bitBlt,
        FailurePoint::gdiFlush,
    };

    for (const auto failure : failures) {
        FakeGdi fake;
        fake.failure = failure;
        fake.error = ERROR_ACCESS_DENIED;
        GdiCaptureBackend backend(fake.apis());
        MemoryBudget budget(48U);

        const auto result = backend.capture(snapshotFor({display(L"A", 0, 0)}), budget);

        const auto* error = captureError(result);
        if (error != nullptr) {
            CHECK(error->code == CaptureErrorCode::systemFailure);
            CHECK(error->nativeCode == HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED));
        }
        CHECK(budget.usedBytes() == 0U);
        CHECK(fake.releaseDcCalls == (failure == FailurePoint::getDc ? 0 : 1));
        CHECK(fake.deleteDcCalls
            == (failure == FailurePoint::getDc
                    || failure == FailurePoint::createCompatibleDc
                ? 0
                : 1));
        CHECK(fake.deleteObjectCalls
            == (failure == FailurePoint::createDibSectionWithoutBits
                    || failure == FailurePoint::selectObject
                    || failure == FailurePoint::bitBlt
                    || failure == FailurePoint::gdiFlush
                ? 1
                : 0));
        CHECK(fake.selectObjectCalls
            == (failure == FailurePoint::bitBlt
                    || failure == FailurePoint::gdiFlush ? 2
                : failure == FailurePoint::selectObject ? 1 : 0));
        CHECK(!fake.deletedWhileSelected);
    }
}

void testFlushFailureDoesNotPublishPixelsAndCleansUp()
{
    FakeGdi fake;
    fake.failure = FailurePoint::gdiFlush;
    fake.error = ERROR_WRITE_FAULT;
    GdiCaptureBackend backend(fake.apis());
    MemoryBudget budget(48U);

    const auto result = backend.capture(snapshotFor({display(L"A", 0, 0)}), budget);

    const auto* error = captureError(result);
    if (error != nullptr) {
        CHECK(error->code == CaptureErrorCode::systemFailure);
        CHECK(error->nativeCode == HRESULT_FROM_WIN32(ERROR_WRITE_FAULT));
    }
    CHECK(fake.bitBltCalls == 1);
    CHECK(fake.gdiFlushCalls == 1);
    CHECK(fake.dibBytes != fake.pendingDibBytes);
    CHECK(fake.selectObjectCalls == 2);
    CHECK(fake.deleteDcCalls == 1);
    CHECK(fake.deleteObjectCalls == 1);
    CHECK(fake.releaseDcCalls == 1);
    CHECK(!fake.deletedWhileSelected);
    CHECK(budget.usedBytes() == 0U);
}

void testZeroLastErrorIsStableEFail()
{
    FakeGdi fake;
    fake.failure = FailurePoint::getDc;
    fake.error = ERROR_SUCCESS;
    GdiCaptureBackend backend(fake.apis());
    MemoryBudget budget(48U);

    const auto result = backend.capture(snapshotFor({display(L"A", 0, 0)}), budget);

    CHECK(captureError(result)->nativeCode == E_FAIL);
}

void testStaleLastErrorIsClearedBeforeEachFallibleCall()
{
    FakeGdi fake;
    fake.failure = FailurePoint::getDc;
    fake.failureSetsLastError = false;
    SetLastError(ERROR_ACCESS_DENIED);
    GdiCaptureBackend backend(fake.apis());
    MemoryBudget budget(48U);

    const auto result = backend.capture(snapshotFor({display(L"A", 0, 0)}), budget);

    CHECK(captureError(result)->nativeCode == E_FAIL);
    CHECK(fake.setLastErrorCalls == 1);
}

void testRestoreFailuresDetachDcBeforeDeletingBitmap()
{
    const std::array failures{
        RestoreFailure::nullResult,
        RestoreFailure::gdiError,
        RestoreFailure::exception,
    };
    for (const auto restoreFailure : failures) {
        FakeGdi fake;
        fake.restoreFailure = restoreFailure;
        fake.error = ERROR_INVALID_HANDLE;
        GdiCaptureBackend backend(fake.apis());
        MemoryBudget budget(48U);

        const auto result = backend.capture(snapshotFor({display(L"A", 0, 0)}), budget);

        const auto* error = captureError(result);
        if (error != nullptr) {
            CHECK(error->code == CaptureErrorCode::systemFailure);
            CHECK(error->nativeCode == (restoreFailure == RestoreFailure::exception
                    ? E_FAIL
                    : HRESULT_FROM_WIN32(ERROR_INVALID_HANDLE)));
        }
        CHECK(fake.selectObjectCalls == 2);
        CHECK(fake.deleteDcCalls == 1);
        CHECK(fake.deleteObjectCalls == 1);
        CHECK(fake.releaseDcCalls == 1);
        CHECK(!fake.deletedWhileSelected);
        const auto restore = std::find(
            fake.events.begin(), fake.events.end(), GdiEvent::restore);
        const auto deleteDc = std::find(
            fake.events.begin(), fake.events.end(), GdiEvent::deleteDc);
        const auto deleteObject = std::find(
            fake.events.begin(), fake.events.end(), GdiEvent::deleteObject);
        CHECK(restore < deleteDc);
        CHECK(deleteDc < deleteObject);
        CHECK(budget.usedBytes() == 0U);
    }
}

void testBudgetFailureStopsBeforeSecondDisplaysGdiWork()
{
    FakeGdi fake;
    GdiCaptureBackend backend(fake.apis());
    const auto snapshot = snapshotFor({display(L"first", 0, 0), display(L"second", 4, 0)});
    MemoryBudget budget(48U);

    const auto result = backend.capture(snapshot, budget);

    const auto* error = captureError(result);
    if (error != nullptr) {
        CHECK(error->code == CaptureErrorCode::memoryLimit);
        CHECK(error->nativeCode == E_OUTOFMEMORY);
    }
    CHECK(fake.createDibSectionCalls == 1);
    CHECK(fake.bitBltCalls == 1);
    CHECK(fake.releaseDcCalls == 1);
    CHECK(fake.deleteDcCalls == 1);
    CHECK(fake.deleteObjectCalls == 1);
    CHECK(!fake.deletedWhileSelected);
    CHECK(budget.usedBytes() == 0U);
}

void testInvalidSizeAndArithmeticOverflowAvoidGdi()
{
    const std::array cases{
        std::pair{display(L"zero", 0, 0, 0, 3), CaptureErrorCode::invalidSize},
        std::pair{display(L"negative", 0, 0, 4, -3), CaptureErrorCode::invalidSize},
        std::pair{display(L"overflow", 0, 0, std::numeric_limits<std::int64_t>::max(), 3),
                  CaptureErrorCode::arithmeticOverflow},
    };
    for (const auto& [descriptor, expected] : cases) {
        FakeGdi fake;
        GdiCaptureBackend backend(fake.apis());
        MemoryBudget budget(std::numeric_limits<std::uint64_t>::max());

        const auto result = backend.capture(snapshotFor({descriptor}), budget);

        CHECK(captureError(result)->code == expected);
        CHECK(fake.getDcCalls == 0);
        CHECK(fake.createDibSectionCalls == 0);
        CHECK(fake.bitBltCalls == 0);
        CHECK(budget.usedBytes() == 0U);
    }
}

void testInjectedExceptionsAreContainedAndResourcesReleased()
{
    {
        FakeGdi fake;
        fake.throwFromBitBlt = true;
        GdiCaptureBackend backend(fake.apis());
        MemoryBudget budget(48U);
        const auto result = backend.capture(snapshotFor({display(L"A", 0, 0)}), budget);
        CHECK(captureError(result)->code == CaptureErrorCode::systemFailure);
        CHECK(captureError(result)->nativeCode == E_FAIL);
        CHECK(fake.selectObjectCalls == 2);
        CHECK(fake.deleteObjectCalls == 1);
        CHECK(fake.deleteDcCalls == 1);
        CHECK(fake.releaseDcCalls == 1);
        CHECK(!fake.deletedWhileSelected);
        CHECK(budget.usedBytes() == 0U);
    }
    {
        FakeGdi fake;
        fake.throwBadAllocFromDib = true;
        GdiCaptureBackend backend(fake.apis());
        MemoryBudget budget(48U);
        const auto result = backend.capture(snapshotFor({display(L"A", 0, 0)}), budget);
        CHECK(captureError(result)->code == CaptureErrorCode::systemFailure);
        CHECK(captureError(result)->nativeCode == E_OUTOFMEMORY);
        CHECK(fake.deleteDcCalls == 1);
        CHECK(fake.releaseDcCalls == 1);
        CHECK(budget.usedBytes() == 0U);
    }
}

void testDisplayOrderAndIndependentBuffersArePreserved()
{
    FakeGdi fake;
    GdiCaptureBackend backend(fake.apis());
    const auto snapshot = snapshotFor({display(L"left", -4, 0), display(L"right", 0, 0)});
    MemoryBudget budget(96U);

    const auto result = backend.capture(snapshot, budget);

    const auto* desktop = successfulDesktop(result);
    if (desktop != nullptr) {
        CHECK(desktop->displays.size() == 2U);
        CHECK(desktop->displays[0].descriptor.deviceName == L"left");
        CHECK(desktop->displays[1].descriptor.deviceName == L"right");
        CHECK(desktop->displays[0].pixels.data() != desktop->displays[1].pixels.data());
    }
    CHECK(fake.createDibSectionCalls == 2);
    CHECK(fake.bitBltCalls == 2);
    CHECK(fake.releaseDcCalls == 2);
    CHECK(fake.deleteDcCalls == 2);
    CHECK(fake.deleteObjectCalls == 2);
}

void testRealGdiMemoryDcCaptureIsTopDownAndOpaque()
{
    auto sourceApis = systemGdiCaptureApis();
    BitmapHandle sourceBitmap;
    const auto sourceHandle = CreateCompatibleDC(nullptr);
    CHECK(sourceHandle != nullptr);
    if (sourceHandle == nullptr) {
        return;
    }
    MemoryDc sourceDc(sourceHandle, &sourceApis.deleteDc);

    BITMAPINFO sourceInfo{};
    sourceInfo.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    sourceInfo.bmiHeader.biWidth = 4;
    sourceInfo.bmiHeader.biHeight = -3;
    sourceInfo.bmiHeader.biPlanes = 1U;
    sourceInfo.bmiHeader.biBitCount = 32U;
    sourceInfo.bmiHeader.biCompression = BI_RGB;
    void* sourceBits = nullptr;
    const auto sourceBitmapValue = CreateDIBSection(
        sourceDc.get(), &sourceInfo, DIB_RGB_COLORS, &sourceBits, nullptr, 0U);
    CHECK(sourceBitmapValue != nullptr);
    CHECK(sourceBits != nullptr);
    if (sourceBitmapValue == nullptr || sourceBits == nullptr) {
        if (sourceBitmapValue != nullptr) {
            DeleteObject(sourceBitmapValue);
        }
        return;
    }
    sourceBitmap = BitmapHandle(sourceBitmapValue, &sourceApis.deleteObject);
    const auto previous = SelectObject(sourceDc.get(), sourceBitmap.get());
    CHECK(previous != nullptr);
    CHECK(previous != HGDI_ERROR);
    if (previous == nullptr || previous == HGDI_ERROR) {
        return;
    }
    SelectedObject sourceSelection(sourceDc.get(), previous, &sourceApis.selectObject);

    auto* bytes = static_cast<std::byte*>(sourceBits);
    for (std::int64_t row = 0; row < 3; ++row) {
        for (std::int64_t column = 0; column < 4; ++column) {
            const auto offset = static_cast<std::size_t>((row * 4 + column) * 4);
            bytes[offset + 0U] = std::byte{static_cast<unsigned char>(51 + row)};
            bytes[offset + 1U] = std::byte{static_cast<unsigned char>(61 + column)};
            bytes[offset + 2U]
                = std::byte{static_cast<unsigned char>(71 + row * 4 + column)};
            bytes[offset + 3U] = std::byte{static_cast<unsigned char>(81 + row)};
        }
    }
    CHECK(GdiFlush() != FALSE);

    int releaseCalls = 0;
    auto backendApis = systemGdiCaptureApis();
    backendApis.getDc = [&sourceDc](HWND window) {
        CHECK(window == nullptr);
        return sourceDc.get();
    };
    backendApis.releaseDc = [&releaseCalls, &sourceDc](HWND window, HDC dc) {
        CHECK(window == nullptr);
        CHECK(dc == sourceDc.get());
        ++releaseCalls;
        return 1;
    };
    GdiCaptureBackend backend(std::move(backendApis));
    MemoryBudget budget(48U);
    const auto resourcesBefore = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);

    const auto result = backend.capture(
        snapshotFor({display(L"real-memory-dc", 0, 0)}), budget);

    const auto resourcesAfter = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
    const auto* desktop = successfulDesktop(result);
    if (desktop != nullptr) {
        const auto& pixels = desktop->displays[0].pixels;
        for (std::int64_t row = 0; row < 3; ++row) {
            for (std::int64_t column = 0; column < 4; ++column) {
                const auto offset = static_cast<std::size_t>((row * 4 + column) * 4);
                CHECK(pixels.data()[offset + 0U]
                    == std::byte{static_cast<unsigned char>(51 + row)});
                CHECK(pixels.data()[offset + 1U]
                    == std::byte{static_cast<unsigned char>(61 + column)});
                CHECK(pixels.data()[offset + 2U]
                    == std::byte{static_cast<unsigned char>(71 + row * 4 + column)});
                CHECK(pixels.data()[offset + 3U] == std::byte{255U});
            }
        }
    }
    CHECK(releaseCalls == 1);
    CHECK(resourcesBefore != 0U);
    CHECK(resourcesAfter == resourcesBefore);
}

} // namespace

int main()
{
    testBoundaryIsPortableAndMoveOnly();
    testCapturesTopDownBgrxAsOpaqueBgra();
    testAllBlackDesktopSucceeds();
    testEveryGdiFailureReturnsSystemFailureAndCleansUp();
    testFlushFailureDoesNotPublishPixelsAndCleansUp();
    testZeroLastErrorIsStableEFail();
    testStaleLastErrorIsClearedBeforeEachFallibleCall();
    testRestoreFailuresDetachDcBeforeDeletingBitmap();
    testBudgetFailureStopsBeforeSecondDisplaysGdiWork();
    testInvalidSizeAndArithmeticOverflowAvoidGdi();
    testInjectedExceptionsAreContainedAndResourcesReleased();
    testDisplayOrderAndIndependentBuffersArePreserved();
    testRealGdiMemoryDcCaptureIsTopDownAndOpaque();
    return failureCount == 0 ? 0 : 1;
}
