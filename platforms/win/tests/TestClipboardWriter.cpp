#include "export/ClipboardWriter.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <type_traits>
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

std::unique_ptr<PixelBuffer> pattern()
{
    static MemoryBudget budget(1024U * 1024U);
    auto allocation = PixelBuffer::allocate(3, 2, budget);
    CHECK(allocation.value != nullptr);
    if (!allocation.value) {
        return nullptr;
    }

    const std::byte bytes[] = {
        std::byte{1}, std::byte{2}, std::byte{3}, std::byte{255},
        std::byte{20}, std::byte{40}, std::byte{60}, std::byte{128},
        std::byte{7}, std::byte{8}, std::byte{9}, std::byte{0},
        std::byte{10}, std::byte{11}, std::byte{12}, std::byte{255},
        std::byte{13}, std::byte{14}, std::byte{15}, std::byte{64},
        std::byte{0}, std::byte{0}, std::byte{0}, std::byte{0},
    };
    std::memcpy(allocation.value->data(), bytes, sizeof(bytes));
    return std::move(allocation.value);
}

class FakePngEncoder final : public PngEncoder {
public:
    PngMemoryResult encodeMemory(const PixelBuffer&) const noexcept override
    {
        if (failure.has_value()) {
            return *failure;
        }
        return bytes;
    }

    std::vector<std::byte> bytes{
        std::byte{0x89}, std::byte{'P'}, std::byte{'N'}, std::byte{'G'}};
    std::optional<ExportError> failure;
};

class FakeClipboardApi final : public ClipboardApi {
public:
    bool openClipboard(HWND) noexcept override
    {
        ++openCalls;
        if (openCalls <= openFailures) {
            error = ERROR_ACCESS_DENIED;
            return false;
        }
        return true;
    }

    bool emptyClipboard() noexcept override
    {
        ++emptyCalls;
        if (failEmpty) {
            error = ERROR_INVALID_FUNCTION;
            return false;
        }
        return true;
    }

    UINT registerClipboardFormat(const wchar_t* name) noexcept override
    {
        ++registerCalls;
        CHECK(std::wcscmp(name, L"PNG") == 0);
        if (failRegister) {
            error = ERROR_INVALID_FUNCTION;
            return 0U;
        }
        return pngFormat;
    }

    HGLOBAL allocateGlobal(std::size_t byteCount) noexcept override
    {
        ++allocateCalls;
        if (allocateCalls == failAllocationCall) {
            error = ERROR_NOT_ENOUGH_MEMORY;
            return nullptr;
        }
        const auto id = nextHandle++;
        blocks.emplace(id, std::vector<std::byte>(byteCount));
        return reinterpret_cast<HGLOBAL>(id);
    }

    void* lockGlobal(HGLOBAL handle) noexcept override
    {
        ++lockCalls;
        const auto id = reinterpret_cast<std::uintptr_t>(handle);
        auto found = blocks.find(id);
        if (found == blocks.end()) {
            error = ERROR_INVALID_HANDLE;
            return nullptr;
        }
        return found->second.data();
    }

    bool unlockGlobal(HGLOBAL) noexcept override
    {
        ++unlockCalls;
        error = unlockError;
        return unlockReturnsTrue;
    }

    void clearLastError() noexcept override
    {
        ++clearLastErrorCalls;
        error = ERROR_SUCCESS;
    }

    HGLOBAL freeGlobal(HGLOBAL handle) noexcept override
    {
        ++freeCalls;
        blocks.erase(reinterpret_cast<std::uintptr_t>(handle));
        return nullptr;
    }

    HANDLE setClipboardData(UINT format, HANDLE handle) noexcept override
    {
        ++setCalls;
        formats.push_back(format);
        if ((format == CF_DIBV5 && failDibSet) || (format == pngFormat && failPngSet)) {
            error = ERROR_INVALID_DATA;
            return nullptr;
        }
        transferred.push_back(reinterpret_cast<std::uintptr_t>(handle));
        blocks.erase(reinterpret_cast<std::uintptr_t>(handle));
        return handle;
    }

