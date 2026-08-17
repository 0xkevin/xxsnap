#pragma once

#include "annotation/AnnotationRenderer.h"
#include "capture/CaptureBackend.h"

#include <optional>
#include <cstdint>

namespace xxsnap::win {

std::optional<CaptureError> composeAnnotations(
    PixelBuffer& pixels,
    const AnnotationRenderPlan& plan,
    UINT dpiX,
    UINT dpiY,
    std::int64_t contentOriginX = 0,
    std::int64_t contentOriginY = 0,
    const PixelBuffer* magnifierSource = nullptr,
    const std::vector<EraserMask>& eraserMasks = {}) noexcept;

} // namespace xxsnap::win
