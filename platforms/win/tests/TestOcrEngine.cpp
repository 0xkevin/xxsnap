#include "ocr/OcrEngine.h"
#include "ocr/QrCodeEngine.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>

#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

using namespace xxsnap::win;

namespace {

int failureCount = 0;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                      \
            std::cerr << __FILE__ << ':' << __LINE__                            \
                      << ": CHECK failed: " #condition << '\n';                 \
            ++failureCount;                                                      \
        }                                                                        \
    } while (false)

std::unique_ptr<PixelBuffer> loadFixture(const wchar_t* path)
{
    std::ifstream stream(path, std::ios::binary);
    if (!stream) return nullptr;
    BITMAPFILEHEADER fileHeader{};
    BITMAPV5HEADER info{};
    stream.read(reinterpret_cast<char*>(&fileHeader), sizeof(fileHeader));
    stream.read(reinterpret_cast<char*>(&info), sizeof(info));
    if (!stream || fileHeader.bfType != 0x4D42U
        || info.bV5Size < sizeof(BITMAPINFOHEADER)
        || info.bV5Width <= 0 || info.bV5Height == 0
        || info.bV5BitCount != 32U
        || (info.bV5Compression != BI_RGB && info.bV5Compression != BI_BITFIELDS)) {
        return nullptr;
    }
    const auto width = static_cast<std::int64_t>(info.bV5Width);
    const auto height = static_cast<std::int64_t>(
        info.bV5Height < 0 ? -info.bV5Height : info.bV5Height);
    const auto sourceStride = (static_cast<std::uint64_t>(width) * 4U + 3U) & ~3ULL;
    std::vector<std::byte> source(
        static_cast<std::size_t>(sourceStride * static_cast<std::uint64_t>(height)));
    stream.seekg(fileHeader.bfOffBits);
    stream.read(reinterpret_cast<char*>(source.data()),
        static_cast<std::streamsize>(source.size()));
    if (!stream) return nullptr;
    MemoryBudget budget(16U * 1024U * 1024U);
    auto allocation = PixelBuffer::allocate(width, height, budget);
    if (!allocation.value) return nullptr;

    for (std::int64_t row = 0; row < height; ++row) {
        const auto sourceRow = info.bV5Height < 0 ? row : height - 1 - row;
        std::memcpy(
            allocation.value->data()
                + static_cast<std::size_t>(row) * allocation.value->stride(),
            source.data() + static_cast<std::size_t>(sourceRow * sourceStride),
            static_cast<std::size_t>(width) * 4U);
    }
    return std::move(allocation.value);
}

void testRecognizesQrFixtureAndTakesPriorityOverText()
{
    const auto fixture = loadFixture(L"qr-xxsnap-2026.bmp");
    CHECK(fixture != nullptr);
    if (!fixture) return;

    const auto qr = recognizeQrCode(*fixture);
    CHECK(qr.has_value());
    CHECK(qr == L"XXSNAP-QR-2026");

    const auto result = recognizeText(*fixture);
    CHECK(result.status == OcrStatus::completed);
    CHECK(result.contentKind == OcrContentKind::qrCode);
    CHECK(result.text == L"XXSNAP-QR-2026");
}

void testRejectsPixelBufferWithoutQrCode()
{
    MemoryBudget budget(1024U);
    auto allocation = PixelBuffer::allocate(8, 8, budget);
    CHECK(allocation.value != nullptr);
    if (!allocation.value) return;
    std::memset(allocation.value->data(), 0xFF, allocation.value->byteCount());
    CHECK(!recognizeQrCode(*allocation.value).has_value());
}

} // namespace

int main()
{
    testRecognizesQrFixtureAndTakesPriorityOverText();
    testRejectsPixelBufferWithoutQrCode();
    return failureCount == 0 ? 0 : 1;
}
