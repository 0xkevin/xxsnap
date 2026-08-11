#include "export/PngWriter.h"

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <type_traits>
#include <vector>

namespace {

using namespace xxsnap::win;
using Microsoft::WRL::ComPtr;
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
    // Premultiplied BGRA: use opaque or exactly divisible values.
    const std::byte bytes[] = {
        std::byte{10}, std::byte{20}, std::byte{30}, std::byte{255},
        std::byte{20}, std::byte{40}, std::byte{60}, std::byte{128},
        std::byte{0}, std::byte{0}, std::byte{0}, std::byte{0},
        std::byte{70}, std::byte{80}, std::byte{90}, std::byte{255},
        std::byte{25}, std::byte{50}, std::byte{75}, std::byte{85},
        std::byte{1}, std::byte{2}, std::byte{3}, std::byte{255},
    };
    std::memcpy(allocation.value->data(), bytes, sizeof(bytes));
    return std::move(allocation.value);
}

const std::array<std::byte, 24>& expectedStraightPattern()
{
    static const std::array<std::byte, 24> expected{
        std::byte{10}, std::byte{20}, std::byte{30}, std::byte{255},
        std::byte{40}, std::byte{80}, std::byte{120}, std::byte{128},
        std::byte{0}, std::byte{0}, std::byte{0}, std::byte{0},
        std::byte{70}, std::byte{80}, std::byte{90}, std::byte{255},
        std::byte{75}, std::byte{150}, std::byte{225}, std::byte{85},
        std::byte{1}, std::byte{2}, std::byte{3}, std::byte{255},
    };
    return expected;
}

std::vector<std::byte> decodePng(const std::vector<std::byte>& encoded, UINT& width, UINT& height)
{
    ComPtr<IWICImagingFactory> factory;
    HRESULT hr = CoCreateInstance(
        CLSID_WICImagingFactory,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory));
    CHECK(SUCCEEDED(hr));
    HGLOBAL storage = GlobalAlloc(GMEM_MOVEABLE, encoded.size());
    CHECK(storage != nullptr);
    void* memory = GlobalLock(storage);
    CHECK(memory != nullptr);
    if (memory != nullptr) {
        std::memcpy(memory, encoded.data(), encoded.size());
        GlobalUnlock(storage);
    }
    ComPtr<IStream> stream;
    hr = CreateStreamOnHGlobal(storage, TRUE, &stream);
    CHECK(SUCCEEDED(hr));
    ComPtr<IWICBitmapDecoder> decoder;
    hr = factory->CreateDecoderFromStream(
        stream.Get(), nullptr, WICDecodeMetadataCacheOnLoad, &decoder);
    CHECK(SUCCEEDED(hr));
    ComPtr<IWICBitmapFrameDecode> frame;
    hr = decoder->GetFrame(0U, &frame);
    CHECK(SUCCEEDED(hr));
    hr = frame->GetSize(&width, &height);
    CHECK(SUCCEEDED(hr));
    ComPtr<IWICFormatConverter> converter;
    hr = factory->CreateFormatConverter(&converter);
    CHECK(SUCCEEDED(hr));
    hr = converter->Initialize(
        frame.Get(),
        GUID_WICPixelFormat32bppBGRA,
        WICBitmapDitherTypeNone,
        nullptr,
        0.0,
        WICBitmapPaletteTypeCustom);
    CHECK(SUCCEEDED(hr));
    std::vector<std::byte> pixels(static_cast<std::size_t>(width) * height * 4U);
    hr = converter->CopyPixels(
        nullptr,
        width * 4U,
        static_cast<UINT>(pixels.size()),
        reinterpret_cast<BYTE*>(pixels.data()));
    CHECK(SUCCEEDED(hr));
    return pixels;
}

std::uint32_t readBigEndian32(const std::byte* bytes)
{
    return (std::to_integer<std::uint32_t>(bytes[0]) << 24U)
        | (std::to_integer<std::uint32_t>(bytes[1]) << 16U)
        | (std::to_integer<std::uint32_t>(bytes[2]) << 8U)
        | std::to_integer<std::uint32_t>(bytes[3]);
}