    bool closeClipboard() noexcept override
    {
        ++closeCalls;
        if (failClose) {
            error = ERROR_INVALID_HANDLE;
            return false;
        }
        return true;
    }

    DWORD lastError() const noexcept override { return error; }

    void sleep(DWORD milliseconds) noexcept override
    {
        sleeps.push_back(milliseconds);
    }

    int openFailures = 0;
    int failAllocationCall = 0;
    bool failEmpty = false;
    bool failRegister = false;
    bool failDibSet = false;
    bool failPngSet = false;
    bool failClose = false;
    int openCalls = 0;
    int emptyCalls = 0;
    int registerCalls = 0;
    int allocateCalls = 0;
    int lockCalls = 0;
    int unlockCalls = 0;
    int clearLastErrorCalls = 0;
    int setCalls = 0;
    int closeCalls = 0;
    int freeCalls = 0;
    DWORD error = ERROR_SUCCESS;
    DWORD unlockError = ERROR_SUCCESS;
    bool unlockReturnsTrue = true;
    UINT pngFormat = 0xC001U;
    std::uintptr_t nextHandle = 1U;
    std::map<std::uintptr_t, std::vector<std::byte>> blocks;
    std::vector<std::uintptr_t> transferred;
    std::vector<UINT> formats;
    std::vector<DWORD> sleeps;
};

void testBuildsTopDownBgraDibV5WithoutConsumingPixels()
{
    auto pixels = pattern();
    if (!pixels) {
        return;
    }
    const auto* originalAddress = pixels->data();
    std::array<std::byte, 24> originalBytes{};
    std::memcpy(originalBytes.data(), pixels->data(), originalBytes.size());
    const auto result = buildDibV5(*pixels);
    const auto* dib = std::get_if<std::vector<std::byte>>(&result);
    CHECK(dib != nullptr);
    if (dib == nullptr) {
        return;
    }

    CHECK(dib->size() == sizeof(BITMAPV5HEADER) + 24U);
    BITMAPV5HEADER header{};
    std::memcpy(&header, dib->data(), sizeof(header));
    CHECK(header.bV5Size == sizeof(BITMAPV5HEADER));
    CHECK(header.bV5Width == 3);
    CHECK(header.bV5Height == -2);
    CHECK(header.bV5Planes == 1U);
    CHECK(header.bV5BitCount == 32U);
    CHECK(header.bV5Compression == BI_BITFIELDS);
    CHECK(header.bV5SizeImage == 24U);
    CHECK(header.bV5RedMask == 0x00FF0000U);
    CHECK(header.bV5GreenMask == 0x0000FF00U);
    CHECK(header.bV5BlueMask == 0x000000FFU);
    CHECK(header.bV5AlphaMask == 0xFF000000U);
    CHECK(header.bV5CSType == LCS_sRGB);
    const std::array<std::byte, 24> expectedStraightBytes{
        std::byte{1}, std::byte{2}, std::byte{3}, std::byte{255},
        std::byte{40}, std::byte{80}, std::byte{120}, std::byte{128},
        std::byte{0}, std::byte{0}, std::byte{0}, std::byte{0},
        std::byte{10}, std::byte{11}, std::byte{12}, std::byte{255},
        std::byte{52}, std::byte{56}, std::byte{60}, std::byte{64},
        std::byte{0}, std::byte{0}, std::byte{0}, std::byte{0},
    };
    CHECK(std::memcmp(
        dib->data() + sizeof(header),
        expectedStraightBytes.data(),
        expectedStraightBytes.size()) == 0);
    CHECK(pixels->data() == originalAddress);
    CHECK(pixels->width() == 3);
    CHECK(std::memcmp(
        pixels->data(), originalBytes.data(), originalBytes.size()) == 0);
}

