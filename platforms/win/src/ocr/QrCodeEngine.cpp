#include "ocr/QrCodeEngine.h"

extern "C" {
#include <quirc.h>
}

#include <Windows.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>

namespace xxsnap::win {
namespace {

std::optional<std::wstring> utf8Text(
    const std::uint8_t* bytes, std::size_t byteCount)
{
    if (bytes == nullptr || byteCount == 0U
        || byteCount > static_cast<std::size_t>((std::numeric_limits<int>::max)())) {
        return std::nullopt;
    }
    const auto required = MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS,
        reinterpret_cast<const char*>(bytes),
        static_cast<int>(byteCount), nullptr, 0);
    if (required <= 0) return std::nullopt;
    std::wstring result(static_cast<std::size_t>(required), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8, MB_ERR_INVALID_CHARS,
            reinterpret_cast<const char*>(bytes),
            static_cast<int>(byteCount), result.data(), required) != required) {
        return std::nullopt;
    }
    return result;
}

struct QuircDeleter {
    void operator()(quirc* value) const noexcept { quirc_destroy(value); }
};

} // namespace

std::optional<std::wstring> recognizeQrCode(
    const PixelBuffer& pixels) noexcept
{
    if (pixels.width() <= 0 || pixels.height() <= 0
        || pixels.width() > (std::numeric_limits<int>::max)()
        || pixels.height() > (std::numeric_limits<int>::max)()
        || pixels.stride() < static_cast<std::uint64_t>(pixels.width()) * 4U) {
        return std::nullopt;
    }
    try {
        std::unique_ptr<quirc, QuircDeleter> decoder(quirc_new());
        if (!decoder || quirc_resize(decoder.get(),
                static_cast<int>(pixels.width()),
                static_cast<int>(pixels.height())) < 0) {
            return std::nullopt;
        }
        auto* gray = quirc_begin(decoder.get(), nullptr, nullptr);
        if (gray == nullptr) return std::nullopt;
        for (std::int64_t y = 0; y < pixels.height(); ++y) {
            const auto* source = pixels.data()
                + static_cast<std::size_t>(y) * pixels.stride();
            auto* destination = gray
                + static_cast<std::size_t>(y) * pixels.width();
            for (std::int64_t x = 0; x < pixels.width(); ++x) {
                const auto* pixel = source + static_cast<std::size_t>(x) * 4U;
                const auto blue = static_cast<unsigned char>(pixel[0]);
                const auto green = static_cast<unsigned char>(pixel[1]);
                const auto red = static_cast<unsigned char>(pixel[2]);
                destination[x] = static_cast<std::uint8_t>(
                    (77U * red + 150U * green + 29U * blue) >> 8U);
            }
        }
        quirc_end(decoder.get());
        const auto count = quirc_count(decoder.get());
        for (int index = 0; index < count; ++index) {
            quirc_code code{};
            quirc_data data{};
            quirc_extract(decoder.get(), index, &code);
            auto error = quirc_decode(&code, &data);
            if (error != QUIRC_SUCCESS) {
                quirc_flip(&code);
                error = quirc_decode(&code, &data);
            }
            if (error == QUIRC_SUCCESS) {
                if (auto text = utf8Text(data.payload, data.payload_len);
                    text.has_value() && !text->empty()) {
                    return text;
                }
            }
        }
    } catch (...) {
    }
    return std::nullopt;
}

} // namespace xxsnap::win