std::size_t pngEndOffset(const std::vector<std::byte>& encoded)
{
    std::size_t offset = 8U;
    while (offset <= encoded.size() && encoded.size() - offset >= 12U) {
        const auto length = static_cast<std::size_t>(readBigEndian32(encoded.data() + offset));
        if (length > encoded.size() - offset - 12U) {
            return 0U;
        }
        const bool isEnd = encoded[offset + 4U] == std::byte{'I'}
            && encoded[offset + 5U] == std::byte{'E'}
            && encoded[offset + 6U] == std::byte{'N'}
            && encoded[offset + 7U] == std::byte{'D'};
        offset += 12U + length;
        if (isEnd) {
            return offset;
        }
    }
    return 0U;
}

class FakeEncoder final : public PngEncoder {
public:
    PngMemoryResult encodeMemory(const PixelBuffer&) const noexcept override
    {
        ++memoryCalls;
        return result;
    }

    mutable int memoryCalls = 0;
    PngMemoryResult result = std::vector<std::byte>{
        std::byte{0x89}, std::byte{'P'}, std::byte{'N'}, std::byte{'G'}};
};

enum class FileOperation {
    reserve,
    write,
    flush,
    close,
    remove,
    move,
};

class FakeFileApi final : public AtomicFileApi {
public:
    bool temporaryNonce(
        wchar_t* buffer,
        std::size_t capacity,
        HRESULT& nativeCode) noexcept override
    {
        ++nonceCalls;
        if (failNonce) {
            nativeCode = E_FAIL;
            return false;
        }
        const int written = swprintf_s(buffer, capacity, L"nonce-%02d", nonceCalls);
        nativeCode = written > 0 ? S_OK : E_FAIL;
        return written > 0;
    }

    TemporaryFileReservation reserveTemporary(const wchar_t* path) noexcept override
    {
        ++reserveCalls;
        operations.push_back(FileOperation::reserve);
        candidates.emplace_back(path);
        if (reserveCalls <= collisions) {
            return {
                TemporaryFileReservationStatus::collision,
                INVALID_HANDLE_VALUE,
                ERROR_FILE_EXISTS};
        }
        if (failReserve) {
            return {
                TemporaryFileReservationStatus::failed,
                INVALID_HANDLE_VALUE,
                ERROR_ACCESS_DENIED};
        }
        const auto token = reinterpret_cast<HANDLE>(nextToken++);
        reservedTokens.push_back(token);
        return {TemporaryFileReservationStatus::created, token, ERROR_SUCCESS};
    }

    bool writeFile(
        HANDLE token,
        const std::byte* bytes,
        DWORD byteCount,
        DWORD& written,
        DWORD& nativeCode) noexcept override
    {
        ++writeCalls;
        operations.push_back(FileOperation::write);
        writeTokens.push_back(token);
        if (failWrite) {
            written = 0U;
            nativeCode = ERROR_WRITE_FAULT;
            return false;
        }
        written = std::min(byteCount, maximumWriteSize);
        writtenBytes.insert(writtenBytes.end(), bytes, bytes + written);
        nativeCode = ERROR_SUCCESS;
        return true;
    }

    bool flushFile(HANDLE token, DWORD& nativeCode) noexcept override
    {
        ++flushCalls;
        operations.push_back(FileOperation::flush);
        flushTokens.push_back(token);
        nativeCode = failFlush ? ERROR_WRITE_FAULT : ERROR_SUCCESS;
        return !failFlush;
    }

    bool closeFile(HANDLE token, DWORD& nativeCode) noexcept override
    {
        ++closeCalls;
        operations.push_back(FileOperation::close);
        closeTokens.push_back(token);
        nativeCode = failClose ? ERROR_INVALID_HANDLE : ERROR_SUCCESS;
        return !failClose;
    }