void testRetriesOpenExactlyThreeTimesWithRequiredBackoff()
{
    auto pixels = pattern();
    FakePngEncoder encoder;
    FakeClipboardApi api;
    api.openFailures = 2;

    const auto result = writeClipboard(*pixels, nullptr, encoder, api);
    CHECK(result.succeeded());
    CHECK(api.openCalls == 3);
    CHECK(api.sleeps == std::vector<DWORD>({10U, 25U}));
    CHECK(api.emptyCalls == 1);
    CHECK(api.closeCalls == 1);
    CHECK(api.setCalls == 2);
    CHECK(api.formats == std::vector<UINT>({CF_DIBV5, api.pngFormat}));
    CHECK(api.freeCalls == 0);
    CHECK(pixels->width() == 3);
}

void testOpenFailureCountsAndNoSleepAfterSuccess()
{
    for (int failures = 0; failures <= 3; ++failures) {
        auto pixels = pattern();
        FakePngEncoder encoder;
        FakeClipboardApi api;
        api.openFailures = failures;
        const auto result = writeClipboard(*pixels, nullptr, encoder, api);
        const int expectedCalls = failures < 3 ? failures + 1 : 3;
        CHECK(api.openCalls == expectedCalls);
        CHECK(api.sleeps.size() == static_cast<std::size_t>(failures < 3 ? failures : 2));
        CHECK(api.closeCalls == (failures < 3 ? 1 : 0));
        if (failures == 3) {
            CHECK(!result.succeeded());
            CHECK(result.primaryError.has_value());
            CHECK(result.primaryError->code == ExportErrorCode::clipboardOpenFailed);
            CHECK(result.primaryError->nativeCode == HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED));
        }
    }
}

void testEmptyFailureClosesAndDoesNotTransferOwnership()
{
    auto pixels = pattern();
    FakePngEncoder encoder;
    FakeClipboardApi api;
    api.failEmpty = true;
    const auto result = writeClipboard(*pixels, nullptr, encoder, api);
    CHECK(!result.succeeded());
    CHECK(result.primaryError->code == ExportErrorCode::clipboardEmptyFailed);
    CHECK(api.closeCalls == 1);
    CHECK(api.allocateCalls == 0);
    CHECK(api.setCalls == 0);
}

void testPartialSetFailureFreesOnlyUntransferredHandle()
{
    auto pixels = pattern();
    FakePngEncoder encoder;
    FakeClipboardApi api;
    api.failPngSet = true;
    const auto result = writeClipboard(*pixels, nullptr, encoder, api);
    CHECK(!result.succeeded());
    CHECK(result.partial());
    CHECK(result.dib == ClipboardFormatResult::written);
    CHECK(result.png == ClipboardFormatResult::failed);
    CHECK(result.primaryError->code == ExportErrorCode::clipboardSetPngFailed);
    CHECK(api.freeCalls == 1);
    CHECK(api.transferred.size() == 1U);
    CHECK(api.closeCalls == 1);
}

void testAllocationAndCloseFailuresAreExplicit()
{
    auto pixels = pattern();
    FakePngEncoder encoder;
    {
        FakeClipboardApi api;
        api.failAllocationCall = 1;
        const auto result = writeClipboard(*pixels, nullptr, encoder, api);
        CHECK(result.primaryError->code == ExportErrorCode::clipboardAllocationFailed);
        CHECK(api.setCalls == 1);
        CHECK(result.png == ClipboardFormatResult::written);
        CHECK(result.partial());
        CHECK(api.closeCalls == 1);
    }
    {
        FakeClipboardApi api;
        api.failClose = true;
        const auto result = writeClipboard(*pixels, nullptr, encoder, api);
        CHECK(!result.succeeded());
        CHECK(!result.primaryError.has_value());
        CHECK(result.closeError.has_value());
        CHECK(result.closeError->code == ExportErrorCode::clipboardCloseFailed);
        CHECK(result.dib == ClipboardFormatResult::written);
        CHECK(result.png == ClipboardFormatResult::written);
    }
}

