#pragma once

#include "capture/CaptureBackend.h"

#include <string>

namespace xxsnap::win {

enum class OcrStatus {
    completed,
    empty,
    unavailable,
    failed,
};

enum class OcrContentKind {
    text,
    qrCode,
};

struct OcrResult {
    OcrStatus status = OcrStatus::failed;
    std::wstring text;
    HRESULT nativeCode = E_FAIL;
    OcrContentKind contentKind = OcrContentKind::text;
};

OcrResult recognizeText(const PixelBuffer& pixels) noexcept;

} // namespace xxsnap::win
