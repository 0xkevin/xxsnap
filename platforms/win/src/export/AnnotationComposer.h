#pragma once

#include "annotation/AnnotationRenderer.h"
#include "capture/CaptureBackend.h"

#include <optional>

namespace xxsnap::win {

std::optional<CaptureError> composeAnnotations(
    PixelBuffer& pixels,
    const AnnotationRenderPlan& plan,
    UINT dpiX,
    UINT dpiY) noexcept;

} // namespace xxsnap::win