    bool deleteFile(const wchar_t* path, DWORD& nativeCode) noexcept override
    {
        ++deleteCalls;
        operations.push_back(FileOperation::remove);
        deleted.emplace_back(path);
        nativeCode = failDelete ? ERROR_ACCESS_DENIED : ERROR_SUCCESS;
        return !failDelete;
    }

    bool moveFile(const wchar_t* from, const wchar_t* to, DWORD flags, DWORD& nativeCode) noexcept override
    {
        ++moveCalls;
        operations.push_back(FileOperation::move);
        moveFrom = from;
        moveTo = to;
        moveFlags = flags;
        nativeCode = failMove ? ERROR_ACCESS_DENIED : ERROR_SUCCESS;
        return !failMove;
    }

    int collisions = 0;
    bool failNonce = false;
    bool failReserve = false;
    bool failWrite = false;
    bool failFlush = false;
    bool failClose = false;
    bool failDelete = false;
    bool failMove = false;
    DWORD maximumWriteSize = std::numeric_limits<DWORD>::max();
    int nonceCalls = 0;
    int reserveCalls = 0;
    int writeCalls = 0;
    int flushCalls = 0;
    int closeCalls = 0;
    int deleteCalls = 0;
    int moveCalls = 0;
    DWORD moveFlags = 0U;
    std::uintptr_t nextToken = 1U;
    std::vector<std::wstring> candidates;
    std::vector<FileOperation> operations;
    std::vector<HANDLE> reservedTokens;
    std::vector<HANDLE> writeTokens;
    std::vector<HANDLE> flushTokens;
    std::vector<HANDLE> closeTokens;
    std::vector<std::byte> writtenBytes;
    std::vector<std::wstring> deleted;
    std::wstring moveFrom;
    std::wstring moveTo;
};

void testWicMemoryRoundTripPreservesDimensionsAndAlpha()
{
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    CHECK(initialized == S_OK || initialized == S_FALSE);
    auto pixels = pattern();
    WicPngEncoder encoder;
    const auto result = encoder.encodeMemory(*pixels);
    const auto* encoded = std::get_if<std::vector<std::byte>>(&result);
    CHECK(encoded != nullptr);
    if (encoded != nullptr) {
        CHECK(encoded->size() > 8U);
        const std::array<std::byte, 8> signature{
            std::byte{0x89}, std::byte{0x50}, std::byte{0x4E}, std::byte{0x47},
            std::byte{0x0D}, std::byte{0x0A}, std::byte{0x1A}, std::byte{0x0A}};
        CHECK(std::memcmp(encoded->data(), signature.data(), signature.size()) == 0);
        CHECK(pngEndOffset(*encoded) == encoded->size());
        UINT width = 0;
        UINT height = 0;
        const auto decoded = decodePng(*encoded, width, height);
        CHECK(width == 3U);
        CHECK(height == 2U);
        CHECK(decoded.size() == 24U);
        CHECK(std::equal(
            decoded.begin(), decoded.end(), expectedStraightPattern().begin()));
    }
    CHECK(pixels->width() == 3);
    if (initialized == S_OK || initialized == S_FALSE) {
        CoUninitialize();
    }
}

void testAtomicCommitOnlyAfterEncoderSuccess()
{
    auto pixels = pattern();
    FakeEncoder encoder;
    FakeFileApi files;
    const auto result = savePngAtomically(*pixels, L"C:\\captures\\shot.png", encoder, files);
    CHECK(!result.has_value());
    CHECK(files.reserveCalls == 1);
    CHECK(encoder.memoryCalls == 1);
    CHECK(files.writeCalls == 1);
    CHECK(files.flushCalls == 1);
    CHECK(files.closeCalls == 1);
    CHECK(files.writeTokens == files.reservedTokens);
    CHECK(files.flushTokens == files.reservedTokens);
    CHECK(files.closeTokens == files.reservedTokens);
    CHECK(files.operations == std::vector<FileOperation>({
        FileOperation::reserve,
        FileOperation::write,
        FileOperation::flush,
        FileOperation::close,
        FileOperation::move}));
    const auto* encoded = std::get_if<std::vector<std::byte>>(&encoder.result);
    CHECK(encoded != nullptr);
    CHECK(encoded != nullptr && files.writtenBytes == *encoded);
    CHECK(files.moveCalls == 1);
    CHECK(files.moveFrom == files.candidates.front());
    CHECK(files.moveTo == L"C:\\captures\\shot.png");
    CHECK(files.moveFlags == (MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH));
    CHECK(files.deleteCalls == 0);
}

