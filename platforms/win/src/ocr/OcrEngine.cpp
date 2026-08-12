#include "ocr/OcrEngine.h"
#include "ocr/QrCodeEngine.h"

#include <algorithm>
#include <cstring>
#include <limits>

#if defined(XXSNAP_MODERN)
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#endif

namespace xxsnap::win {
namespace {

void trim(std::wstring& text)
{
    const auto whitespace = [](wchar_t value) {
        return value == L' ' || value == L'\t' || value == L'\r'
            || value == L'\n' || value == L'\f' || value == L'\v';
    };
    const auto first = std::find_if_not(text.begin(), text.end(), whitespace);
    const auto last = std::find_if_not(text.rbegin(), text.rend(), whitespace)
        .base();
    if (first >= last) {
        text.clear();
        return;
    }
    text.assign(first, last);
}

#if defined(XXSNAP_MODERN)
struct __declspec(uuid("5B0D3235-4DBA-4D44-8658-1D0E4FD04D7F"))
IMemoryBufferByteAccess : IUnknown {
    virtual HRESULT STDMETHODCALLTYPE GetBuffer(
        BYTE** value, UINT32* capacity) = 0;
};
#endif

} // namespace

OcrResult recognizeText(const PixelBuffer& pixels) noexcept
{
    if (auto qrCode = recognizeQrCode(pixels)) {
        return {OcrStatus::completed, std::move(*qrCode), S_OK,
            OcrContentKind::qrCode};
    }
#if defined(XXSNAP_LEGACY)
    (void)pixels;
    return {OcrStatus::unavailable, {}, E_NOTIMPL};
#else
    if (pixels.width() <= 0 || pixels.height() <= 0
        || pixels.width() > (std::numeric_limits<int>::max)()
        || pixels.height() > (std::numeric_limits<int>::max)()
        || pixels.stride() > (std::numeric_limits<UINT32>::max)()) {
        return {OcrStatus::failed, {}, E_INVALIDARG};
    }
    try {
        using namespace winrt::Windows::Graphics::Imaging;
        using namespace winrt::Windows::Media::Ocr;

        SoftwareBitmap bitmap(
            BitmapPixelFormat::Bgra8,
            static_cast<int>(pixels.width()),
            static_cast<int>(pixels.height()),
            BitmapAlphaMode::Ignore);
        auto locked = bitmap.LockBuffer(BitmapBufferAccessMode::Write);
        auto reference = locked.CreateReference();
        auto access = reference.as<IMemoryBufferByteAccess>();
        BYTE* destination = nullptr;
        UINT32 capacity = 0;
        winrt::check_hresult(access->GetBuffer(&destination, &capacity));

        const auto plane = locked.GetPlaneDescription(0);
        if (plane.Width != pixels.width() || plane.Height != pixels.height()
            || plane.Stride <= 0 || plane.StartIndex < 0) {
            return {OcrStatus::failed, {}, E_FAIL};
        }
        const auto rowBytes = static_cast<std::uint64_t>(pixels.width()) * 4U;
        const auto lastRowEnd = static_cast<std::uint64_t>(plane.StartIndex)
            + static_cast<std::uint64_t>(pixels.height() - 1)
                * static_cast<std::uint64_t>(plane.Stride)
            + rowBytes;
        if (pixels.stride() < rowBytes || lastRowEnd > capacity) {
            return {OcrStatus::failed, {}, E_BOUNDS};
        }
        for (std::int64_t row = 0; row < pixels.height(); ++row) {
            std::memcpy(
                destination + plane.StartIndex
                    + static_cast<std::size_t>(row) * plane.Stride,
                pixels.data() + static_cast<std::size_t>(row) * pixels.stride(),
                static_cast<std::size_t>(rowBytes));
        }

        const auto engine = OcrEngine::TryCreateFromUserProfileLanguages();
        if (engine == nullptr) {
            return {OcrStatus::unavailable, {}, E_NOTIMPL};
        }
        std::wstring text = engine.RecognizeAsync(bitmap).get().Text().c_str();
        trim(text);
        return text.empty()
            ? OcrResult{OcrStatus::empty, {}, S_FALSE}
            : OcrResult{OcrStatus::completed, std::move(text), S_OK};
    } catch (const winrt::hresult_error& error) {
        return {OcrStatus::failed, {}, error.code()};
    } catch (...) {
        return {OcrStatus::failed, {}, E_FAIL};
    }
#endif
}

} // namespace xxsnap::win
