#pragma once

#include "annotation/AnnotationTypes.h"

#include <Windows.h>
#include <d2d1.h>

namespace xxsnap::win {

HRESULT drawBrushPath(
    ID2D1Factory* factory,
    ID2D1RenderTarget* renderTarget,
    const ShapeAnnotation& annotation) noexcept;

} // namespace xxsnap::win
