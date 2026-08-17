#pragma once

#include "annotation/AnnotationTypes.h"

#include <Windows.h>
#include <d2d1.h>

namespace xxsnap::win {

HRESULT drawMarkerLine(
    ID2D1RenderTarget* renderTarget,
    const ShapeAnnotation& annotation) noexcept;

} // namespace xxsnap::win