void testGlobalUnlockFalseUsesLastErrorToDistinguishSuccessFromFailure()
{
    auto pixels = pattern();
    FakePngEncoder encoder;
    {
        FakeClipboardApi api;
        api.unlockReturnsTrue = false;
        const auto result = writeClipboard(*pixels, nullptr, encoder, api);
        CHECK(result.succeeded());
        CHECK(api.clearLastErrorCalls == 2);
        CHECK(api.unlockCalls == 2);
        CHECK(api.freeCalls == 0);
    }
    {
        FakeClipboardApi api;
        api.unlockReturnsTrue = false;
        api.unlockError = ERROR_INVALID_HANDLE;
        const auto result = writeClipboard(*pixels, nullptr, encoder, api);
        CHECK(!result.succeeded());
        CHECK(result.primaryError.has_value());
        CHECK(result.primaryError->code == ExportErrorCode::clipboardLockFailed);
        CHECK(result.primaryError->nativeCode == HRESULT_FROM_WIN32(ERROR_INVALID_HANDLE));
        CHECK(api.clearLastErrorCalls == 2);
        CHECK(api.unlockCalls == 2);
        CHECK(api.freeCalls == 2);
        CHECK(api.setCalls == 0);
    }
}

void testPngEncodingFailureStillWritesDibAsStructuredPartialFailure()
{
    auto pixels = pattern();
    FakePngEncoder encoder;
    encoder.failure = ExportError{ExportErrorCode::imagingFailure, WINCODEC_ERR_CODECNOTHUMBNAIL};
    FakeClipboardApi api;
    const auto result = writeClipboard(*pixels, nullptr, encoder, api);
    CHECK(result.partial());
    CHECK(result.dib == ClipboardFormatResult::written);
    CHECK(result.png == ClipboardFormatResult::failed);
    CHECK(result.primaryError->code == ExportErrorCode::imagingFailure);
    CHECK(api.setCalls == 1);
    CHECK(api.closeCalls == 1);
}

void testCloseFailureRemainsVisibleAfterTwoEarlierFailures()
{
    auto pixels = pattern();
    FakePngEncoder encoder;
    encoder.failure = ExportError{ExportErrorCode::imagingFailure, WINCODEC_ERR_STREAMWRITE};
    FakeClipboardApi api;
    api.failDibSet = true;
    api.failClose = true;
    const auto result = writeClipboard(*pixels, nullptr, encoder, api);
    CHECK(!result.succeeded());
    CHECK(result.primaryError.has_value());
    CHECK(result.primaryError->code == ExportErrorCode::imagingFailure);
    CHECK(result.secondaryError.has_value());
    CHECK(result.secondaryError->code == ExportErrorCode::clipboardSetDibFailed);
    CHECK(result.closeError.has_value());
    CHECK(result.closeError->code == ExportErrorCode::clipboardCloseFailed);
    CHECK(result.closeError->nativeCode == HRESULT_FROM_WIN32(ERROR_INVALID_HANDLE));
    CHECK(result.secondaryError->code != ExportErrorCode::clipboardCloseFailed);
    CHECK(api.closeCalls == 1);
    CHECK(api.freeCalls == 1);
}

} // namespace

int main()
{
    static_assert(noexcept(convertPremultipliedToStraightBgra(
        std::declval<const PixelBuffer&>())));
    static_assert(noexcept(buildDibV5(std::declval<const PixelBuffer&>())));
    static_assert(noexcept(writeClipboard(
        std::declval<const PixelBuffer&>(),
        nullptr,
        std::declval<const PngEncoder&>(),
        std::declval<ClipboardApi&>())));
    testBuildsTopDownBgraDibV5WithoutConsumingPixels();
    testRetriesOpenExactlyThreeTimesWithRequiredBackoff();
    testOpenFailureCountsAndNoSleepAfterSuccess();
    testEmptyFailureClosesAndDoesNotTransferOwnership();
    testPartialSetFailureFreesOnlyUntransferredHandle();
    testAllocationAndCloseFailuresAreExplicit();
    testGlobalUnlockFalseUsesLastErrorToDistinguishSuccessFromFailure();
    testPngEncodingFailureStillWritesDibAsStructuredPartialFailure();
    testCloseFailureRemainsVisibleAfterTwoEarlierFailures();
    return failureCount == 0 ? 0 : 1;
}
