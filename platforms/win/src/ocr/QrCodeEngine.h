#pragma once

#include "capture/CaptureBackend.h"

#include <optional>
#include <string>

namespace xxsnap::win {

std::optional<std::wstring> recognizeQrCode(
    const PixelBuffer& pixels) noexcept;

} // namespace xxsnap::win