void testPartialWritesUseTheReservedTokenUntilComplete()
{
    auto pixels = pattern();
    FakeEncoder encoder;
    encoder.result = std::vector<std::byte>{
        std::byte{1}, std::byte{2}, std::byte{3}, std::byte{4}, std::byte{5}};
    FakeFileApi files;
    files.maximumWriteSize = 2U;
    const auto result = savePngAtomically(*pixels, L"shot.png", encoder, files);
    CHECK(!result.has_value());
    CHECK(files.writeCalls == 3);
    CHECK(files.writtenBytes == std::get<std::vector<std::byte>>(encoder.result));
    CHECK(std::all_of(
        files.writeTokens.begin(), files.writeTokens.end(),
        [&](HANDLE token) { return token == files.reservedTokens.front(); }));
}

void testEncodingAndCommitFailuresCleanTemporaryFile()
{
    auto pixels = pattern();
    {
        FakeEncoder encoder;
        encoder.result = ExportError{ExportErrorCode::imagingFailure, WINCODEC_ERR_STREAMWRITE};
        FakeFileApi files;
        const auto result = savePngAtomically(*pixels, L"C:\\captures\\shot.png", encoder, files);
        CHECK(result.has_value());
        CHECK(result->code == ExportErrorCode::imagingFailure);
        CHECK(files.moveCalls == 0);
        CHECK(files.closeCalls == 1);
        CHECK(files.deleteCalls == 1);
        CHECK(files.deleted.front() == files.candidates.front());
    }
    {
        FakeEncoder encoder;
        encoder.result = std::vector<std::byte>{};
        FakeFileApi files;
        const auto result = savePngAtomically(*pixels, L"C:\\captures\\shot.png", encoder, files);
        CHECK(result.has_value());
        CHECK(result->code == ExportErrorCode::imagingFailure);
        CHECK(result->nativeCode == WINCODEC_ERR_BADIMAGE);
        CHECK(files.writeCalls == 0);
        CHECK(files.flushCalls == 0);
        CHECK(files.moveCalls == 0);
        CHECK(files.closeCalls == 1);
        CHECK(files.deleteCalls == 1);
    }
    {
        FakeEncoder encoder;
        FakeFileApi files;
        files.failMove = true;
        const auto result = savePngAtomically(*pixels, L"C:\\captures\\shot.png", encoder, files);
        CHECK(result.has_value());
        CHECK(result->code == ExportErrorCode::fileCommitFailed);
        CHECK(result->nativeCode == HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED));
        CHECK(files.deleteCalls == 1);
    }
}

void testWriteFlushAndCloseFailuresCloseAndDeleteTemporaryFile()
{
    auto pixels = pattern();
    for (int failure = 0; failure < 3; ++failure) {
        FakeEncoder encoder;
        FakeFileApi files;
        files.failWrite = failure == 0;
        files.failFlush = failure == 1;
        files.failClose = failure == 2;
        const auto result = savePngAtomically(*pixels, L"shot.png", encoder, files);
        CHECK(result.has_value());
        const auto expected = failure == 0 ? ExportErrorCode::fileWriteFailed
            : failure == 1 ? ExportErrorCode::fileFlushFailed
                           : ExportErrorCode::fileCloseFailed;
        CHECK(result->code == expected);
        CHECK(files.closeCalls == 1);
        CHECK(files.deleteCalls == 1);
        CHECK(files.moveCalls == 0);
    }
}

void testCloseAndDeleteFailuresRemainVisibleAfterEncodingFailure()
{
    auto pixels = pattern();
    FakeEncoder encoder;
    encoder.result = ExportError{ExportErrorCode::imagingFailure, WINCODEC_ERR_STREAMWRITE};
    FakeFileApi files;
    files.failClose = true;
    files.failDelete = true;
    const auto result = savePngAtomically(*pixels, L"shot.png", encoder, files);
    CHECK(result.has_value());
    CHECK(result->code == ExportErrorCode::imagingFailure);
    CHECK(result->additionalErrorCount == 2U);
    CHECK(result->additionalErrors[0].code == ExportErrorCode::fileCloseFailed);
    CHECK(result->additionalErrors[1].code == ExportErrorCode::fileCleanupFailed);
}

void testCleanupFailureIsReportedWithoutHidingPrimaryFailure()
{
    auto pixels = pattern();
    FakeEncoder encoder;
    encoder.result = ExportError{ExportErrorCode::imagingFailure, WINCODEC_ERR_STREAMWRITE};
    FakeFileApi files;
    files.failDelete = true;
    const auto result = savePngAtomically(*pixels, L"shot.png", encoder, files);
    CHECK(result.has_value());
    CHECK(result->code == ExportErrorCode::imagingFailure);
    CHECK(result->additionalErrorCount == 1U);
    CHECK(result->additionalErrors[0].code == ExportErrorCode::fileCleanupFailed);
    CHECK(result->additionalErrors[0].nativeCode == HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED));
}

void testTemporaryNameCollisionsHaveBoundedRetries()
{
    auto pixels = pattern();
    FakeEncoder encoder;
    FakeFileApi files;
    files.collisions = static_cast<int>(maximumTemporaryFileAttempts);
    const auto result = savePngAtomically(*pixels, L"shot.png", encoder, files);
    CHECK(result.has_value());
    CHECK(result->code == ExportErrorCode::temporaryNameExhausted);
    CHECK(files.reserveCalls == static_cast<int>(maximumTemporaryFileAttempts));
    CHECK(std::adjacent_find(
        files.candidates.begin(), files.candidates.end())
        == files.candidates.end());
    CHECK(encoder.memoryCalls == 0);
    CHECK(files.moveCalls == 0);
    CHECK(files.deleteCalls == 0);
}

void testTemporaryNameUsesIndependentShortBasename()
{
    auto pixels = pattern();
    FakeEncoder encoder;
    FakeFileApi files;
    const std::wstring longBasename(240U, L'a');
    const std::wstring target = L"C:\\captures\\" + longBasename + L".png";
    const auto result = savePngAtomically(*pixels, target.c_str(), encoder, files);
    CHECK(!result.has_value());
    CHECK(files.candidates.size() == 1U);
    const auto separator = files.candidates.front().find_last_of(L"\\/");
    const auto basename = files.candidates.front().substr(separator + 1U);
    CHECK(basename.size() < 80U);
    CHECK(files.candidates.front().substr(0U, separator + 1U)
        == L"C:\\captures\\");
}

void testNonceFailureDoesNotCreateAFile()
{
    auto pixels = pattern();
    FakeEncoder encoder;
    FakeFileApi files;
    files.failNonce = true;
    const auto result = savePngAtomically(*pixels, L"shot.png", encoder, files);
    CHECK(result.has_value());
    CHECK(result->code == ExportErrorCode::temporaryNonceFailed);
    CHECK(files.reserveCalls == 0);
    CHECK(encoder.memoryCalls == 0);
}

class FakeGlobalMemoryApi final : public GlobalMemoryApi {
public:
    SIZE_T globalSize(HGLOBAL) noexcept override { return storage.size(); }

    const void* lockGlobal(HGLOBAL) noexcept override
    {
        ++lockCalls;
        return storage.data();
    }

    BOOL unlockGlobal(HGLOBAL) noexcept override
    {
        ++unlockCalls;
        error = unlockError;
        return unlockReturnsTrue ? TRUE : FALSE;
    }

    void clearLastError() noexcept override { error = ERROR_SUCCESS; }
    DWORD lastError() const noexcept override { return error; }

    std::vector<std::byte> storage = std::vector<std::byte>(1024U * 1024U);
    bool unlockReturnsTrue = false;
    DWORD unlockError = ERROR_SUCCESS;
    DWORD error = ERROR_SUCCESS;
    int lockCalls = 0;
    int unlockCalls = 0;
};

void testGlobalUnlockFalseWithSuccessIsAcceptedAndRealFailureIsReported()
{
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    CHECK(initialized == S_OK || initialized == S_FALSE);
    auto pixels = pattern();
    {
        FakeGlobalMemoryApi globals;
        WicPngEncoder encoder(globals);
        const auto result = encoder.encodeMemory(*pixels);
        CHECK(std::holds_alternative<std::vector<std::byte>>(result));
        CHECK(std::get<std::vector<std::byte>>(result).size()
            < globals.storage.size());
        CHECK(globals.lockCalls == 1);
        CHECK(globals.unlockCalls == 1);
    }
    {
        FakeGlobalMemoryApi globals;
        globals.unlockError = ERROR_INVALID_HANDLE;
        WicPngEncoder encoder(globals);
        const auto result = encoder.encodeMemory(*pixels);
        const auto* error = std::get_if<ExportError>(&result);
        CHECK(error != nullptr);
        CHECK(error != nullptr
            && error->code == ExportErrorCode::globalMemoryUnlockFailed);
        CHECK(error != nullptr
            && error->nativeCode == HRESULT_FROM_WIN32(ERROR_INVALID_HANDLE));
    }
    if (initialized == S_OK || initialized == S_FALSE) {
        CoUninitialize();
    }
}

void testExistingTargetSurvivesRealEncodingFailureAndTempIsCleaned()
{
    auto pixels = pattern();
    wchar_t directoryBuffer[MAX_PATH]{};
    const DWORD length = GetTempPathW(MAX_PATH, directoryBuffer);
    CHECK(length > 0U && length < MAX_PATH);
    const std::filesystem::path directory = std::filesystem::path(directoryBuffer)
        / (L"xxsnap-png-test-" + std::to_wstring(GetCurrentProcessId()));
    std::error_code ignored;
    std::filesystem::create_directories(directory, ignored);
    const auto target = directory / L"existing.png";
    const std::array<unsigned char, 8> original{{1, 3, 3, 7, 9, 2, 4, 6}};
    {
        std::ofstream stream(target, std::ios::binary | std::ios::trunc);
        stream.write(reinterpret_cast<const char*>(original.data()), original.size());
    }
    FakeEncoder encoder;
    encoder.result = ExportError{ExportErrorCode::imagingFailure, WINCODEC_ERR_STREAMWRITE};
    Win32AtomicFileApi files;
    const auto result = savePngAtomically(*pixels, target.c_str(), encoder, files);
    CHECK(result.has_value());
    std::array<unsigned char, 8> after{};
    {
        std::ifstream stream(target, std::ios::binary);
        stream.read(reinterpret_cast<char*>(after.data()), after.size());
    }
    CHECK(after == original);
    std::size_t entryCount = 0;
    for (const auto& entry : std::filesystem::directory_iterator(directory, ignored)) {
        (void)entry;
        ++entryCount;
    }
    CHECK(entryCount == 1U);
    std::filesystem::remove_all(directory, ignored);
}

void testRealAtomicWicFileRoundTrip()
{
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    CHECK(initialized == S_OK || initialized == S_FALSE);
    auto pixels = pattern();
    wchar_t directoryBuffer[MAX_PATH]{};
    const DWORD length = GetTempPathW(MAX_PATH, directoryBuffer);
    CHECK(length > 0U && length < MAX_PATH);
    const std::filesystem::path directory = std::filesystem::path(directoryBuffer)
        / (L"xxsnap-png-roundtrip-" + std::to_wstring(GetCurrentProcessId()));
    std::error_code ignored;
    std::filesystem::create_directories(directory, ignored);
    const auto target = directory / L"capture.png";
    const std::array<unsigned char, 8> oldContents{{9, 8, 7, 6, 5, 4, 3, 2}};
    {
        std::ofstream oldTarget(target, std::ios::binary | std::ios::trunc);
        oldTarget.write(
            reinterpret_cast<const char*>(oldContents.data()),
            oldContents.size());
    }
    const auto result = savePngAtomically(*pixels, target.c_str());
    CHECK(!result.has_value());
    CHECK(std::filesystem::exists(target));
    const DWORD attributes = GetFileAttributesW(target.c_str());
    CHECK(attributes != INVALID_FILE_ATTRIBUTES);
    CHECK((attributes & FILE_ATTRIBUTE_TEMPORARY) == 0U);

    std::ifstream stream(target, std::ios::binary | std::ios::ate);
    const auto lengthInBytes = stream.tellg();
    CHECK(lengthInBytes > 8);
    std::vector<std::byte> encoded(static_cast<std::size_t>(lengthInBytes));
    stream.seekg(0);
    stream.read(reinterpret_cast<char*>(encoded.data()), lengthInBytes);
    UINT width = 0U;
    UINT height = 0U;
    const auto decoded = decodePng(encoded, width, height);
    CHECK(width == 3U);
    CHECK(height == 2U);
    CHECK(decoded.size() == 24U);
    CHECK(std::equal(
        decoded.begin(), decoded.end(), expectedStraightPattern().begin()));

    std::filesystem::remove_all(directory, ignored);
    if (initialized == S_OK || initialized == S_FALSE) {
        CoUninitialize();
    }
}

void testNullAndEmptyPathsFailWithoutFileCalls()
{
    auto pixels = pattern();
    FakeEncoder encoder;
    FakeFileApi files;
    const auto nullResult = savePngAtomically(*pixels, nullptr, encoder, files);
    const auto emptyResult = savePngAtomically(*pixels, L"", encoder, files);
    CHECK(nullResult->code == ExportErrorCode::invalidArgument);
    CHECK(emptyResult->code == ExportErrorCode::invalidArgument);
    CHECK(files.reserveCalls == 0);
}

} // namespace

int main()
{
    static_assert(std::is_nothrow_move_constructible_v<ExportError>);
    static_assert(noexcept(std::declval<const WicPngEncoder&>().encodeMemory(
        std::declval<const PixelBuffer&>())));
    static_assert(noexcept(savePngAtomically(
        std::declval<const PixelBuffer&>(),
        L"x.png",
        std::declval<const PngEncoder&>(),
        std::declval<AtomicFileApi&>())));
    testWicMemoryRoundTripPreservesDimensionsAndAlpha();
    testAtomicCommitOnlyAfterEncoderSuccess();
    testPartialWritesUseTheReservedTokenUntilComplete();
    testEncodingAndCommitFailuresCleanTemporaryFile();
    testWriteFlushAndCloseFailuresCloseAndDeleteTemporaryFile();
    testCloseAndDeleteFailuresRemainVisibleAfterEncodingFailure();
    testCleanupFailureIsReportedWithoutHidingPrimaryFailure();
    testTemporaryNameCollisionsHaveBoundedRetries();
    testTemporaryNameUsesIndependentShortBasename();
    testNonceFailureDoesNotCreateAFile();
    testGlobalUnlockFalseWithSuccessIsAcceptedAndRealFailureIsReported();
    testExistingTargetSurvivesRealEncodingFailureAndTempIsCleaned();
    testRealAtomicWicFileRoundTrip();
    testNullAndEmptyPathsFailWithoutFileCalls();
    return failureCount == 0 ? 0 : 1;
}
